//! Centralized config paths. Single source of truth for filesystem locations.
//! Keep constants minimal and DRY; do not duplicate these values elsewhere.

pub const secure_dir: []const u8 = "config/secure";

/// The single authoritative path for the REAL secrets file.
/// - This path is intentionally excluded from VCS via config/secure/.gitignore
/// - Never commit a file at this path; use config/secure/secrets.zig.example as template
/// - Loaders will reference this constant (implemented in a later task)
pub const secrets_path: []const u8 = "config/secure/secrets.zig";

/// The tracked template file developers should copy locally to secrets_path.
pub const secrets_template_path: []const u8 = "config/secure/secrets.zig.example";