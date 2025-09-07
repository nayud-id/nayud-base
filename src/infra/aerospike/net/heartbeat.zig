const std = @import("std");

/// Errors specific to heartbeat configuration.
pub const Errors = error{
    InvalidPort,
    InvalidTiming,
    MissingSeeds,
    DuplicateSeed,
    MissingMulticastGroup,
};

pub const Mode = enum { mesh, multicast };

/// Host:Port descriptor for mesh heartbeat seeds.
pub const HostPort = struct {
    host: []const u8,
    port: u16,

    pub fn format(self: HostPort, comptime _: []const u8, _: std.fmt.FormatOptions, w: anytype) !void {
        try w.print("{s}:{}", .{ self.host, self.port });
    }
};

/// Heartbeat configuration (mesh or multicast).
pub const HeartbeatConfig = struct {
    mode: Mode = .mesh,
    port: u16 = 3002,
    interval_ms: u32 = 150,
    timeout_ms: u32 = 10_000,

    // Mesh mode
    mesh_seeds: []const HostPort = &.{},

    // Multicast mode
    mcast_group: []const u8 = "", // e.g. "239.1.99.22"
    mcast_port: u16 = 9918,

    pub fn validate(self: HeartbeatConfig) Errors!void {
        if (self.port == 0) return Errors.InvalidPort;
        if (self.interval_ms == 0 or self.timeout_ms <= self.interval_ms)
            return Errors.InvalidTiming;

        switch (self.mode) {
            .mesh => {
                if (self.mesh_seeds.len < 2) return Errors.MissingSeeds;
                // ensure no duplicate host:port (tiny lists) without allocations
                var i: usize = 0;
                while (i < self.mesh_seeds.len) : (i += 1) {
                    var j: usize = i + 1;
                    while (j < self.mesh_seeds.len) : (j += 1) {
                        if (std.mem.eql(u8, self.mesh_seeds[i].host, self.mesh_seeds[j].host) and self.mesh_seeds[i].port == self.mesh_seeds[j].port) {
                            return Errors.DuplicateSeed;
                        }
                    }
                }
            },
            .multicast => {
                if (self.mcast_group.len == 0 or self.mcast_port == 0) return Errors.MissingMulticastGroup;
            },
        }
    }

    /// Render only the heartbeat subsection; caller prints surrounding blocks.
    pub fn renderInto(self: HeartbeatConfig, w: anytype, indent: []const u8) !void {
        try self.validate();
        try w.print("{s}heartbeat {\n", .{indent});
        try w.print("{s}    mode {s}\n", .{ indent, @tagName(self.mode) });
        try w.print("{s}    port {}\n", .{ indent, self.port });
        try w.print("{s}    interval {} ms\n", .{ indent, self.interval_ms });
        try w.print("{s}    timeout {} ms\n", .{ indent, self.timeout_ms });
        switch (self.mode) {
            .mesh => {
                if (self.mesh_seeds.len > 0) {
                    try w.print("{s}    # mesh seed hosts\n", .{indent});
                    for (self.mesh_seeds) |hp| {
                        try w.print("{s}    mesh-seed {s}:{}\n", .{ indent, hp.host, hp.port });
                    }
                }
            },
            .multicast => {
                try w.print("{s}    multicast-group {s}:{}\n", .{ indent, self.mcast_group, self.mcast_port });
            },
        }
        try w.print("{s}}\n", .{indent});
    }
};