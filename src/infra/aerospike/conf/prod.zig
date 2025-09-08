const std = @import("std");
const net = @import("../net/mod.zig");
const service = @import("../service/mod.zig");
const nsplan = @import("../nsplan.zig");

/// Production Aerospike server configuration template (aerospike.conf).
/// Focus: performance and durability, while remaining DRY and modular.
/// Composes existing renderers:
/// - service { rack-id (per-host), migrate { threads, sleep-us } }
/// - network { heartbeat { mesh w/ seeds }, fabric { port, threads } }
/// - namespace <name> { durable writes, ttl, eviction, defrag, nsup, devices }
///
/// Notes:
/// - Provide at least 2 unique mesh seeds for heartbeat in production.
/// - Defaults below are conservative; tune based on CPU, disk, and workload.
pub const ProdTemplate = struct {
    /// Hostname/identifier for this node; used for rack-id emission.
    host: []const u8 = "node-1",

    /// Production mesh seeds (adjust per environment). Must be >= 2 unique entries.
    mesh_seeds: []const net.heartbeat.HostPort = &.{
        .{ .host = "10.0.0.1", .port = 3002 },
        .{ .host = "10.0.0.2", .port = 3002 },
        .{ .host = "10.0.0.3", .port = 3002 },
    },

    /// Namespace parameters (tune sizing and pathing for production disks/volumes).
    ns_name: []const u8 = "prod",
    ns_memory_size_bytes: u64 = 8_589_934_592, // 8 GiB in-memory budget (example)
    ns_device_path: []const u8 = "/var/lib/aerospike/prod.dat",
    ns_device_size_bytes: u64 = 137_438_953_472, // 128 GiB device size (example)

    /// Replication and durability safety rails.
    replication_factor: u8 = 3,
    stop_writes_pct: u8 = 90,

    /// Performance-oriented tuning (adjust to CPU cores and workload):
    migrate_threads: u16 = 8,
    fabric_threads: u16 = 8,
    hb_interval_ms: u16 = 150,
    hb_timeout_ms: u32 = 10_000,

    /// Render the full prod aerospike.conf into the given writer.
    pub fn renderInto(self: ProdTemplate, w: anytype) !void {
        // Header
        try w.print("# Aerospike production configuration template (generated)\n", .{});
        try w.print("# Focus: performance & durability. Tune threads, RF, and devices per node.\n\n", .{});

        // --- service block ---
        try w.print("service {\n", .{});
        var rack_cfg: service.rack.RackConfig = .{};
        try rack_cfg.renderServiceForHost(w, "    ", self.host);
        var mig: service.migrate.MigrateConfig = .{ .threads = self.migrate_threads };
        try mig.renderInto(w, "    ");
        try w.print("}\n\n", .{});

        // --- network block ---
        try w.print("network {\n", .{});
        var hb: net.heartbeat.HeartbeatConfig = .{
            .mode = .mesh,
            .port = 3002,
            .interval_ms = self.hb_interval_ms,
            .timeout_ms = self.hb_timeout_ms,
            .mesh_seeds = self.mesh_seeds,
        };
        try hb.renderInto(w, "    ");
        var fab: net.fabric.FabricConfig = .{ .threads = self.fabric_threads };
        try fab.renderInto(w, "    ");
        try w.print("}\n\n", .{});

        // --- namespace block ---
        var plan = nsplan.singleDevice(self.ns_name, self.ns_memory_size_bytes, self.ns_device_path, self.ns_device_size_bytes);
        plan.replication_factor = self.replication_factor;
        plan.durable.stop_writes_pct = self.stop_writes_pct;
        try plan.renderPseudoConf(w);
    }
};