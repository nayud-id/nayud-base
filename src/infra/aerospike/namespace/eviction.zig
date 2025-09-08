const std = @import("std");

pub const Errors = error{ InvalidEvictPct };

/// Eviction policy for in-memory namespaces.
/// Aerospike evicts least-recently-used (LRU) objects when memory is under pressure.
pub const EvictionConfig = struct {
    /// Percentage of memory at which to begin evicting. Typical 5..90
    evict_tenths_pct: u8 = 10, // start near 10%; caller can tune

    pub fn validate(self: EvictionConfig) Errors!void {
        // Accept 0..99 tenths percent, where 0 disables eviction trigger.
        // We model as integer percent to keep simple; extend later if needed.
        if (self.evict_tenths_pct >= 100) return Errors.InvalidEvictPct;
    }

    pub fn renderInto(self: EvictionConfig, w: anytype, indent: []const u8) !void {
        try self.validate();
        try w.print("{s}# Eviction policy\n", .{indent});
        // Map to pseudo key 'evict-pct'; real mapping can be adjusted later
        try w.print("{s}evict-pct {}\n", .{ indent, self.evict_tenths_pct });
    }
};