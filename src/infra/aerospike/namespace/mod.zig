// Namespace-scoped submodules for Aerospike infra.

pub const durable_writes = @import("durable_writes.zig");
pub const ttl = @import("ttl.zig");
pub const eviction = @import("eviction.zig");
pub const defrag = @import("defrag.zig");
pub const nsup = @import("nsup.zig");