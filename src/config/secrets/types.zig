const std = @import("std");

/// Canonical secrets type for the application.
/// Keep fields minimal and avoid logging anywhere.
pub const Secrets = struct {
    // Aerospike client authentication
    aerospike_user: []const u8,
    aerospike_password: []const u8,

    // Optional TLS material (file paths)
    tls_ca_file: []const u8 = "",
    tls_cert_file: []const u8 = "",
    tls_key_file: []const u8 = "",

    // Optional: app namespace / cluster identifiers
    namespace: []const u8 = "",
    cluster_name: []const u8 = "",

    /// Redacted formatting helper. Never expose raw values.
    pub fn toStringRedacted(_: Secrets) []const u8 {
        return "Secrets(user=***, password=***, tls=***)";
    }

    /// Compile-time guard: disallow formatting/printing of Secrets via std.fmt/std.debug.
    /// If someone attempts to `print("{any}", .{secrets})`, this triggers a compile error
    /// instructing to use redacted helpers instead.
    pub fn format(_: Secrets, comptime _: []const u8, _: std.fmt.FormatOptions, _: anytype) !void {
        @compileError("Printing Secrets is forbidden. Use Secrets.toStringRedacted() or security.redaction utilities.");
    }
};