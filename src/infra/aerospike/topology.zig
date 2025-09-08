const std = @import("std");

/// Physical placement options for a node. Use to avoid single point of failure.
pub const Placement = enum { az, rack, host };

/// Basic node descriptor for Aerospike CE cluster design.
pub const Node = struct {
    id: u8,
    host: []const u8,
    port: u16 = 3000,
    placement: Placement,

    pub fn format(self: Node, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("Node(id={}, host={s}:{}, placement={s})", .{ self.id, self.host, self.port, @tagName(self.placement) });
    }
};

/// Error set for topology validation and constructors.
pub const Errors = error{ InvalidNodeCount, DuplicateHost, LowPlacementDiversity, InvalidInput };

/// Cluster topology for 3–5 nodes. Use separate placements where possible.
pub const Topology = struct {
    nodes: []const Node,

    /// Seed list for client bootstrap (simply reuse node descriptors).
    pub fn seeds(self: Topology) []const Node {
        return self.nodes;
    }

    /// Validate recommended constraints for CE cluster design.
    /// - Node count between 3 and 5
    /// - Unique hosts
    /// - Prefer placement diversity (>= 2 distinct types)
    pub fn validate(self: Topology) Errors!void {
        if (self.nodes.len < 3 or self.nodes.len > 5) return Errors.InvalidNodeCount;

        // Unique hosts without allocations (n <= 5, so O(n^2) is fine)
        var i: usize = 0;
        while (i < self.nodes.len) : (i += 1) {
            var j: usize = i + 1;
            while (j < self.nodes.len) : (j += 1) {
                if (std.mem.eql(u8, self.nodes[i].host, self.nodes[j].host)) {
                    return Errors.DuplicateHost;
                }
            }
        }

        // Placement diversity: ensure at least two distinct placements
        var has_az = false;
        var has_rack = false;
        var has_host = false;
        for (self.nodes) |n| switch (n.placement) {
            .az => has_az = true,
            .rack => has_rack = true,
            .host => has_host = true,
        };
        const distinct: u3 = @intFromBool(has_az) + @intFromBool(has_rack) + @intFromBool(has_host);
        if (distinct < 2) return Errors.LowPlacementDiversity;
    }
};

/// Utility constructors for common topologies: 3, 4, 5 nodes.
pub fn threeNode(allocator: std.mem.Allocator, a: []const u8, b: []const u8, c: []const u8) Errors!Topology {
    const nodes = try allocator.alloc(Node, 3);
    nodes[0] = .{ .id = 1, .host = a, .placement = .az };
    nodes[1] = .{ .id = 2, .host = b, .placement = .rack };
    nodes[2] = .{ .id = 3, .host = c, .placement = .host };
    return .{ .nodes = nodes };
}

pub fn fourNode(allocator: std.mem.Allocator, hosts: []const []const u8) Errors!Topology {
    if (hosts.len != 4) return Errors.InvalidInput;
    const nodes = try allocator.alloc(Node, 4);
    const placements = [_]Placement{ .az, .rack, .host, .az };
    for (hosts, 0..) |h, i| nodes[i] = .{ .id = @intCast(i + 1), .host = h, .placement = placements[i] };
    return .{ .nodes = nodes };
}

pub fn fiveNode(allocator: std.mem.Allocator, hosts: []const []const u8) Errors!Topology {
    if (hosts.len != 5) return Errors.InvalidInput;
    const nodes = try allocator.alloc(Node, 5);
    const placements = [_]Placement{ .az, .rack, .host, .az, .rack };
    for (hosts, 0..) |h, i| nodes[i] = .{ .id = @intCast(i + 1), .host = h, .placement = placements[i] };
    return .{ .nodes = nodes };
}

const service = @import("service/mod.zig");

pub fn annotateWithRacks(writer: anytype, cfg: service.rack.RackConfig, top: Topology) !void {
    // Zero-alloc walkthrough: list nodes with optional rack-id when enabled
    try writer.writeAll("# Topology with rack annotations\n");
    for (top.nodes) |n| {
        try writer.print("- {any}", .{n});
        if (cfg.enabled) {
            if (cfg.rackIdFor(n.host)) |rid| {
                try writer.print(" (rack={})", .{rid});
            }
        }
        try writer.writeByte('\n');
    }
}

/// Render client seeds line from topology for convenience.
pub fn writeClientSeeds(writer: anytype, indent: []const u8, top: Topology) !void {
    try writer.print("{s}# Client bootstrap seeds derived from topology\n", .{indent});
    try writer.print("{s}seeds ", .{indent});
    var first = true;
    for (top.nodes) |n| {
        if (!first) try writer.writeAll(", ");
        first = false;
        try writer.print("{s}:{}", .{ n.host, n.port });
    }
    try writer.writeByte('\n');
}