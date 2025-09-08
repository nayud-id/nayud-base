const std = @import("std");

pub const Errors = error{ InvalidTtlRange };

/// Namespace TTL configuration (default-ttl)
/// 0 means "never expire". Validation keeps values within sane bounds.
pub const TTLConfig = struct {
    /// Default TTL in seconds; 0 = never expire
    default_ttl_sec: u32 = 0,

    pub fn validate(self: TTLConfig) Errors!void {
        // Allow 0 (never). Otherwise, cap to 10 years for sanity.
        if (self.default_ttl_sec > 315_360_000) { // ~10 years
            return Errors.InvalidTtlRange;
        }
    }

    /// Render pseudo-config line under a namespace block.
    pub fn renderInto(self: TTLConfig, w: anytype, indent: []const u8) !void {
        try self.validate();
        try w.print("{s}# TTL policy\n", .{indent});
        if (self.default_ttl_sec == 0) {
            try w.print("{s}default-ttl 0  # never expire\n", .{ indent });
        } else {
            try w.print("{s}default-ttl {}\n", .{ indent, self.default_ttl_sec });
        }
    }
};