const std = @import("std");
const net = @import("../net/mod.zig");
const service = @import("../service/mod.zig");
const nsplan = @import("../nsplan.zig");

/// Development/Test Aerospike server configuration template (aerospike.conf).
/// Composes existing renderers (DRY) to produce a clean, minimal template:
/// - service { rack-id (per-host), migrate { ... } }
/// - network { heartbeat { ... }, fabric { ... } }
/// - namespace <name> { durable writes, ttl, eviction, defrag, nsup, devices }
///
/// All values here are safe defaults for local dev/test. Adjust seeds/devices per environment.
pub const DevTemplate = struct {
    /// Hostname or identifier of the current node; used to render rack-id hint/line.
    host: []const u8 = "localhost",

    /// Optional: override seed hosts for heartbeat mesh (must be >= 2 unique entries).
    /// Defaults provide a working mesh for a tiny dev/test cluster when adjusted per node.
    mesh_seeds: []const net.heartbeat.HostPort = &.{
        .{ .host = "127.0.0.1", .port = 3002 },
        .{ .host = "127.0.0.2", .port = 3002 },
    },

    /// Optional: override the single-device namespace parameters (path/sizes tuned for dev/test).
    ns_name: []const u8 = "test",
    ns_memory_size_bytes: u64 = 1_073_741_824, // 1 GiB in-memory budget
    ns_device_path: []const u8 = "/opt/aerospike/data/test.dat",
    ns_device_size_bytes: u64 = 2_147_483_648, // 2 GiB device size (dev/test)

    /// Render the full dev/test aerospike.conf into the given writer.
    pub fn renderInto(self: DevTemplate, w: anytype) !void {
        // Header
        try w.print("# Aerospike dev/test configuration template (generated)\n", .{});
        try w.print("# Adjust seeds, rack-id assignments, and device paths for your environment.\n\n", .{});

        // --- service block ---
        try w.print("service {\n", .{});
        // Rack-id (if rack awareness enabled/assigned) and hints
        var rack_cfg: service.rack.RackConfig = .{};
        try rack_cfg.renderServiceForHost(w, "    ", self.host);
        // Migrate tuning (nested block)
        var mig: service.migrate.MigrateConfig = .{};
        try mig.renderInto(w, "    ");
        try w.print("}\n\n", .{});

        // --- network block ---
        try w.print("network {\n", .{});
        var hb: net.heartbeat.HeartbeatConfig = .{
            .mode = .mesh,
            .port = 3002,
            .interval_ms = 150,
            .timeout_ms = 10_000,
            .mesh_seeds = self.mesh_seeds,
        };
        try hb.renderInto(w, "    ");
        var fab: net.fabric.FabricConfig = .{};
        try fab.renderInto(w, "    ");
        try w.print("}\n\n", .{});

        // --- namespace block ---
        var plan = nsplan.singleDevice(self.ns_name, self.ns_memory_size_bytes, self.ns_device_path, self.ns_device_size_bytes);
        try plan.renderPseudoConf(w);
    }
};