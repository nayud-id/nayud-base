const std = @import("std");
const infra = @import("../../infra/aerospike/mod.zig");

// Aerospike client scaffold. Real FFI/client plumbing will be added in later tasks.

pub const Client = struct {
    // Placeholder for connection pools, policies, etc.
};

pub const Bootstrap = struct {
    seeds: infra.bootstrap.seed_list.SeedList = .{},

    /// Render a pseudo-client conf snippet showing seed nodes for bootstrap.
    pub fn renderInto(self: Bootstrap, w: anytype, indent: []const u8) !void {
        try w.print("{s}# Aerospike client bootstrap\n", .{indent});
        try self.seeds.renderInto(w, indent);
    }
};

pub fn connect() void {
    // Placeholder connect routine
}