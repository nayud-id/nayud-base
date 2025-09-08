const std = @import("std");
const ns = @import("../namespace/mod.zig");
const types = @import("types.zig");

/// Enumerate namespace-level knobs across durability, TTL, eviction, defrag, nsup, replication, storage.
pub const NamespaceKnobs = struct {
    pub fn list() []const types.Knob {
        return &.{
            // Durability
            .{ .key = "stop-writes-pct", .section = "durable_writes", .scope = .namespace, .kind = .percent, .description = "Stop writes threshold (%)", .ce_supported = true },
            .{ .key = "commit-to-device", .section = "durable_writes", .scope = .namespace, .kind = .bool, .description = "Sync to device before ack", .ce_supported = true },
            .{ .key = "write-commit-level", .section = "durable_writes", .scope = .namespace, .kind = .enum_, .description = "Ack level: master or all", .ce_supported = true },

            // TTL
            .{ .key = "default-ttl", .section = "ttl", .scope = .namespace, .kind = .uint, .description = "Default TTL (seconds; 0=never)", .ce_supported = true },

            // Eviction
            .{ .key = "evict-pct", .section = "eviction", .scope = .namespace, .kind = .percent, .description = "Start eviction above this memory percent", .ce_supported = true },

            // Defrag
            .{ .key = "defrag-sleep", .section = "defrag", .scope = .namespace, .kind = .duration_ms, .description = "Sleep between defrag batches (ms)", .ce_supported = true },
            .{ .key = "defrag-threshold", .section = "defrag", .scope = .namespace, .kind = .percent, .description = "Defrag trigger threshold (%)", .ce_supported = true },

            // NSUP
            .{ .key = "nsup-period", .section = "nsup", .scope = .namespace, .kind = .uint, .description = "Namespace supervisor period (s)", .ce_supported = true },

            // Replication
            .{ .key = "replication-factor", .section = "general", .scope = .namespace, .kind = .uint, .description = "Replica count; must be >= 2 for HA", .ce_supported = true },

            // Storage engine (in-memory + devices modeled in nsplan)
            .{ .key = "storage-engine", .section = "storage", .scope = .namespace, .kind = .enum_, .description = "Engine type (e.g., memory)", .ce_supported = true },
            .{ .key = "device", .section = "storage", .scope = .namespace, .kind = .list, .description = "Persistence devices or files", .ce_supported = true },
        };
    }

    pub fn renderInto(w: anytype, indent: []const u8) !void {
        try types.renderKnobList(w, indent, "Namespace knobs", NamespaceKnobs.list());
    }
};