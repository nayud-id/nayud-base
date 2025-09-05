const std = @import("std");
const build_options = @import("build_options");

pub const Error = error{
    AerospikeDisabled,
    ConnectionFailed,
    OperationFailed,
    InvalidArgument,
    UnsupportedValueType,
    NotFound,
};

pub const Value = union(enum) {
    int: i64,
    // For now we only support integer values in minimal wrapper to keep C interop predictable.
    // Extend with more variants (str, bytes, float, bool) as needed.
};

// High-level client configuration (policies + socket) exposed to consumers.
pub const Replica = enum { master, any };
pub const ConsistencyLevel = enum { one, all };
pub const CommitLevel = enum { commit_all, commit_master };
pub const GenerationPolicy = enum { none, eq, gt };

pub const Timeouts = struct {
    connect_ms: u32 = 500,
    read_ms: u32 = 15,
    write_ms: u32 = 15,
    total_ms: u32 = 10_000,
};

pub const Retries = struct {
    max_retries: u32 = 2,
    sleep_between_retries_ms: u32 = 10,
    retry_on_timeout: bool = true,
};

pub const ReadPolicy = struct {
    replica: Replica = .master,
    consistency_level: ConsistencyLevel = .one,
    allow_partial_results: bool = false,
};

pub const WritePolicy = struct {
    commit_level: CommitLevel = .commit_all,
    generation_policy: GenerationPolicy = .none,
    durable_delete: bool = false,
    send_key: bool = true,
};

pub const BatchPolicy = struct {
    max_concurrency: u32 = 64,
    allow_inline: bool = true,
    send_set_name: bool = false,
    max_retries: u32 = 2,
    sleep_between_retries_ms: u32 = 10,
};

pub const ScanPolicy = struct {
    // Extend with scan-specific knobs later as needed
    // Placeholder keeps interface consistent
    _reserved: u8 = 0,
};

pub const QueryPolicy = struct {
    // Extend with query-specific knobs later as needed
    _reserved: u8 = 0,
};

pub const AdminPolicy = struct {
    // Extend with admin-specific knobs later as needed
    _reserved: u8 = 0,
};

pub const SocketPolicy = struct {
    max_connections_per_node: u32 = 300,
    connection_idle_timeout_ms: u32 = 60_000,
    login_timeout_ms: u32 = 5_000,
};

pub const ClientPolicies = struct {
    timeouts: Timeouts = .{},
    retries: Retries = .{},
    read: ReadPolicy = .{},
    write: WritePolicy = .{},
    batch: BatchPolicy = .{},
    scan: ScanPolicy = .{},
    query: QueryPolicy = .{},
    admin: AdminPolicy = .{},
    socket: SocketPolicy = .{},
};

pub const Config = struct {
    // Namespaces/sets are app-level and not included here; this is transport + policy config.
    policies: ClientPolicies = .{},
};

pub const Seed = struct { host: []const u8, port: u16 = 3000 };

// Select implementation based on build flag. When Aerospike C client headers/libs
// are not available, provide a no-op stub implementation that compiles.
pub const Client = if (build_options.aerospike) RealClient else DummyClient;

// Dual-cluster support: independent client pools and per-cluster health tracking.
pub const HealthStatus = enum { healthy, degraded, down };

pub const ClusterHealth = struct {
    consecutive_failures: u32 = 0,
    last_success_ms: u64 = 0,
    last_error_ms: u64 = 0,
    status: HealthStatus = .healthy,

    fn recordSuccess(self: *ClusterHealth, now_ms: u64) void {
        self.consecutive_failures = 0;
        self.last_success_ms = now_ms;
        self.status = .healthy;
    }

    fn recordFailure(self: *ClusterHealth, now_ms: u64) void {
        self.consecutive_failures += 1;
        self.last_error_ms = now_ms;
        // Basic heuristic: 1 failure => degraded, >=3 => down
        self.status = if (self.consecutive_failures >= 3) .down else .degraded;
    }

    pub fn snapshot(self: *const ClusterHealth) ClusterHealth {
        return self.*;
    }
};

pub const DualClient = struct {
    pub const Side = enum { primary, secondary };

    allocator: std.mem.Allocator,
    primary: Client,
    secondary: Client,
    primary_health: ClusterHealth = .{},
    secondary_health: ClusterHealth = .{},
    cfg: Config,

    fn nowMs() u64 {
        // milliTimestamp returns i128; clamp to u64 for storage
        const ts: i128 = std.time.milliTimestamp();
        return @intCast(if (ts < 0) 0 else ts);
    }

    pub fn connect(
        allocator: std.mem.Allocator,
        primary_seeds: []const Seed,
        secondary_seeds: []const Seed,
        cfg: Config,
    ) Error!DualClient {
        if (primary_seeds.len == 0 or secondary_seeds.len == 0) return Error.InvalidArgument;

        var p = try Client.connectWithConfig(allocator, primary_seeds, cfg);
        errdefer p.close();
        var s = try Client.connectWithConfig(allocator, secondary_seeds, cfg);
        errdefer s.close();

        var dc: DualClient = .{
            .allocator = allocator,
            .primary = p,
            .secondary = s,
            .cfg = cfg,
        };
        // Initial health marks as success at creation time
        const now = nowMs();
        dc.primary_health.recordSuccess(now);
        dc.secondary_health.recordSuccess(now);
        return dc;
    }

    pub fn close(self: *DualClient) void {
        self.primary.close();
        self.secondary.close();
    }

    pub fn recordResult(self: *DualClient, side: Side, ok: bool) void {
        const now = nowMs();
        switch (side) {
            .primary => if (ok) self.primary_health.recordSuccess(now) else self.primary_health.recordFailure(now),
            .secondary => if (ok) self.secondary_health.recordSuccess(now) else self.secondary_health.recordFailure(now),
        }
    }

    pub fn health(self: *const DualClient) struct { primary: ClusterHealth, secondary: ClusterHealth } {
        return .{ .primary = self.primary_health, .secondary = self.secondary_health };
    }

    fn clientPtr(self: *DualClient, side: Side) *Client {
        return switch (side) {
            .primary => &self.primary,
            .secondary => &self.secondary,
        };
    }

    pub fn putBoth(self: *DualClient, ns: []const u8, set: []const u8, key: []const u8, bin_name: []const u8, value: Value) Error!void {
        var err_p: ?Error = null;
        var err_s: ?Error = null;

        self.primary.put(ns, set, key, bin_name, value) catch |e| {
            err_p = e;
        };
        self.recordResult(.primary, err_p == null);

        self.secondary.put(ns, set, key, bin_name, value) catch |e| {
            err_s = e;
        };
        self.recordResult(.secondary, err_s == null);

        if (err_p != null or err_s != null) return Error.OperationFailed;
    }

    pub fn getFrom(self: *DualClient, side: Side, ns: []const u8, set: []const u8, key: []const u8) Error!void {
        var ok = true;
        self.clientPtr(side).*.get(ns, set, key) catch |e| {
            // Treat NotFound as a healthy response
            ok = (e == Error.NotFound);
            if (!ok) return e;
        };
        self.recordResult(side, ok);
    }
};

const DummyClient = struct {
    pub fn connect(_: std.mem.Allocator, _: []const u8, _: u16) Error!DummyClient {
        return Error.AerospikeDisabled;
    }
    pub fn connectWithConfig(_: std.mem.Allocator, _: []const Seed, _: Config) Error!DummyClient {
        return Error.AerospikeDisabled;
    }
    pub fn close(_: *DummyClient) void {}
    pub fn put(_: *DummyClient, _: []const u8, _: []const u8, _: []const u8, _: []const u8, _: Value) Error!void {
        return Error.AerospikeDisabled;
    }
    pub fn get(_: *DummyClient, _: []const u8, _: []const u8, _: []const u8) Error!void {
        return Error.AerospikeDisabled;
    }
    pub fn operateIncr(_: *DummyClient, _: []const u8, _: []const u8, _: []const u8, _: []const u8, _: i64) Error!void {
        return Error.AerospikeDisabled;
    }
    pub fn batchGet(_: *DummyClient, _: []const u8, _: []const u8, _: [][]const u8) Error!void {
        return Error.AerospikeDisabled;
    }
    pub fn queryAll(_: *DummyClient, _: []const u8, _: []const u8) Error!void {
        return Error.AerospikeDisabled;
    }
};

const RealClient = if (build_options.aerospike) struct {
    const c = @cImport({
        @cInclude("aerospike/aerospike.h");
        @cInclude("aerospike/as_config.h");
        @cInclude("aerospike/as_policy.h");
        @cInclude("aerospike/aerospike_key.h");
        @cInclude("aerospike/as_record.h");
        @cInclude("aerospike/as_key.h");
        @cInclude("aerospike/as_operations.h");
        @cInclude("aerospike/aerospike_batch.h");
        @cInclude("aerospike/aerospike_query.h");
        @cInclude("aerospike/as_query.h");
        @cInclude("aerospike/as_status.h");
    });

    as: c.aerospike = undefined,
    connected: bool = false,

    fn toCStrZ(allocator: std.mem.Allocator, s: []const u8) ![:0]u8 {
        var buf = try allocator.alloc(u8, s.len + 1);
        std.mem.copy(u8, buf[0..s.len], s);
        buf[s.len] = 0;
        return @ptrCast(buf[0..s.len :0]);
    }

    fn setIfField(comptime T: type, ptr: anytype, comptime name: []const u8, value: anytype) void {
        if (@hasField(T, name)) {
            @field(ptr.*, name) = value;
        }
    }

    fn mapReplica(rep: Replica) c.as_policy_replica {
        return switch (rep) {
            .master => c.AS_POLICY_REPLICA_MASTER,
            .any => c.AS_POLICY_REPLICA_ANY,
        };
    }

    fn mapConsistency(cns: ConsistencyLevel) c.as_policy_consistency_level {
        return switch (cns) {
            .one => c.AS_POLICY_CONSISTENCY_ONE,
            .all => c.AS_POLICY_CONSISTENCY_ALL,
        };
    }

    fn mapCommitLevel(cl: CommitLevel) c.as_policy_commit_level {
        return switch (cl) {
            .commit_all => c.AS_POLICY_COMMIT_LEVEL_ALL,
            .commit_master => c.AS_POLICY_COMMIT_LEVEL_MASTER,
        };
    }

    fn mapGenPolicy(gp: GenerationPolicy) c.as_policy_gen {
        return switch (gp) {
            .none => c.AS_POLICY_GEN_IGNORE,
            .eq => c.AS_POLICY_GEN_EQ,
            .gt => c.AS_POLICY_GEN_GT,
        };
    }

    fn applyConfig(c_cfg: *c.as_config, cfg: Config) void {
        // Socket/global settings
        setIfField(@TypeOf(c_cfg.*), c_cfg, "conn_timeout_ms", cfg.policies.timeouts.connect_ms);
        setIfField(@TypeOf(c_cfg.*), c_cfg, "login_timeout_ms", cfg.policies.socket.login_timeout_ms);
        setIfField(@TypeOf(c_cfg.*), c_cfg, "max_conns_per_node", cfg.policies.socket.max_connections_per_node);
        setIfField(@TypeOf(c_cfg.*), c_cfg, "conn_idle_ms", cfg.policies.socket.connection_idle_timeout_ms);

        // Default policies present on as_config.policies
        if (@hasField(@TypeOf(c_cfg.*), "policies")) {
            const policies_ptr = &c_cfg.policies;

            if (@hasField(@TypeOf(policies_ptr.*), "read")) {
                const rp = &policies_ptr.read;
                // timeouts
                setIfField(@TypeOf(rp.*), rp, "total_timeout", cfg.policies.timeouts.read_ms);
                // retries
                setIfField(@TypeOf(rp.*), rp, "max_retries", cfg.policies.retries.max_retries);
                setIfField(@TypeOf(rp.*), rp, "sleep_between_retries", cfg.policies.retries.sleep_between_retries_ms);
                setIfField(@TypeOf(rp.*), rp, "retry_on_timeout", cfg.policies.retries.retry_on_timeout);
                // booleans/enums
                if (@hasField(@TypeOf(rp.*), "replica")) rp.replica = mapReplica(cfg.policies.read.replica);
                if (@hasField(@TypeOf(rp.*), "consistency_level")) rp.consistency_level = mapConsistency(cfg.policies.read.consistency_level);
                setIfField(@TypeOf(rp.*), rp, "allow_partial_results", cfg.policies.read.allow_partial_results);
            }

            if (@hasField(@TypeOf(policies_ptr.*), "write")) {
                const wp = &policies_ptr.write;
                setIfField(@TypeOf(wp.*), wp, "total_timeout", cfg.policies.timeouts.write_ms);
                setIfField(@TypeOf(wp.*), wp, "max_retries", cfg.policies.retries.max_retries);
                setIfField(@TypeOf(wp.*), wp, "sleep_between_retries", cfg.policies.retries.sleep_between_retries_ms);
                setIfField(@TypeOf(wp.*), wp, "retry_on_timeout", cfg.policies.retries.retry_on_timeout);
                if (@hasField(@TypeOf(wp.*), "commit_level")) wp.commit_level = mapCommitLevel(cfg.policies.write.commit_level);
                if (@hasField(@TypeOf(wp.*), "generation_policy")) wp.generation_policy = mapGenPolicy(cfg.policies.write.generation_policy);
                setIfField(@TypeOf(wp.*), wp, "durable_delete", cfg.policies.write.durable_delete);
                setIfField(@TypeOf(wp.*), wp, "send_key", cfg.policies.write.send_key);
            }

            if (@hasField(@TypeOf(policies_ptr.*), "batch")) {
                const bp = &policies_ptr.batch;
                // Favor total_ms as overall batch timeout
                setIfField(@TypeOf(bp.*), bp, "total_timeout", cfg.policies.timeouts.total_ms);
                setIfField(@TypeOf(bp.*), bp, "max_retries", cfg.policies.batch.max_retries);
                setIfField(@TypeOf(bp.*), bp, "sleep_between_retries", cfg.policies.batch.sleep_between_retries_ms);
                setIfField(@TypeOf(bp.*), bp, "retry_on_timeout", cfg.policies.retries.retry_on_timeout);
                setIfField(@TypeOf(bp.*), bp, "allow_inline", cfg.policies.batch.allow_inline);
                setIfField(@TypeOf(bp.*), bp, "send_set_name", cfg.policies.batch.send_set_name);
                // concurrency field names vary; try common ones
                setIfField(@TypeOf(bp.*), bp, "concurrent_max", cfg.policies.batch.max_concurrency);
                setIfField(@TypeOf(bp.*), bp, "max_concurrent_threads", cfg.policies.batch.max_concurrency);
            }

            if (@hasField(@TypeOf(policies_ptr.*), "query")) {
                const qp = &policies_ptr.query;
                setIfField(@TypeOf(qp.*), qp, "total_timeout", cfg.policies.timeouts.total_ms);
            }

            if (@hasField(@TypeOf(policies_ptr.*), "scan")) {
                const sp = &policies_ptr.scan;
                setIfField(@TypeOf(sp.*), sp, "total_timeout", cfg.policies.timeouts.total_ms);
            }

            if (@hasField(@TypeOf(policies_ptr.*), "admin")) {
                const ap = &policies_ptr.admin;
                setIfField(@TypeOf(ap.*), ap, "total_timeout", cfg.policies.timeouts.total_ms);
            }
        }
    }

    pub fn connect(allocator: std.mem.Allocator, host: []const u8, port: u16) Error!RealClient {
        // Backward-compat convenience: single seed with default policies
        const seeds = [_]Seed{.{ .host = host, .port = port }};
        return connectWithConfig(allocator, &seeds, .{});
    }

    pub fn connectWithConfig(allocator: std.mem.Allocator, seeds: []const Seed, cfg: Config) Error!RealClient {
        var client: RealClient = .{};

        var c_cfg: c.as_config = undefined;
        _ = c.as_config_init(&c_cfg);

        // Add all seeds
        var i: usize = 0;
        while (i < seeds.len) : (i += 1) {
            const host_z = toCStrZ(allocator, seeds[i].host) catch {
                // If we cannot allocate, fallback to fail connect cleanly
                return Error.ConnectionFailed;
            };
            defer allocator.free(host_z);
            _ = c.as_config_add_host(&c_cfg, host_z, seeds[i].port);
        }

        // Apply policies and socket settings
        applyConfig(&c_cfg, cfg);

        _ = c.aerospike_init(&client.as, &c_cfg);

        var err: c.as_error = undefined;
        if (c.aerospike_connect(&client.as, &err) != c.AEROSPIKE_OK) {
            _ = c.aerospike_destroy(&client.as);
            return Error.ConnectionFailed;
        }
        client.connected = true;
        return client;
    }

    pub fn close(self: *RealClient) void {
        if (self.connected) {
            var err: c.as_error = undefined;
            _ = c.aerospike_close(&self.as, &err);
            _ = c.aerospike_destroy(&self.as);
            self.connected = false;
        }
    }

    pub fn put(self: *RealClient, ns: []const u8, set: []const u8, key: []const u8, bin_name: []const u8, value: Value) Error!void {
        if (!self.connected) return Error.OperationFailed;
        var err: c.as_error = undefined;

        const ns_z = try toCStrZ(std.heap.page_allocator, ns);
        defer std.heap.page_allocator.free(ns_z);
        const set_z = try toCStrZ(std.heap.page_allocator, set);
        defer std.heap.page_allocator.free(set_z);
        const key_z = try toCStrZ(std.heap.page_allocator, key);
        defer std.heap.page_allocator.free(key_z);
        const bin_z = try toCStrZ(std.heap.page_allocator, bin_name);
        defer std.heap.page_allocator.free(bin_z);

        var akey: c.as_key = undefined;
        _ = c.as_key_init_str(&akey, ns_z, set_z, key_z);

        var rec: c.as_record = undefined;
        _ = c.as_record_inita(&rec, 1);

        switch (value) {
            .int => |v| {
                _ = c.as_record_set_int64(&rec, bin_z, v);
            },
        }

        if (c.aerospike_key_put(&self.as, &err, null, &akey, &rec) != c.AEROSPIKE_OK) {
            _ = c.as_record_destroy(&rec);
            return Error.OperationFailed;
        }
        _ = c.as_record_destroy(&rec);
    }

    pub fn get(self: *RealClient, ns: []const u8, set: []const u8, key: []const u8) Error!void {
        if (!self.connected) return Error.OperationFailed;
        var err: c.as_error = undefined;

        const ns_z = try toCStrZ(std.heap.page_allocator, ns);
        defer std.heap.page_allocator.free(ns_z);
        const set_z = try toCStrZ(std.heap.page_allocator, set);
        defer std.heap.page_allocator.free(set_z);
        const key_z = try toCStrZ(std.heap.page_allocator, key);
        defer std.heap.page_allocator.free(key_z);

        var akey: c.as_key = undefined;
        _ = c.as_key_init_str(&akey, ns_z, set_z, key_z);

        var rec: ?*c.as_record = null;
        if (c.aerospike_key_get(&self.as, &err, null, &akey, &rec) != c.AEROSPIKE_OK) {
            if (err.code == c.AEROSPIKE_ERR_RECORD_NOT_FOUND) return Error.NotFound;
            return Error.OperationFailed;
        }
        if (rec) |r| {
            _ = c.as_record_destroy(r);
        }
    }

    pub fn operateIncr(self: *RealClient, ns: []const u8, set: []const u8, key: []const u8, bin_name: []const u8, delta: i64) Error!void {
        if (!self.connected) return Error.OperationFailed;
        var err: c.as_error = undefined;

        const ns_z = try toCStrZ(std.heap.page_allocator, ns);
        defer std.heap.page_allocator.free(ns_z);
        const set_z = try toCStrZ(std.heap.page_allocator, set);
        defer std.heap.page_allocator.free(set_z);
        const key_z = try toCStrZ(std.heap.page_allocator, key);
        defer std.heap.page_allocator.free(key_z);
        const bin_z = try toCStrZ(std.heap.page_allocator, bin_name);
        defer std.heap.page_allocator.free(bin_z);

        var akey: c.as_key = undefined;
        _ = c.as_key_init_str(&akey, ns_z, set_z, key_z);

        var ops: c.as_operations = undefined;
        _ = c.as_operations_inita(&ops, 1);
        _ = c.as_operations_add_incr(&ops, bin_z, delta);

        var rec: ?*c.as_record = null;
        if (c.aerospike_key_operate(&self.as, &err, null, &akey, &ops, &rec) != c.AEROSPIKE_OK) {
            _ = c.as_operations_destroy(&ops);
            if (rec) |_| _ = c.as_record_destroy(rec.?);
            return Error.OperationFailed;
        }
        _ = c.as_operations_destroy(&ops);
        if (rec) |r| _ = c.as_record_destroy(r);
    }

    pub fn batchGet(self: *RealClient, ns: []const u8, set: []const u8, keys: [][]const u8) Error!void {
        if (!self.connected) return Error.OperationFailed;
        // Minimal placeholder; full batch API will be added later.
        // For now, iterate and call get() individually.
        var i: usize = 0;
        while (i < keys.len) : (i += 1) {
            try self.get(ns, set, keys[i]);
        }
    }

    pub fn queryAll(_: *RealClient, _: []const u8, _: []const u8) Error!void {
        // Minimal wrapper does not implement server-side Query yet.
        // A proper implementation will construct as_query and iterate with callbacks.
        return Error.OperationFailed;
    }
} else DummyClient;