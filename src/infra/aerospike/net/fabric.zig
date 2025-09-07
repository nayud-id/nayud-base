const std = @import("std");

pub const Errors = error{ InvalidPort, InvalidThreads };

/// Fabric (intra-cluster) network configuration
pub const FabricConfig = struct {
    port: u16 = 3001,
    threads: u16 = 4, // worker threads; tune by CPU

    pub fn validate(self: FabricConfig) Errors!void {
        if (self.port == 0) return Errors.InvalidPort;
        if (self.threads == 0) return Errors.InvalidThreads;
    }

    pub fn renderInto(self: FabricConfig, w: anytype, indent: []const u8) !void {
        try self.validate();
        try w.print("{s}fabric {\n", .{indent});
        try w.print("{s}    port {}\n", .{ indent, self.port });
        try w.print("{s}    threads {}\n", .{ indent, self.threads });
        try w.print("{s}}\n", .{indent});
    }
};