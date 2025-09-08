const std = @import("std");
const net = @import("../net/mod.zig");
const types = @import("types.zig");

/// Enumerate network-related knobs (heartbeat, fabric).
pub const NetworkKnobs = struct {
    pub fn list() []const types.Knob {
        return &.{
            // Heartbeat
            .{ .key = "heartbeat.mode", .section = "heartbeat", .scope = .network, .kind = .enum_, .description = "Cluster heartbeat mode: mesh or multicast", .ce_supported = true },
            .{ .key = "heartbeat.port", .section = "heartbeat", .scope = .network, .kind = .uint, .description = "Heartbeat UDP port", .ce_supported = true },
            .{ .key = "heartbeat.interval-ms", .section = "heartbeat", .scope = .network, .kind = .duration_ms, .description = "Heartbeat interval (ms)", .ce_supported = true },
            .{ .key = "heartbeat.timeout-ms", .section = "heartbeat", .scope = .network, .kind = .duration_ms, .description = "Heartbeat timeout (ms)", .ce_supported = true },
            .{ .key = "heartbeat.mesh-seed", .section = "heartbeat", .scope = .network, .kind = .list, .description = "Mesh seed host:port entries (repeatable)", .ce_supported = true },
            .{ .key = "heartbeat.multicast-group", .section = "heartbeat", .scope = .network, .kind = .string, .description = "Multicast group address", .ce_supported = true },
            .{ .key = "heartbeat.multicast-port", .section = "heartbeat", .scope = .network, .kind = .uint, .description = "Multicast port", .ce_supported = true },

            // Fabric
            .{ .key = "fabric.port", .section = "fabric", .scope = .network, .kind = .uint, .description = "Fabric TCP port for intra-cluster traffic", .ce_supported = true },
            .{ .key = "fabric.threads", .section = "fabric", .scope = .network, .kind = .uint, .description = "Fabric worker threads", .ce_supported = true },
        };
    }

    pub fn renderInto(w: anytype, indent: []const u8) !void {
        try types.renderKnobList(w, indent, "Network knobs", NetworkKnobs.list());
    }
};