const std = @import("std");
const service = @import("../service/mod.zig");
const types = @import("types.zig");

/// Enumerate service-level (global) configuration knobs.
/// We reference existing modules (migrate, rack) to stay DRY on names and semantics.
pub const GlobalKnobs = struct {
    pub fn list() []const types.Knob {
        // Static storage for zero-alloc return.
        return &.{
            .{ .key = "migrate.threads", .section = "migrate", .scope = .global, .kind = .uint, .description = "Number of migrate (rebalance) threads", .ce_supported = true },
            .{ .key = "migrate.sleep-us", .section = "migrate", .scope = .global, .kind = .uint, .description = "Optional backoff per batch in microseconds", .ce_supported = true },
            .{ .key = "rack-id", .section = "service", .scope = .global, .kind = .uint, .description = "Per-node rack identifier for rack-aware placement", .ce_supported = true },
        };
    }

    pub fn renderInto(w: anytype, indent: []const u8) !void {
        try types.renderKnobList(w, indent, "Global (service-level) knobs", GlobalKnobs.list());
    }
};