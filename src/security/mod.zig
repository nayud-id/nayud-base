const std = @import("std");

// Security module scaffold. No secret material here; only safe utilities.

/// Redact any sensitive input for logs. Always returns a constant mask.
pub fn redact(_: []const u8) []const u8 {
    return "***";
}

pub const Guards = struct {
    // Compile-time guards can be added here later (e.g., disallow secret prints).
};