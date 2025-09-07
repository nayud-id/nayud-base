const std = @import("std");

// Config module scaffold. Keep minimal and DRY.
// Responsibility: configuration types and future loaders (CLI > env > file > defaults).

pub const paths = @import("paths.zig");
pub const secrets = @import("secrets/mod.zig");

pub const Source = enum { cli, env, file, defaults };

pub const AppConfig = struct {
    // Placeholder for future fields (ports, endpoints, Aerospike client options, etc.)
};

pub fn init() void {
    // No-op initializer placeholder.
}