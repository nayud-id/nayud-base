const std = @import("std");

/// A constant mask used to represent redacted values in any diagnostics.
pub const MASK: []const u8 = "***";

/// Redact any sensitive input for logs. Always returns a constant mask.
/// This function does not print or allocate.
pub fn redact(_: []const u8) []const u8 {
    return MASK;
}

/// Simple key/value pair type for redaction adapters.
pub const Pair = struct {
    key: []const u8,
    value: []const u8,
};

/// Write a redacted representation of key/value pairs to the provided writer.
/// Only keys are rendered; all values are masked with MASK.
/// Example output: {user=***, password=***}
pub fn writePairsRedacted(writer: anytype, pairs: []const Pair) !void {
    var first = true;
    try writer.writeAll("{");
    for (pairs) |p| {
        if (!first) try writer.writeAll(", ");
        first = false;
        // Only print the key; value is always masked.
        try writer.print("{s}={s}", .{ p.key, MASK });
    }
    try writer.writeAll("}");
}

/// Write a redacted representation of a StringHashMap([]const u8) to the writer.
/// No allocations are performed; this is a zero-alloc formatter.
/// Example output: {AEROSPIKE_USER=***, TLS_KEY_FILE=***}
pub fn redactAll(writer: anytype, map: *const std.StringHashMap([]const u8)) !void {
    var it = map.iterator();
    var first = true;
    try writer.writeAll("{");
    while (it.next()) |entry| {
        if (!first) try writer.writeAll(", ");
        first = false;
        const key_slice: []const u8 = entry.key_ptr.*;
        try writer.print("{s}={s}", .{ key_slice, MASK });
    }
    try writer.writeAll("}");
}