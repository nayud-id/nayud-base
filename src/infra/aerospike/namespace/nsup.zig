const std = @import("std");

pub const Errors = error{ InvalidNsupPeriod };

/// Namespace supervisor (nsup) tuning.
pub const NsupConfig = struct {
    /// Period in seconds for nsup to sweep and maintain objects (1..3600 typical)
    period_sec: u32 = 120,

    pub fn validate(self: NsupConfig) Errors!void {
        if (self.period_sec == 0 or self.period_sec > 86_400) return Errors.InvalidNsupPeriod; // cap 1 day
    }

    pub fn renderInto(self: NsupConfig, w: anytype, indent: []const u8) !void {
        try self.validate();
        try w.print("{s}# Namespace supervisor\n", .{indent});
        try w.print("{s}nsup-period {}\n", .{ indent, self.period_sec });
    }
};