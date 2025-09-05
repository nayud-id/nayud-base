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

// Select implementation based on build flag. When Aerospike C client headers/libs
// are not available, provide a no-op stub implementation that compiles.
pub const Client = if (build_options.aerospike) RealClient else DummyClient;

const DummyClient = struct {
    pub fn connect(_: std.mem.Allocator, _: []const u8, _: u16) Error!DummyClient {
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

const RealClient = struct {
    const c = @cImport({
        @cInclude("aerospike/aerospike.h");
        @cInclude("aerospike/as_config.h");
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

    pub fn connect(allocator: std.mem.Allocator, host: []const u8, port: u16) Error!RealClient {
        var client: RealClient = .{};

        var cfg: c.as_config = undefined;
        _ = c.as_config_init(&cfg);

        const host_z = try toCStrZ(allocator, host);
        defer allocator.free(host_z);
        _ = c.as_config_add_host(&cfg, host_z, port);

        _ = c.aerospike_init(&client.as, &cfg);

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
};