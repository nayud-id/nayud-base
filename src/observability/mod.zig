const std = @import("std");

// Observability scaffold: logging/metrics placeholders.
// Intentionally no-op to avoid accidental logging of secrets.

pub fn logInfo(_: []const u8) void {}
pub fn logError(_: []const u8) void {}