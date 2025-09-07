const std = @import("std");
const paths = @import("../paths.zig");
const Types = @import("types.zig");
const env_loader = @import("env.zig");

pub const LoadError = error{
    NotFound,
    InvalidFormat,
    Io,
};

fn trim(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t\r\n");
}

fn parse_kv_line(line: []const u8, key_out: *[]const u8, val_out: *[]const u8) bool {
    const idx = std.mem.indexOfScalar(u8, line, '=') orelse return false;
    const key = trim(line[0..idx]);
    const val = trim(line[idx + 1 ..]);
    if (key.len == 0) return false;
    key_out.* = key;
    val_out.* = val;
    return true;
}

/// Load from an env-style file at paths.secrets_env_path.
/// Accepted keys:
/// - AEROSPIKE_USER (required)
/// - AEROSPIKE_PASSWORD (required)
/// - TLS_CA_FILE, TLS_CERT_FILE, TLS_KEY_FILE, NAMESPACE, CLUSTER_NAME (optional)
fn fromEnvFile(allocator: std.mem.Allocator) LoadError!Types.Secrets {
    var file = std.fs.cwd().openFile(paths.secrets_env_path, .{ .mode = .read_only }) catch |e| switch (e) {
        error.FileNotFound => return LoadError.NotFound,
        else => return LoadError.Io,
    };
    defer file.close();

    const stat = file.stat() catch return LoadError.Io;
    if (stat.size == 0) return LoadError.InvalidFormat;

    var buf = allocator.alloc(u8, @intCast(stat.size)) catch return LoadError.Io;
    errdefer allocator.free(buf);

    const n = file.readAll(buf) catch return LoadError.Io;
    const content = buf[0..n];

    var user_opt: ?[]u8 = null;
    var pass_opt: ?[]u8 = null;
    var tls_ca_opt: ?[]u8 = null;
    var tls_cert_opt: ?[]u8 = null;
    var tls_key_opt: ?[]u8 = null;
    var ns_opt: ?[]u8 = null;
    var cluster_opt: ?[]u8 = null;

    errdefer {
        if (user_opt) |v| allocator.free(v);
        if (pass_opt) |v| allocator.free(v);
        if (tls_ca_opt) |v| allocator.free(v);
        if (tls_cert_opt) |v| allocator.free(v);
        if (tls_key_opt) |v| allocator.free(v);
        if (ns_opt) |v| allocator.free(v);
        if (cluster_opt) |v| allocator.free(v);
    }

    var it = std.mem.splitScalar(u8, content, '\n');
    while (it.next()) |raw_line| {
        const line = trim(raw_line);
        if (line.len == 0) continue;
        if (line[0] == '#') continue;

        var key: []const u8 = undefined;
        var val: []const u8 = undefined;
        if (!parse_kv_line(line, &key, &val)) return LoadError.InvalidFormat;

        // Normalize key to upper-case match (keys are expected upper already).
        if (std.mem.eql(u8, key, "AEROSPIKE_USER")) {
            user_opt = std.mem.dupe(allocator, u8, val) catch return LoadError.Io;
        } else if (std.mem.eql(u8, key, "AEROSPIKE_PASSWORD")) {
            pass_opt = std.mem.dupe(allocator, u8, val) catch return LoadError.Io;
        } else if (std.mem.eql(u8, key, "TLS_CA_FILE")) {
            tls_ca_opt = std.mem.dupe(allocator, u8, val) catch return LoadError.Io;
        } else if (std.mem.eql(u8, key, "TLS_CERT_FILE")) {
            tls_cert_opt = std.mem.dupe(allocator, u8, val) catch return LoadError.Io;
        } else if (std.mem.eql(u8, key, "TLS_KEY_FILE")) {
            tls_key_opt = std.mem.dupe(allocator, u8, val) catch return LoadError.Io;
        } else if (std.mem.eql(u8, key, "NAMESPACE")) {
            ns_opt = std.mem.dupe(allocator, u8, val) catch return LoadError.Io;
        } else if (std.mem.eql(u8, key, "CLUSTER_NAME")) {
            cluster_opt = std.mem.dupe(allocator, u8, val) catch return LoadError.Io;
        } else {
            // Unknown key: ignore silently to avoid leaking info.
            continue;
        }
    }

    if (user_opt == null or pass_opt == null) return LoadError.InvalidFormat;

    // At this point, we can free the read buffer safely; values are duped.
    allocator.free(buf);

    return .{
        .aerospike_user = user_opt.?,
        .aerospike_password = pass_opt.?,
        .tls_ca_file = if (tls_ca_opt) |v| v else allocator.alloc(u8, 0) catch return LoadError.Io,
        .tls_cert_file = if (tls_cert_opt) |v| v else allocator.alloc(u8, 0) catch return LoadError.Io,
        .tls_key_file = if (tls_key_opt) |v| v else allocator.alloc(u8, 0) catch return LoadError.Io,
        .namespace = if (ns_opt) |v| v else allocator.alloc(u8, 0) catch return LoadError.Io,
        .cluster_name = if (cluster_opt) |v| v else allocator.alloc(u8, 0) catch return LoadError.Io,
    };
}

/// Load secrets with a safe strategy and sanitized errors.
/// Strategy order:
/// 1) Env-style file: paths.secrets_env_path (if present)
/// 2) Environment variables (AEROSPIKE_USER/PASSWORD, optional TLS/namespace/cluster)
///
/// We purposefully avoid compile-time `@import` of config/secure/secrets.zig here to
/// keep builds working in clean repos. The authoritative path is defined in
/// paths.secrets_path for local-only Zig module usage, which can be wired via
/// a build option in a later task if desired.
pub fn load(allocator: std.mem.Allocator) LoadError!Types.Secrets {
    // 1) Try env-style file
    const file_result = fromEnvFile(allocator);
    switch (file_result) {
        LoadError.NotFound => {}, // fall through to env loader
        LoadError.InvalidFormat => return LoadError.InvalidFormat,
        LoadError.Io => return LoadError.Io,
        else => return file_result,
    }

    // 2) Try process environment
    return env_loader.fromEnv(allocator) catch |e| switch (e) {
        env_loader.LoadError.NotFound => LoadError.NotFound,
        env_loader.LoadError.Io => LoadError.Io,
        else => LoadError.InvalidFormat,
    };
}