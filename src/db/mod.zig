// DB module scaffold. Central place to expose specific database clients.

pub const aerospike = @import("aerospike/client.zig");

pub fn noop() void {}