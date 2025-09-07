const std = @import("std");
const Types = @import("types.zig");

pub const LoadError = error{ NotFound, Io };

fn getOwned(allocator: std.mem.Allocator, name: []const u8) LoadError!?[]u8 {
    return std.process.getEnvVarOwned(allocator, name) catch |e| switch (e) {
        error.EnvironmentVariableNotFound => null,
        else => LoadError.Io,
    };
}

fn getOwnedRequired(allocator: std.mem.Allocator, name: []const u8) LoadError![]u8 {
    if (try getOwned(allocator, name)) |val| return val;
    return LoadError.NotFound;
}

/// Load secrets from environment variables. No logging; caller must free returned slices.
/// Required: AEROSPIKE_USER, AEROSPIKE_PASSWORD
/// Optional: TLS_CA_FILE, TLS_CERT_FILE, TLS_KEY_FILE, NAMESPACE, CLUSTER_NAME
pub fn fromEnv(allocator: std.mem.Allocator) LoadError!Types.Secrets {
    const user = try getOwnedRequired(allocator, "AEROSPIKE_USER");
    const pass = try getOwnedRequired(allocator, "AEROSPIKE_PASSWORD");

    const tls_ca = (try getOwned(allocator, "TLS_CA_FILE")) orelse try allocator.alloc(u8, 0);
    const tls_cert = (try getOwned(allocator, "TLS_CERT_FILE")) orelse try allocator.alloc(u8, 0);
    const tls_key = (try getOwned(allocator, "TLS_KEY_FILE")) orelse try allocator.alloc(u8, 0);

    const ns = (try getOwned(allocator, "NAMESPACE")) orelse try allocator.alloc(u8, 0);
    const cluster = (try getOwned(allocator, "CLUSTER_NAME")) orelse try allocator.alloc(u8, 0);

    return .{
        .aerospike_user = user,
        .aerospike_password = pass,
        .tls_ca_file = tls_ca,
        .tls_cert_file = tls_cert,
        .tls_key_file = tls_key,
        .namespace = ns,
        .cluster_name = cluster,
    };
}