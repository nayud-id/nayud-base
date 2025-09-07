const std = @import("std");

pub const Errors = error{ InvalidThreads, InvalidSleepUs };

/// Migrate (partition rebalancing) threads configuration
pub const MigrateConfig = struct {
    threads: u16 = 4,
    sleep_us: u32 = 0, // optional backoff per batch

    pub fn validate(self: MigrateConfig) Errors!void {
        if (self.threads == 0) return Errors.InvalidThreads;
        // sleep_us can be zero; if set, sanity cap at 10s
        if (self.sleep_us > 10_000_000) return Errors.InvalidSleepUs;
    }

    pub fn renderInto(self: MigrateConfig, w: anytype, indent: []const u8) !void {
        try self.validate();
        try w.print("{s}migrate {\n", .{indent});
        try w.print("{s}    threads {}\n", .{ indent, self.threads });
        if (self.sleep_us > 0) try w.print("{s}    sleep-us {}\n", .{ indent, self.sleep_us });
        try w.print("{s}}\n", .{indent});
    }
};