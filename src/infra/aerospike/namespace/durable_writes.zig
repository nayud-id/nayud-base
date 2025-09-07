const std = @import("std");

/// Errors for durable writes configuration validation.
pub const Errors = error{ InvalidStopWritesPct };

/// Commit level policy for writes.
pub const CommitLevel = enum { master, all };

/// Namespace durable writes configuration.
/// Models key durability knobs with safe defaults and zero-alloc helpers.
pub const DurableWritesConfig = struct {
    /// When true, server commits to device (fsync) before acknowledging.
    commit_to_device: bool = true,
    /// Write commit level: master (single replica ack) or all (all replicas ack).
    write_commit_level: CommitLevel = .all,
    /// Stop writes threshold as a percentage (1..99).
    stop_writes_pct: u8 = 95,

    /// Basic validation for internal constraints.
    /// Cross-field/cluster-wide validations can be added by callers if needed.
    pub fn validate(self: DurableWritesConfig) Errors!void {
        // Require 1..99 to ensure headroom and avoid degenerate settings.
        if (self.stop_writes_pct == 0 or self.stop_writes_pct >= 100) {
            return Errors.InvalidStopWritesPct;
        }
    }

    /// Render pseudo-config lines for aerospike.conf under a namespace block.
    /// The caller controls the surrounding namespace braces and indentation.
    pub fn renderInto(self: DurableWritesConfig, w: anytype, indent: []const u8) !void {
        try self.validate();
        try w.print("{s}# Durable writes\n", .{indent});
        try w.print("{s}stop-writes-pct {}\n", .{ indent, self.stop_writes_pct });
        // Aerospike uses true/false literals.
        try w.print("{s}commit-to-device {s}\n", .{ indent, if (self.commit_to_device) "true" else "false" });
        try w.print("{s}write-commit-level {s}\n", .{ indent, @tagName(self.write_commit_level) });
    }
};