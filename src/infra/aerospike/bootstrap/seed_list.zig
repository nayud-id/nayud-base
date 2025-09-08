const std = @import("std");
const topo = @import("../topology.zig");
const heartbeat = @import("../net/heartbeat.zig");

/// Errors for client seed list modeling and helpers.
pub const Errors = error{ MissingSeeds, InvalidPort, DuplicateSeed, BufferTooSmall };

/// Reuse HostPort shape from heartbeat to avoid duplication (DRY).
pub const HostPort = heartbeat.HostPort;

/// Client bootstrap seed list. Zero-alloc validation and rendering helpers.
pub const SeedList = struct {
    /// Caller-owned host:port slice. Provide at least two entries for resiliency.
    seeds: []const HostPort = &.{},

    /// Basic validity checks: >= 2 seeds, non-zero ports, no duplicate host:port.
    pub fn validate(self: SeedList) Errors!void {
        if (self.seeds.len < 2) return Errors.MissingSeeds;
        var i: usize = 0;
        while (i < self.seeds.len) : (i += 1) {
            const a = self.seeds[i];
            if (a.port == 0) return Errors.InvalidPort;
            var j: usize = i + 1;
            while (j < self.seeds.len) : (j += 1) {
                const b = self.seeds[j];
                if (a.port == b.port and std.mem.eql(u8, a.host, b.host)) {
                    return Errors.DuplicateSeed;
                }
            }
        }
    }

    /// Render a concise, zero-alloc pseudo-conf line for client seeds.
    pub fn renderInto(self: SeedList, w: anytype, indent: []const u8) !void {
        try self.validate();
        try w.print("{s}# Client bootstrap seeds (host:port)\n", .{indent});
        try w.print("{s}# Provide at least two nodes for resiliency\n", .{indent});
        try w.print("{s}seeds ", .{indent});
        var first = true;
        for (self.seeds) |hp| {
            if (!first) try w.writeAll(", ");
            first = false;
            // HostPort.format prints host:port
            try w.print("{any}", .{hp});
        }
        try w.writeByte('\n');
    }

    /// Zero-alloc rendering of seeds derived from Topology (for ops visibility).
    pub fn writeFromTopology(w: anytype, indent: []const u8, top: topo.Topology) !void {
        try w.print("{s}# Client bootstrap seeds derived from topology\n", .{indent});
        try w.print("{s}seeds ", .{indent});
        var first = true;
        for (top.nodes) |n| {
            if (!first) try w.writeAll(", ");
            first = false;
            try w.print("{s}:{}", .{ n.host, n.port });
        }
        try w.writeByte('\n');
    }

    /// Copy topology nodes into a caller-provided HostPort buffer.
    /// Returns the used slice; no allocations performed.
    pub fn fillFromTopology(buf: []HostPort, top: topo.Topology) Errors![]HostPort {
        if (buf.len < top.nodes.len) return Errors.BufferTooSmall;
        var i: usize = 0;
        while (i < top.nodes.len) : (i += 1) {
            buf[i] = .{ .host = top.nodes[i].host, .port = top.nodes[i].port };
        }
        return buf[0..top.nodes.len];
    }
};