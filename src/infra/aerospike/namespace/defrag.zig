const std = @import("std");

pub const Errors = error{ InvalidDefragSleep, InvalidDefragThreshold };

/// Defragmentation tuning for persistent storage engine.
pub const DefragConfig = struct {
    /// Sleep in milliseconds between defrag batches (0..1000 reasonable)
    sleep_ms: u16 = 10,
    /// Threshold percent to trigger defrag (1..99)
    threshold_pct: u8 = 50,

    pub fn validate(self: DefragConfig) Errors!void {
        if (self.sleep_ms > 10_000) return Errors.InvalidDefragSleep; // cap 10s
        if (self.threshold_pct == 0 or self.threshold_pct >= 100) return Errors.InvalidDefragThreshold;
    }

    pub fn renderInto(self: DefragConfig, w: anytype, indent: []const u8) !void {
        try self.validate();
        try w.print("{s}# Defrag policy\n", .{indent});
        try w.print("{s}defrag-sleep {}\n", .{ indent, self.sleep_ms });
        try w.print("{s}defrag-threshold {}\n", .{ indent, self.threshold_pct });
    }
};