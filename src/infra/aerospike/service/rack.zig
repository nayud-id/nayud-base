const std = @import("std");

/// Errors for rack-awareness planning and validation.
pub const Errors = error{ MissingAssignments, InvalidRackId, DuplicateHost, InvalidHost };

/// Simple mapping of a node host to a rack id.
/// Rack IDs are positive integers (>= 1). Keep mapping explicit and zero-alloc.
pub const HostRack = struct {
    host: []const u8,
    rack_id: u16,
};

/// Rack-awareness planner for Aerospike service/namespace settings.
/// - enabled: master switch to emit rack-related config
/// - assignments: explicit host -> rack-id mapping (caller-owned slice)
///
/// Zero-alloc: all helpers operate on caller-provided data and writers.
pub const RackConfig = struct {
    enabled: bool = false,
    assignments: []const HostRack = &.{},

    /// Validate mapping correctness when enabled.
    pub fn validate(self: RackConfig) Errors!void {
        if (!self.enabled) return; // nothing to validate when disabled
        if (self.assignments.len == 0) return Errors.MissingAssignments;
        // host must be non-empty, rack_id >= 1, no duplicate hosts
        var i: usize = 0;
        while (i < self.assignments.len) : (i += 1) {
            const a = self.assignments[i];
            if (a.host.len == 0) return Errors.InvalidHost;
            if (a.rack_id == 0) return Errors.InvalidRackId;
            var j: usize = i + 1;
            while (j < self.assignments.len) : (j += 1) {
                if (std.mem.eql(u8, a.host, self.assignments[j].host)) {
                    return Errors.DuplicateHost;
                }
            }
        }
    }

    /// Find rack id for a given host if mapped.
    pub fn rackIdFor(self: RackConfig, host: []const u8) ?u16 {
        var i: usize = 0;
        while (i < self.assignments.len) : (i += 1) {
            if (std.mem.eql(u8, self.assignments[i].host, host)) {
                return self.assignments[i].rack_id;
            }
        }
        return null;
    }

    /// Count distinct rack IDs (0 if disabled).
    pub fn distinctRackCount(self: RackConfig) u16 {
        if (!self.enabled or self.assignments.len == 0) return 0;
        var count: u16 = 0;
        var i: usize = 0;
        while (i < self.assignments.len) : (i += 1) {
            const rid = self.assignments[i].rack_id;
            var seen = false;
            var j: usize = 0;
            while (j < i) : (j += 1) {
                if (self.assignments[j].rack_id == rid) { seen = true; break; }
            }
            if (!seen) count += 1;
        }
        return count;
    }

    /// Render the global service-level rack-id for a specific host (node).
    /// If disabled, prints a commented hint. Otherwise prints `rack-id <n>`
    /// when a mapping is found, or a commented note if missing.
    pub fn renderServiceForHost(self: RackConfig, w: anytype, indent: []const u8, host: []const u8) !void {
        if (!self.enabled) {
            try w.print("{s}# rack-id not set (rack-awareness disabled)\n", .{ indent });
            return;
        }
        try self.validate();
        if (self.rackIdFor(host)) |rid| {
            try w.print("{s}rack-id {}\n", .{ indent, rid });
        } else {
            try w.print("{s}# rack-id unknown for host '{s}' — add to assignments\n", .{ indent, host });
        }
    }

    /// Render a namespace-level hint to enable rack-aware placement when applicable.
    /// Some editions require feature support; we keep this as a pseudo-conf hint only.
    pub fn renderNamespaceHint(self: RackConfig, w: anytype, indent: []const u8) !void {
        if (!self.enabled) return;
        if (self.distinctRackCount() >= 2) {
            try w.print("{s}# rack-aware true   # enable if your edition supports rack-aware\n", .{ indent });
        }
    }
};