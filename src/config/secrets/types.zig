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
};