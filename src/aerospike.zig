const std = @import("std");
const build_options = @import("build_options");

pub const Error = error{
    AerospikeDisabled,
    ConnectionFailed,
    OperationFailed,
    InvalidArgument,
    UnsupportedValueType,
    NotFound,
    // New generation/idempotency-aware errors
    RecordExists,
    GenerationMismatch,
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

// New: policy to control how DualClient surfaces true conflicts
pub const ConflictHandling = enum { enqueue_repair, return_conflict };

// New: read preference for DualClient read routing
pub const ReadPreference = enum { prefer_primary, prefer_secondary, primary_only, secondary_only };

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

// New: expose key_exists_action in the WritePolicy API
pub const KeyExistsAction = enum { update, replace, create_only, update_only };

pub const WritePolicy = struct {
    commit_level: CommitLevel = .commit_all,
    generation_policy: GenerationPolicy = .none,
    key_exists_action: KeyExistsAction = .update,
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
    // New: how to handle true cross-cluster write conflicts
    conflict_policy: ConflictHandling = .enqueue_repair,
    // New: read preference and failover cooldown for graceful failback
    read_preference: ReadPreference = .prefer_primary,
    failover_cooldown_ms: u32 = 30_000,
    // Task16: health controller knobs
    health_probe_interval_ms: u32 = 1_000, // base probe period when healthy
    breaker_down_threshold: u32 = 3,       // failures to consider cluster down
    backoff_initial_ms: u32 = 1_000,       // starting backoff when degraded/down
    backoff_max_ms: u32 = 30_000,          // upper bound for exponential backoff
    failback_hysteresis_ms: u32 = 30_000,  // stable window before failing back
    // Task17: durable repair queue directory (relative to process cwd)
    repair_dir: []const u8 = "repair_queue",
};

pub const Seed = struct { host: []const u8, port: u16 = 3000 };

// New: top-level Side enum used for dual-cluster operations and repair items
pub const Side = enum { primary, secondary };

// New: Repair operation and item types for deferred reconciliation
pub const RepairOp = union(enum) {
    put: struct {
        bin_name: []u8,
        value: Value,
    },
    incr: struct {
        bin_name: []u8,
        delta: i64,
    },
};

pub const RepairItem = struct {
    ts_ms: u64,
    failed_side: Side,
    ns: []u8,
    set: []u8,
    key: []u8,
    op: RepairOp,
    err: Error,
    // Task17: persistence metadata
    attempts: u32 = 0,

    pub fn deinit(self: *RepairItem, allocator: std.mem.Allocator) void {
        allocator.free(self.ns);
        allocator.free(self.set);
        allocator.free(self.key);
        switch (self.op) {
            .put => |*p| allocator.free(p.bin_name),
            .incr => |*i| allocator.free(i.bin_name),
        }
    }

    // Serialize to a compact binary format with length-prefix strings
    pub fn serialize(self: *const RepairItem, allocator: std.mem.Allocator) ![]u8 {
        var buf = std.ArrayList(u8).init(allocator);
        errdefer buf.deinit();
        var w = buf.writer();
        try w.writeIntLittle(u64, self.ts_ms);
        try w.writeByte(@intFromEnum(self.failed_side));
        try w.writeByte(@intFromEnum(self.op)); // op tag
        try w.writeByte(@intFromEnum(self.err));
        try w.writeIntLittle(u32, self.attempts);
        // ns, set, key
        try w.writeIntLittle(u32, @intCast(self.ns.len));
        try w.writeAll(self.ns);
        try w.writeIntLittle(u32, @intCast(self.set.len));
        try w.writeAll(self.set);
        try w.writeIntLittle(u32, @intCast(self.key.len));
        try w.writeAll(self.key);
        // op payload
        switch (self.op) {
            .put => |p| {
                try w.writeIntLittle(u32, @intCast(p.bin_name.len));
                try w.writeAll(p.bin_name);
                // value: only int variant currently
                try w.writeByte(0); // value tag: int
                try w.writeIntLittle(i64, p.value.int);
            },
            .incr => |i| {
                try w.writeIntLittle(u32, @intCast(i.bin_name.len));
                try w.writeAll(i.bin_name);
                try w.writeIntLittle(i64, i.delta);
            },
        }
        return buf.toOwnedSlice();
    }

    pub fn deserialize(allocator: std.mem.Allocator, data: []const u8) !RepairItem {
        var s = std.io.fixedBufferStream(data);
        const r = s.reader();
        var item: RepairItem = undefined;
        item.ts_ms = try r.readIntLittle(u64);
        const side_tag = try r.readByte();
        item.failed_side = @enumFromInt(side_tag);
        const op_tag: u8 = try r.readByte();
        const err_tag: u8 = try r.readByte();
        item.err = @enumFromInt(err_tag);
        item.attempts = try r.readIntLittle(u32);
        const ns_len = try r.readIntLittle(u32);
        const ns = try allocator.alloc(u8, ns_len);
        try r.readNoEof(ns);
        const set_len = try r.readIntLittle(u32);
        const set = try allocator.alloc(u8, set_len);
        try r.readNoEof(set);
        const key_len = try r.readIntLittle(u32);
        const key = try allocator.alloc(u8, key_len);
        try r.readNoEof(key);
        item.ns = ns;
        item.set = set;
        item.key = key;
        switch (op_tag) {
            0 => { // put
                const bn_len = try r.readIntLittle(u32);
                const bn = try allocator.alloc(u8, bn_len);
                try r.readNoEof(bn);
                _ = try r.readByte(); // value tag (only int supported for now)
                const vint = try r.readIntLittle(i64);
                item.op = .{ .put = .{ .bin_name = bn, .value = .{ .int = vint } } };
            },
            1 => { // incr
                const bn_len = try r.readIntLittle(u32);
                const bn = try allocator.alloc(u8, bn_len);
                try r.readNoEof(bn);
                const d = try r.readIntLittle(i64);
                item.op = .{ .incr = .{ .bin_name = bn, .delta = d } };
            },
            else => return error.InvalidArgument,
        }
        return item;
    }
};

// Select implementation based on build flag. When Aerospike C client headers/libs
// are not available, provide a no-op stub implementation that compiles.
pub const Client = if (build_options.aerospike) RealClient else DummyClient;

// Dual-cluster support: independent client pools and per-cluster health tracking.
pub const HealthStatus = enum { healthy, degraded, down };

// Task17: public metrics snapshot for repair queue/reconciler
pub const RepairMetrics = struct {
    enqueued: u64,
    succeeded: u64,
    failed: u64,
    pending: usize,
};

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
    allocator: std.mem.Allocator,
    primary: Client,
    secondary: Client,
    primary_health: ClusterHealth = .{},
    secondary_health: ClusterHealth = .{},
    cfg: Config,

    // New: repair queue and mutex for thread-safe enqueuing/dequeuing
    repair_queue: std.ArrayList(RepairItem),
    mutex: std.Thread.Mutex = .{},

    // Task16: health controller state
    health_mutex: std.Thread.Mutex = .{},
    controller_thread: ?std.Thread = null,
    controller_stop: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    active_override: ?Side = null, // when set, force reads to this side until cleared
    last_failover_ms: u64 = 0,
    // Probe context (owned strings)
    probe_ns: ?[]u8 = null,
    probe_set: ?[]u8 = null,
    // Probe cadence tracking
    last_probe_primary_ms: u64 = 0,
    last_probe_secondary_ms: u64 = 0,

    // Task17: durable queue state and metrics
    repair_dir_fd: ?std.fs.Dir = null,
    repairs_enqueued: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    repairs_succeeded: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    repairs_failed: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    reconciler_thread: ?std.Thread = null,
    reconciler_stop: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    const MAX_REPAIR_QUEUE: usize = 4096;

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
            .repair_queue = std.ArrayList(RepairItem).init(allocator),
        };
        // Initial health marks as success at creation time
        const now = nowMs();
        dc.primary_health.recordSuccess(now);
        dc.secondary_health.recordSuccess(now);
        // Task17: init durable queue dir, load, and start reconciler
        try dc.initRepairDir();
        try dc.loadRepairsFromDisk();
        // caller can start reconciler explicitly via startReconciler()
        return dc;
    }

    pub fn close(self: *DualClient) void {
        // Stop controller and free probe strings
        self.stopHealthController();
        // Task17: stop reconciler and close repair dir
        self.stopReconciler();
        if (self.repair_dir_fd) |*dir| dir.close();
        self.repair_dir_fd = null;
        if (self.probe_ns) |ns| self.allocator.free(ns);
        self.probe_ns = null;
        if (self.probe_set) |st| self.allocator.free(st);
        self.probe_set = null;
        self.freeRepairQueue();
        self.repair_queue.deinit();
        self.primary.close();
        self.secondary.close();
    }

    // (removed duplicate enqueueRepair; see later definition)

    // Task17: durable queue helpers and reconciler
    fn initRepairDir(self: *DualClient) !void {
        var cwd = std.fs.cwd();
        cwd.makeDir(self.cfg.repair_dir) catch |e| switch (e) {
            error.PathAlreadyExists => {},
            else => return e,
        };
        self.repair_dir_fd = try cwd.openDir(self.cfg.repair_dir, .{ .iterate = true, .access_sub_paths = true });
    }

    fn persistRepair(self: *DualClient, item: *const RepairItem) !void {
        if (self.repair_dir_fd == null) return; // best-effort
        const dir = self.repair_dir_fd.?;
        var name_buf: [128]u8 = undefined;
        const ts = item.ts_ms;
        const rand = @as(u64, @intCast(std.time.microTimestamp() & 0xffff));
        const fname = try std.fmt.bufPrint(&name_buf, "{d}-{d}.rep", .{ ts, rand });
        var file = try dir.createFile(fname, .{ .read = true, .truncate = true });
        defer file.close();
        const blob = try item.serialize(self.allocator);
        defer self.allocator.free(blob);
        try file.writeAll(blob);
        self.repairs_enqueued.store(self.repairs_enqueued.load(.monotonic) + 1, .monotonic);
    }

    fn deletePersisted(self: *DualClient, fname: []const u8) void {
        if (self.repair_dir_fd) |*dir| {
            dir.deleteFile(fname) catch {};
        }
    }

    fn loadRepairsFromDisk(self: *DualClient) !void {
        if (self.repair_dir_fd == null) return;
        var it = self.repair_dir_fd.?.iterate();
        while (try it.next()) |ent| {
            if (ent.kind != .file) continue;
            if (!std.mem.endsWith(u8, ent.name, ".rep")) continue;
            const contents = try self.repair_dir_fd.?.readFileAlloc(self.allocator, ent.name, 1 << 20);
            defer self.allocator.free(contents);
            const item = RepairItem.deserialize(self.allocator, contents) catch |e| {
                _ = e; // skip unreadable item
                continue;
            };
            try self.repair_queue.append(item);
        }
        self.logBacklogIfHigh();
    }

    fn tryRepair(self: *DualClient, item: *RepairItem) Error!void {
        const target: *Client = switch (item.failed_side) {
            .primary => &self.primary,
            .secondary => &self.secondary,
        };
        switch (item.op) {
            .put => |p| try target.put(item.ns, item.set, item.key, p.bin_name, p.value),
            .incr => |i| try target.operateIncr(item.ns, item.set, item.key, i.bin_name, i.delta),
        }
    }

    fn reconcilerLoop(self: *DualClient) void {
        const base_backoff = self.cfg.backoff_initial_ms;
        const max_backoff = self.cfg.backoff_max_ms;
        var sleep_ms: u64 = base_backoff;
        while (!self.reconciler_stop.load(.monotonic)) {
            if (self.nextRepair()) |item| {
                var owned = item; // copy
                // ensure persisted exists prior to attempt
                self.persistRepair(&owned) catch {};
                const res = self.tryRepair(&owned);
                if (res) |err| {
                    _ = err;
                    owned.attempts += 1;
                    self.mutex.lock();
                    self.repair_queue.append(owned) catch {
                        owned.deinit(self.allocator);
                    };
                    self.mutex.unlock();
                    self.repairs_failed.store(self.repairs_failed.load(.monotonic) + 1, .monotonic);
                    sleep_ms = @min(max_backoff, sleep_ms * 2);
                } else {
                    self.repairs_succeeded.store(self.repairs_succeeded.load(.monotonic) + 1, .monotonic);
                    // delete one persisted with ts prefix
                    if (self.repair_dir_fd) |*dir| {
                        var it = dir.iterate();
                        var prefix_buf: [64]u8 = undefined;
                        const prefix = std.fmt.bufPrint(&prefix_buf, "{d}-", .{ owned.ts_ms }) catch "";
                        while (it.next() catch null) |ent| {
                            if (ent.kind != .file) continue;
                            if (std.mem.startsWith(u8, ent.name, prefix) and std.mem.endsWith(u8, ent.name, ".rep")) {
                                dir.deleteFile(ent.name) catch {};
                                break;
                            }
                        }
                    }
                    owned.deinit(self.allocator);
                    sleep_ms = base_backoff;
                }
            } else {
                // Idle
                std.time.sleep(@as(u64, @intCast(base_backoff)) * std.time.ns_per_ms);
                if (sleep_ms > base_backoff) sleep_ms = @max(base_backoff, sleep_ms / 2);
            }
        }
    }

    pub fn startReconciler(self: *DualClient) !void {
        if (self.reconciler_thread != null) return;
        self.reconciler_stop.store(false, .monotonic);
        self.reconciler_thread = try std.Thread.spawn(.{}, DualClient.reconcilerLoop, .{ self });
    }

    pub fn stopReconciler(self: *DualClient) void {
        if (self.reconciler_thread) |t| {
            self.reconciler_stop.store(true, .monotonic);
            t.join();
            self.reconciler_thread = null;
        }
    }

    fn logBacklogIfHigh(self: *DualClient) void {
        const n = self.pendingRepairs();
        if (n > (MAX_REPAIR_QUEUE / 2)) {
            std.log.warn("High repair backlog: {d}/{d}", .{ n, MAX_REPAIR_QUEUE });
        }
    }

    // Task17: expose metrics snapshot
    pub fn repairMetrics(self: *DualClient) RepairMetrics {
        return .{
            .enqueued = self.repairs_enqueued.load(.monotonic),
            .succeeded = self.repairs_succeeded.load(.monotonic),
            .failed = self.repairs_failed.load(.monotonic),
            .pending = self.pendingRepairs(),
        };
    }

    pub fn recordResult(self: *DualClient, side: Side, ok: bool) void {
        const now = nowMs();
        self.health_mutex.lock();
        defer self.health_mutex.unlock();
        switch (side) {
            .primary => if (ok) self.primary_health.recordSuccess(now) else self.primary_health.recordFailure(now),
            .secondary => if (ok) self.secondary_health.recordSuccess(now) else self.secondary_health.recordFailure(now),
        }
        // Apply configurable breaker thresholds
        if (!ok) {
            switch (side) {
                .primary => {
                    if (self.primary_health.consecutive_failures >= self.cfg.breaker_down_threshold) {
                        self.primary_health.status = .down;
                    } else if (self.primary_health.consecutive_failures > 0) {
                        self.primary_health.status = .degraded;
                    }
                },
                .secondary => {
                    if (self.secondary_health.consecutive_failures >= self.cfg.breaker_down_threshold) {
                        self.secondary_health.status = .down;
                    } else if (self.secondary_health.consecutive_failures > 0) {
                        self.secondary_health.status = .degraded;
                    }
                },
            }
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

    fn dup(self: *DualClient, s: []const u8) ![]u8 {
        const buf = try self.allocator.alloc(u8, s.len);
        std.mem.copy(u8, buf, s);
        return buf;
    }

    // Helper: determine if an error represents an idempotent retry outcome under current write policy
    fn isIdempotentRetry(self: *DualClient, err: Error) bool {
        const wp = self.cfg.policies.write;
        return switch (err) {
            // If caller used create_only and we observe RecordExists on retry, the prior write likely succeeded
            .RecordExists => wp.key_exists_action == .create_only,
            // If using generation GT semantics, a generation mismatch implies a newer write already applied
            .GenerationMismatch => wp.generation_policy == .gt,
            else => false,
        };
    }

    // Helper: whether an error merits read failover to the other side
    fn isFailoverEligibleError(err: Error) bool {
        return switch (err) {
            // NotFound is a legitimate outcome and should not trigger failover by default
            .NotFound => false,
            else => true,
        };
    }

    // Read with failover: prefer primary by default; on outage or eligible errors, fallback to secondary;
    pub fn get(self: *DualClient, ns: []const u8, set: []const u8, key: []const u8) Error!void {
        const now = nowMs();
        var pref = self.cfg.read_preference;
        // Task16: enforce active_override when present
        if (self.active_override) |ov| {
            switch (pref) {
                .prefer_primary, .prefer_secondary => {
                    pref = switch (ov) {
                        .primary => .primary_only,
                        .secondary => .secondary_only,
                    };
                },
                else => {},
            }
        }

        const tryOne = struct {
            fn run(dc: *DualClient, side: Side, ns_: []const u8, set_: []const u8, key_: []const u8) Error!void {
                const client = dc.clientPtr(side);
                client.get(ns_, set_, key_) catch |e| {
                    dc.recordResult(side, false);
                    return e;
                };
                dc.recordResult(side, true);
                return;
            }
        };

        // Decide routing based on preference and health/cooldown
        const primary_ok = self.primary_health.status == .healthy or (now - self.primary_health.last_error_ms >= self.cfg.failover_cooldown_ms);
        const secondary_ok = self.secondary_health.status == .healthy or (now - self.secondary_health.last_error_ms >= self.cfg.failover_cooldown_ms);

        switch (pref) {
            .primary_only => {
                return tryOne.run(self, .primary, ns, set, key);
            },
            .secondary_only => {
                return tryOne.run(self, .secondary, ns, set, key);
            },
            .prefer_primary => {
                // If primary considered OK, try it first; otherwise try secondary and probe primary only after cooldown
                if (primary_ok) {
                    const r1 = tryOne.run(self, .primary, ns, set, key);
                    _ = r1; // success returns
                    return;
                } else {
                    // Use secondary first
                    const r2 = tryOne.run(self, .secondary, ns, set, key) catch |e2| {
                        // Secondary failed. If cooldown has elapsed, attempt a single primary probe; otherwise return error.
                        if (now - self.primary_health.last_error_ms >= self.cfg.failover_cooldown_ms) {
                            return tryOne.run(self, .primary, ns, set, key) catch |e1| {
                                // Both failed: prefer returning secondary error if failover-eligible; otherwise primary's.
                                if (isFailoverEligibleError(e2)) return e2 else return e1;
                            };
                        }
                        return e2;
                    };
                    _ = r2;
                    return;
                }
            },
            .prefer_secondary => {
                if (secondary_ok) {
                    const r1s = tryOne.run(self, .secondary, ns, set, key);
                    _ = r1s;
                    return;
                } else {
                    const r2p = tryOne.run(self, .primary, ns, set, key) catch |e2p| {
                        if (now - self.secondary_health.last_error_ms >= self.cfg.failover_cooldown_ms) {
                            return tryOne.run(self, .secondary, ns, set, key) catch |e1s| {
                                if (isFailoverEligibleError(e2p)) return e2p else return e1s;
                            };
                        }
                        return e2p;
                    };
                    _ = r2p;
                    return;
                }
            },
        }
    }

    // New: synchronous dual-write using parallel sends with idempotency-aware handling.
    // Aligns with namespace last-update-time policy: we accept idempotent retry outcomes
    // and deterministically route true conflicts based on cfg.conflict_policy.
    pub fn putBoth(self: *DualClient, ns: []const u8, set: []const u8, key: []const u8, bin_name: []const u8, value: Value) Error!void {
        const ThreadResult = struct { ok: bool = false, err: ?Error = null };
        var r_p: ThreadResult = .{};
        var r_s: ThreadResult = .{};

        const workerPut = struct {
            fn run(client: *Client, ns_: []const u8, set_: []const u8, key_: []const u8, bin_: []const u8, val_: Value, out: *ThreadResult) void {
                out.* = .{};
                client.put(ns_, set_, key_, bin_, val_) catch |e| {
                    out.ok = false;
                    out.err = e;
                    return;
                };
                out.ok = true;
            }
        };

        var t1 = try std.Thread.spawn(.{}, workerPut.run, .{ &self.primary, ns, set, key, bin_name, value, &r_p });
        var t2 = try std.Thread.spawn(.{}, workerPut.run, .{ &self.secondary, ns, set, key, bin_name, value, &r_s });
        t1.join();
        t2.join();

        // Record health based on results
        self.recordResult(.primary, r_p.ok);
        self.recordResult(.secondary, r_s.ok);

        // Fast-path success
        if (r_p.ok and r_s.ok) return;

        // Idempotent retry cases: one or both sides indicate prior success under current write policy
        const p_idem = if (!r_p.ok and r_p.err) |e| self.isIdempotentRetry(e) else false;
        const s_idem = if (!r_s.ok and r_s.err) |e| self.isIdempotentRetry(e) else false;

        if ((r_p.ok and s_idem) or (r_s.ok and p_idem) or (p_idem and s_idem)) {
            // Treat as overall success: one side succeeded now and the other reflects prior success
            return;
        }

        // True conflict detection: generation EQ mismatch is considered a conflict that needs deterministic handling
        const wp = self.cfg.policies.write;
        const p_conflict = (!r_p.ok and r_p.err == Error.GenerationMismatch and wp.generation_policy == .eq);
        const s_conflict = (!r_s.ok and r_s.err == Error.GenerationMismatch and wp.generation_policy == .eq);
        if (p_conflict or s_conflict) {
            switch (self.cfg.conflict_policy) {
                .enqueue_repair => {
                    if (p_conflict) self.enqueueRepairPut(.primary, ns, set, key, bin_name, value, r_p.err orelse Error.OperationFailed);
                    if (s_conflict) self.enqueueRepairPut(.secondary, ns, set, key, bin_name, value, r_s.err orelse Error.OperationFailed);
                    return Error.OperationFailed;
                },
                .return_conflict => return Error.GenerationMismatch,
            }
        }

        // Fallback: partial failure => enqueue repair for the side that failed (non-idempotent errors)
        if (r_p.ok and !r_s.ok) {
            self.enqueueRepairPut(.secondary, ns, set, key, bin_name, value, r_s.err orelse Error.OperationFailed);
        } else if (!r_p.ok and r_s.ok) {
            self.enqueueRepairPut(.primary, ns, set, key, bin_name, value, r_p.err orelse Error.OperationFailed);
        }

        return Error.OperationFailed;
    }

    // New: synchronous dual-operate (increment) using parallel sends with idempotency/conflict handling.
    // Note: increments are not naturally idempotent; when using generation GT, a mismatch may indicate
    // the prior increment has already been applied. Under EQ, a mismatch is treated as a true conflict.
    pub fn operateIncrBoth(self: *DualClient, ns: []const u8, set: []const u8, key: []const u8, bin_name: []const u8, delta: i64) Error!void {
        const ThreadResult = struct { ok: bool = false, err: ?Error = null };
        var r_p: ThreadResult = .{};
        var r_s: ThreadResult = .{};

        const workerOp = struct {
            fn run(client: *Client, ns_: []const u8, set_: []const u8, key_: []const u8, bin_: []const u8, d: i64, out: *ThreadResult) void {
                out.* = .{};
                client.operateIncr(ns_, set_, key_, bin_, d) catch |e| {
                    out.ok = false;
                    out.err = e;
                    return;
                };
                out.ok = true;
            }
        };

        var t1 = try std.Thread.spawn(.{}, workerOp.run, .{ &self.primary, ns, set, key, bin_name, delta, &r_p });
        var t2 = try std.Thread.spawn(.{}, workerOp.run, .{ &self.secondary, ns, set, key, bin_name, delta, &r_s });
        t1.join();
        t2.join();

        self.recordResult(.primary, r_p.ok);
        self.recordResult(.secondary, r_s.ok);

        if (r_p.ok and r_s.ok) return;

        const wp2 = self.cfg.policies.write;
        const p_idem = (!r_p.ok and r_p.err == Error.GenerationMismatch and wp2.generation_policy == .gt);
        const s_idem = (!r_s.ok and r_s.err == Error.GenerationMismatch and wp2.generation_policy == .gt);
        if ((r_p.ok and s_idem) or (r_s.ok and p_idem) or (p_idem and s_idem)) {
            // Accept as idempotent retry under GT semantics
            return;
        }

        const p_conflict = (!r_p.ok and r_p.err == Error.GenerationMismatch and wp2.generation_policy == .eq);
        const s_conflict = (!r_s.ok and r_s.err == Error.GenerationMismatch and wp2.generation_policy == .eq);
        if (p_conflict or s_conflict) {
            switch (self.cfg.conflict_policy) {
                .enqueue_repair => {
                    if (p_conflict) self.enqueueRepairIncr(.primary, ns, set, key, bin_name, delta, r_p.err orelse Error.OperationFailed);
                    if (s_conflict) self.enqueueRepairIncr(.secondary, ns, set, key, bin_name, delta, r_s.err orelse Error.OperationFailed);
                    return Error.OperationFailed;
                },
                .return_conflict => return Error.GenerationMismatch,
            }
        }

        if (r_p.ok and !r_s.ok) {
            self.enqueueRepairIncr(.secondary, ns, set, key, bin_name, delta, r_s.err orelse Error.OperationFailed);
        } else if (!r_p.ok and r_s.ok) {
            self.enqueueRepairIncr(.primary, ns, set, key, bin_name, delta, r_p.err orelse Error.OperationFailed);
        }

        return Error.OperationFailed;
    }

    fn enqueueRepairPut(self: *DualClient, failed_side: Side, ns: []const u8, set: []const u8, key: []const u8, bin_name: []const u8, value: Value, err: Error) void {
        var item = RepairItem{
            .ts_ms = nowMs(),
            .failed_side = failed_side,
            .ns = self.dup(ns) catch return,
            .set = self.dup(set) catch return,
            .key = self.dup(key) catch return,
            .op = .{ .put = .{ .bin_name = self.dup(bin_name) catch return, .value = value } },
            .err = err,
        };
        self.enqueueRepair(item) catch {
            // On enqueue failure, free owned memory to avoid leak
            item.deinit(self.allocator);
        };
    }

    fn enqueueRepairIncr(self: *DualClient, failed_side: Side, ns: []const u8, set: []const u8, key: []const u8, bin_name: []const u8, delta: i64, err: Error) void {
        var item = RepairItem{
            .ts_ms = nowMs(),
            .failed_side = failed_side,
            .ns = self.dup(ns) catch return,
            .set = self.dup(set) catch return,
            .key = self.dup(key) catch return,
            .op = .{ .incr = .{ .bin_name = self.dup(bin_name) catch return, .delta = delta } },
            .err = err,
        };
        self.enqueueRepair(item) catch {
            item.deinit(self.allocator);
        };
    }

    fn enqueueRepair(self: *DualClient, item: RepairItem) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.repair_queue.items.len >= MAX_REPAIR_QUEUE) {
            // Drop oldest to make room
            var old = self.repair_queue.items[0];
            _ = self.repair_queue.orderedRemove(0);
            old.deinit(self.allocator);
        }
        try self.repair_queue.append(item);
        // best-effort persist and backlog alert
        const last = &self.repair_queue.items[self.repair_queue.items.len - 1];
        self.persistRepair(last) catch {};
        self.logBacklogIfHigh();
    }

    pub fn nextRepair(self: *DualClient) ?RepairItem {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.repair_queue.items.len == 0) return null;
        const item = self.repair_queue.items[0];
        _ = self.repair_queue.orderedRemove(0);
        return item;
    }

    pub fn pendingRepairs(self: *DualClient) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.repair_queue.items.len;
    }

    fn freeRepairQueue(self: *DualClient) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        var i: usize = 0;
        while (i < self.repair_queue.items.len) : (i += 1) {
            var it = &self.repair_queue.items[i];
            it.deinit(self.allocator);
        }
        self.repair_queue.clearRetainingCapacity();
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
    // New generation-aware API stubs for no-op client
    pub fn putWithGen(_: *DummyClient, _: []const u8, _: []const u8, _: []const u8, _: []const u8, _: Value, _: u32, _: GenerationPolicy) Error!void {
        return Error.AerospikeDisabled;
    }
    pub fn get(_: *DummyClient, _: []const u8, _: []const u8, _: []const u8) Error!void {
        return Error.AerospikeDisabled;
    }
    pub fn operateIncr(_: *DummyClient, _: []const u8, _: []const u8, _: []const u8, _: []const u8, _: i64) Error!void {
        return Error.AerospikeDisabled;
    }
    pub fn operateIncrWithGen(_: *DummyClient, _: []const u8, _: []const u8, _: []const u8, _: []const u8, _: i64, _: u32, _: GenerationPolicy) Error!void {
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

    // New: map key_exists_action to Aerospike C enum
    fn mapKeyExistsAction(kea: KeyExistsAction) c.as_policy_exists {
        return switch (kea) {
            .update => c.AS_POLICY_EXISTS_IGNORE,
            .replace => c.AS_POLICY_EXISTS_REPLACE,
            .create_only => c.AS_POLICY_EXISTS_CREATE_ONLY,
            .update_only => c.AS_POLICY_EXISTS_UPDATE_ONLY,
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
                // Support both potential field names from C headers: 'key_exists_action' and 'exists'
                if (@hasField(@TypeOf(wp.*), "key_exists_action")) @field(wp.*, "key_exists_action") = mapKeyExistsAction(cfg.policies.write.key_exists_action);
                if (@hasField(@TypeOf(wp.*), "exists")) @field(wp.*, "exists") = mapKeyExistsAction(cfg.policies.write.key_exists_action);
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
            // Map Aerospike status codes to generation-aware errors
            if (err.code == c.AEROSPIKE_ERR_RECORD_EXISTS) return Error.RecordExists;
            if (err.code == c.AEROSPIKE_ERR_RECORD_GENERATION) return Error.GenerationMismatch;
            return Error.OperationFailed;
        }
        _ = c.as_record_destroy(&rec);
    }

    // New: generation-aware put with expected_generation using per-operation write policy
    pub fn putWithGen(self: *RealClient, ns: []const u8, set: []const u8, key: []const u8, bin_name: []const u8, value: Value, expected_generation: u32, gen_policy: GenerationPolicy) Error!void {
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

        var wp: c.as_policy_write = undefined;
        _ = c.as_policy_write_init(&wp);
        // Set generation semantics
        wp.generation = expected_generation;
        wp.generation_policy = mapGenPolicy(gen_policy);

        if (c.aerospike_key_put(&self.as, &err, &wp, &akey, &rec) != c.AEROSPIKE_OK) {
            _ = c.as_record_destroy(&rec);
            if (err.code == c.AEROSPIKE_ERR_RECORD_EXISTS) return Error.RecordExists;
            if (err.code == c.AEROSPIKE_ERR_RECORD_GENERATION) return Error.GenerationMismatch;
            if (err.code == c.AEROSPIKE_ERR_RECORD_NOT_FOUND) return Error.NotFound;
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
            if (err.code == c.AEROSPIKE_ERR_RECORD_EXISTS) return Error.RecordExists; // unlikely for get, but included for completeness
            if (err.code == c.AEROSPIKE_ERR_RECORD_GENERATION) return Error.GenerationMismatch; // likewise
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
            if (err.code == c.AEROSPIKE_ERR_RECORD_NOT_FOUND) return Error.NotFound;
            if (err.code == c.AEROSPIKE_ERR_RECORD_EXISTS) return Error.RecordExists;
            if (err.code == c.AEROSPIKE_ERR_RECORD_GENERATION) return Error.GenerationMismatch;
            return Error.OperationFailed;
        }
        _ = c.as_operations_destroy(&ops);
        if (rec) |r| _ = c.as_record_destroy(r);
    }

    // New: generation-aware increment using per-operation operate policy
    pub fn operateIncrWithGen(self: *RealClient, ns: []const u8, set: []const u8, key: []const u8, bin_name: []const u8, delta: i64, expected_generation: u32, gen_policy: GenerationPolicy) Error!void {
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

        var op_pol: c.as_policy_operate = undefined;
        _ = c.as_policy_operate_init(&op_pol);
        op_pol.generation = expected_generation;
        op_pol.generation_policy = mapGenPolicy(gen_policy);

        var rec: ?*c.as_record = null;
        if (c.aerospike_key_operate(&self.as, &err, &op_pol, &akey, &ops, &rec) != c.AEROSPIKE_OK) {
            _ = c.as_operations_destroy(&ops);
            if (rec) |_| _ = c.as_record_destroy(rec.?);
            if (err.code == c.AEROSPIKE_ERR_RECORD_NOT_FOUND) return Error.NotFound;
            if (err.code == c.AEROSPIKE_ERR_RECORD_EXISTS) return Error.RecordExists;
            if (err.code == c.AEROSPIKE_ERR_RECORD_GENERATION) return Error.GenerationMismatch;
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
