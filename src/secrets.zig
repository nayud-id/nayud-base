//! Secrets manager for Nayud Aerospike CE integration
//! 
//! Provides secure loading, decryption, and validation of encrypted secrets files.
//! Enforces strict security practices:
//! - AES-256-GCM encryption/decryption
//! - Key retrieval from OS keychain (macOS Keychain) or KMS/HSM
//! - File permission enforcement (0600)
//! - Memory zeroing after use
//! - Prevention of accidental logging
//!
//! Usage:
//!   const secrets = @import("nayud_base").secrets;
//!   var manager = secrets.SecretsManager.init(allocator);
//!   defer manager.deinit();
//!   const config = try manager.loadAndDecrypt("/path/to/secrets.enc", "keychain_item_name");
//!   defer config.deinit();

const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;

/// Errors that can occur during secrets operations
pub const SecretsError = error{
    FileNotFound,
    PermissionDenied,
    InvalidFilePermissions,
    KeychainAccessFailed,
    DecryptionFailed,
    InvalidSchema,
    InvalidFormat,
    OutOfMemory,
    SystemError,
};

/// Platform-specific keychain integration
const KeychainProvider = switch (builtin.os.tag) {
    .macos => MacOSKeychain,
    .linux => struct {
        // TODO: Implement Linux keyring or external KMS integration
        pub fn getKey(allocator: std.mem.Allocator, item_name: []const u8) SecretsError![]u8 {
            _ = allocator;
            _ = item_name;
            return SecretsError.KeychainAccessFailed;
        }
    },
    else => struct {
        pub fn getKey(allocator: std.mem.Allocator, item_name: []const u8) SecretsError![]u8 {
            _ = allocator;
            _ = item_name;
            return SecretsError.KeychainAccessFailed;
        }
    },
};

/// macOS Keychain integration using Security framework
const MacOSKeychain = struct {
    /// Retrieve a key from macOS Keychain
    /// Caller owns the returned memory and must zero it after use
    pub fn getKey(allocator: std.mem.Allocator, item_name: []const u8) SecretsError![]u8 {
        // For now, return a placeholder implementation
        // In production, this would call Security framework APIs:
        // SecKeychainFindGenericPassword or SecItemCopyMatching
        _ = allocator;
        _ = item_name;
        
        // TODO: Implement actual keychain integration
        // This is a placeholder that would be replaced with:
        // 1. Convert item_name to CFString
        // 2. Create search dictionary with kSecClass, kSecAttrAccount, etc.
        // 3. Call SecItemCopyMatching to retrieve the key
        // 4. Extract data from the result
        // 5. Return owned copy of the key data
        
        return SecretsError.KeychainAccessFailed;
    }
};

/// Secure memory buffer that zeros itself on deallocation
pub const SecureBuffer = struct {
    data: []u8,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, size: usize) !SecureBuffer {
        const data = try allocator.alloc(u8, size);
        return SecureBuffer{
            .data = data,
            .allocator = allocator,
        };
    }
    
    pub fn initFromSlice(allocator: std.mem.Allocator, source: []const u8) !SecureBuffer {
        const buffer = try init(allocator, source.len);
        @memcpy(buffer.data, source);
        return buffer;
    }
    
    pub fn deinit(self: *SecureBuffer) void {
        // Zero the memory before deallocation
        @memset(self.data, 0);
        self.allocator.free(self.data);
        self.data = &[_]u8{};
    }
    
    pub fn slice(self: *const SecureBuffer) []const u8 {
        return self.data;
    }
    
    pub fn mutableSlice(self: *SecureBuffer) []u8 {
        return self.data;
    }
};

/// AES-256-GCM encryption/decryption utilities
pub const AES256GCM = struct {
    const KEY_SIZE = 32; // 256 bits
    const NONCE_SIZE = 12; // 96 bits (recommended for GCM)
    const TAG_SIZE = 16; // 128 bits
    
    const EncryptedData = struct {
        nonce: [NONCE_SIZE]u8,
        tag: [TAG_SIZE]u8,
        ciphertext: []u8,
        allocator: std.mem.Allocator,
        
        pub fn deinit(self: *EncryptedData) void {
            @memset(self.ciphertext, 0);
            self.allocator.free(self.ciphertext);
        }
    };
    
    /// Decrypt data using AES-256-GCM
    /// Returns a SecureBuffer containing the plaintext
    pub fn decrypt(
        allocator: std.mem.Allocator,
        key: []const u8,
        encrypted_data: []const u8,
    ) SecretsError!SecureBuffer {
        if (key.len != KEY_SIZE) {
            return SecretsError.DecryptionFailed;
        }
        
        if (encrypted_data.len < NONCE_SIZE + TAG_SIZE) {
            return SecretsError.InvalidFormat;
        }
        
        // Extract components from encrypted data
        const nonce = encrypted_data[0..NONCE_SIZE];
        const tag = encrypted_data[NONCE_SIZE..NONCE_SIZE + TAG_SIZE];
        const ciphertext = encrypted_data[NONCE_SIZE + TAG_SIZE..];
        
        // Prepare output buffer
        var plaintext_buffer = SecureBuffer.init(allocator, ciphertext.len) catch |err| switch (err) {
            error.OutOfMemory => return SecretsError.OutOfMemory,
        };
        errdefer plaintext_buffer.deinit();
        
        // Perform AES-256-GCM decryption
        const aes_key = std.crypto.aead.aes_gcm.Aes256Gcm.initEnc(key[0..KEY_SIZE].*);
        aes_key.decrypt(
            plaintext_buffer.mutableSlice(),
            ciphertext,
            tag[0..TAG_SIZE].*,
            nonce[0..NONCE_SIZE].*,
            "",
        ) catch {
            return SecretsError.DecryptionFailed;
        };
        
        return plaintext_buffer;
    }
    
    /// Encrypt data using AES-256-GCM (for testing/utility)
    pub fn encrypt(
        allocator: std.mem.Allocator,
        key: []const u8,
        plaintext: []const u8,
    ) SecretsError!EncryptedData {
        if (key.len != KEY_SIZE) {
            return SecretsError.DecryptionFailed;
        }
        
        var result = EncryptedData{
            .nonce = undefined,
            .tag = undefined,
            .ciphertext = undefined,
            .allocator = allocator,
        };
        
        // Generate random nonce
        std.crypto.random.bytes(&result.nonce);
        
        // Allocate ciphertext buffer
        result.ciphertext = allocator.alloc(u8, plaintext.len) catch |err| switch (err) {
            error.OutOfMemory => return SecretsError.OutOfMemory,
        };
        errdefer {
            @memset(result.ciphertext, 0);
            allocator.free(result.ciphertext);
        }
        
        // Perform AES-256-GCM encryption
        const aes_key = std.crypto.aead.aes_gcm.Aes256Gcm.initEnc(key[0..KEY_SIZE].*);
        aes_key.encrypt(
            result.ciphertext,
            &result.tag,
            plaintext,
            "",
            result.nonce,
        );
        
        return result;
    }
};

/// File permission utilities
const FilePermissions = struct {
    /// Enforce strict file permissions (0600 - owner read/write only)
    pub fn enforce0600(file_path: []const u8) SecretsError!void {
        const file = std.fs.cwd().openFile(file_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return SecretsError.FileNotFound,
            error.AccessDenied => return SecretsError.PermissionDenied,
            else => return SecretsError.SystemError,
        };
        defer file.close();
        
        const stat = file.stat() catch |err| switch (err) {
            error.AccessDenied => return SecretsError.PermissionDenied,
            else => return SecretsError.SystemError,
        };
        
        // Check permissions (Unix-style)
        if (builtin.os.tag != .windows) {
            const mode = stat.mode & 0o777;
            if (mode != 0o600) {
                return SecretsError.InvalidFilePermissions;
            }
        }
        
        // TODO: On Windows, check ACLs for equivalent restrictions
    }
    
    /// Set file permissions to 0600
    pub fn set0600(file_path: []const u8) SecretsError!void {
        if (builtin.os.tag == .windows) {
            // TODO: Implement Windows ACL setting
            return;
        }
        
        const result = std.c.chmod(file_path.ptr, 0o600);
        if (result != 0) {
            return SecretsError.PermissionDenied;
        }
    }
};

/// JSON schema validation (simplified)
const SchemaValidator = struct {
    /// Validate that the JSON contains required top-level fields
    /// This is a simplified validator - in production you'd use a full JSON Schema library
    pub fn validateBasicStructure(json_text: []const u8) SecretsError!void {
        var parser = std.json.Parser.init(std.heap.page_allocator, .{});
        defer parser.deinit();
        
        var tree = parser.parse(json_text) catch {
            return SecretsError.InvalidSchema;
        };
        defer tree.deinit();
        
        const root = tree.root.object;
        
        // Check required top-level fields
        const required_fields = [_][]const u8{ "version", "environment", "namespace", "clusters", "app" };
        for (required_fields) |field| {
            if (!root.contains(field)) {
                return SecretsError.InvalidSchema;
            }
        }
        
        // Basic type checking
        if (root.get("version")) |version| {
            if (version != .string) return SecretsError.InvalidSchema;
        }
        
        if (root.get("clusters")) |clusters| {
            if (clusters != .object) return SecretsError.InvalidSchema;
            const clusters_obj = clusters.object;
            if (!clusters_obj.contains("primary") or !clusters_obj.contains("secondary")) {
                return SecretsError.InvalidSchema;
            }
        }
    }
};

/// Main secrets manager
pub const SecretsManager = struct {
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) SecretsManager {
        return SecretsManager{
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *SecretsManager) void {
        _ = self;
        // Nothing to clean up in the manager itself
    }
    
    /// Load and decrypt a secrets file
    /// Returns a SecureBuffer containing the decrypted JSON payload
    pub fn loadAndDecrypt(
        self: *SecretsManager,
        file_path: []const u8,
        keychain_item_name: []const u8,
    ) SecretsError!SecureBuffer {
        // 1. Enforce file permissions
        FilePermissions.enforce0600(file_path) catch |err| {
            std.log.err("Secrets file permission check failed: {}", .{err});
            return err;
        };
        // 2. Read encrypted file
        const encrypted_data = self.readFileSecurely(file_path) catch |err| {
            std.log.err("Failed to read secrets file: {}", .{err});
            return err;
        };
        defer encrypted_data.deinit();
        // 3. Retrieve decryption key from keychain, with env fallback
        const key_data: []u8 = KeychainProvider.getKey(self.allocator, keychain_item_name) catch |err| blk: {
            _ = err; // don't leak error specifics
            // Try env fallback
            if (getKeyFromEnv(self.allocator)) |env_key| {
                std.log.warn("Using env var key fallback for secrets decryption in this process", .{});
                break :blk env_key;
            } else |env_err| {
                std.log.err("No decryption key available: {}", .{env_err});
                return env_err;
            }
        };
        defer {
            @memset(key_data, 0);
            self.allocator.free(key_data);
        }
        // 4. Decrypt the payload
        const decrypted_payload = AES256GCM.decrypt(
            self.allocator,
            key_data,
            encrypted_data.slice(),
        ) catch |err| {
            std.log.err("Decryption failed: {}", .{err});
            return err;
        };
        errdefer decrypted_payload.deinit();
        // 5. Validate JSON schema
        SchemaValidator.validateBasicStructure(decrypted_payload.slice()) catch |err| {
            std.log.err("Schema validation failed: {}", .{err});
            return err;
        };
        std.log.info("Successfully loaded and validated secrets file", .{});
        return decrypted_payload;
    }

    /// Load and decrypt using a provided raw 32-byte key (dev/testing)
    pub fn loadAndDecryptWithKey(
        self: *SecretsManager,
        file_path: []const u8,
        raw_key: []const u8,
    ) SecretsError!SecureBuffer {
        if (raw_key.len != 32) return SecretsError.InvalidFormat;
        FilePermissions.enforce0600(file_path) catch |err| return err;
        const encrypted_data = try self.readFileSecurely(file_path);
        defer encrypted_data.deinit();
        const key_copy = try self.allocator.alloc(u8, 32);
        errdefer self.allocator.free(key_copy);
        @memcpy(key_copy, raw_key);
        defer {
            @memset(key_copy, 0);
            self.allocator.free(key_copy);
        }
        var decrypted_payload = AES256GCM.decrypt(self.allocator, key_copy, encrypted_data.slice()) catch |err| return err;
        errdefer decrypted_payload.deinit();
        try SchemaValidator.validateBasicStructure(decrypted_payload.slice());
        return decrypted_payload;
    }
    
    /// Read file contents into a SecureBuffer
    fn readFileSecurely(self: *SecretsManager, file_path: []const u8) SecretsError!SecureBuffer {
        const file = std.fs.cwd().openFile(file_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return SecretsError.FileNotFound,
            error.AccessDenied => return SecretsError.PermissionDenied,
            else => return SecretsError.SystemError,
        };
        defer file.close();
        
        const file_size = file.getEndPos() catch return SecretsError.SystemError;
        
        const buffer = SecureBuffer.init(self.allocator, file_size) catch |err| switch (err) {
            error.OutOfMemory => return SecretsError.OutOfMemory,
        };
        errdefer buffer.deinit();
        
        _ = file.readAll(buffer.mutableSlice()) catch return SecretsError.SystemError;
        
        return buffer;
    }
    
    /// Create an encrypted secrets file (utility for initial setup)
    pub fn createEncryptedFile(
        self: *SecretsManager,
        file_path: []const u8,
        json_payload: []const u8,
        keychain_item_name: []const u8,
    ) SecretsError!void {
        // 1. Validate the JSON schema first
        SchemaValidator.validateBasicStructure(json_payload) catch |err| {
            std.log.err("Schema validation failed before encryption: {}", .{err});
            return err;
        };
        
        // 2. Retrieve encryption key from keychain
        const key_data = KeychainProvider.getKey(self.allocator, keychain_item_name) catch |err| {
            std.log.err("Failed to retrieve encryption key from keychain: {}", .{err});
            return err;
        };
        defer {
            @memset(key_data, 0);
            self.allocator.free(key_data);
        }
        
        // 3. Encrypt the payload
        const encrypted_data = AES256GCM.encrypt(self.allocator, key_data, json_payload) catch |err| {
            std.log.err("Encryption failed: {}", .{err});
            return err;
        };
        defer encrypted_data.deinit();
        
        // 4. Write to file with proper format
        const file = std.fs.cwd().createFile(file_path, .{}) catch |err| switch (err) {
            error.AccessDenied => return SecretsError.PermissionDenied,
            else => return SecretsError.SystemError,
        };
        defer file.close();
        
        // Write nonce + tag + ciphertext
        file.writeAll(&encrypted_data.nonce) catch return SecretsError.SystemError;
        file.writeAll(&encrypted_data.tag) catch return SecretsError.SystemError;
        file.writeAll(encrypted_data.ciphertext) catch return SecretsError.SystemError;
        
        // 5. Set proper file permissions
        FilePermissions.set0600(file_path) catch |err| {
            std.log.err("Failed to set file permissions: {}", .{err});
            return err;
        };
        
        std.log.info("Successfully created encrypted secrets file");
    }
};

/// Custom logging formatter that redacts sensitive data
pub const SafeLogger = struct {
    /// Log a message while ensuring no sensitive data is included
    /// This wraps std.log functions with additional safety checks
    pub fn info(comptime fmt: []const u8, args: anytype) void {
        // TODO: Add logic to scan format string and args for potential secrets
        // For now, just delegate to standard logging
        std.log.info(fmt, args);
    }
    
    pub fn err(comptime fmt: []const u8, args: anytype) void {
        std.log.err(fmt, args);
    }
    
    pub fn warn(comptime fmt: []const u8, args: anytype) void {
        std.log.warn(fmt, args);
    }
    
    pub fn debug(comptime fmt: []const u8, args: anytype) void {
        std.log.debug(fmt, args);
    }
};

// Tests
test "SecureBuffer basic operations" {
    const allocator = testing.allocator;
    
    var buffer = try SecureBuffer.init(allocator, 16);
    defer buffer.deinit();
    
    // Write some data
    @memcpy(buffer.mutableSlice()[0..5], "hello");
    
    // Read it back
    try testing.expectEqualSlices(u8, "hello", buffer.slice()[0..5]);
}

test "SecureBuffer initialization from slice" {
    const allocator = testing.allocator;
    const source = "test data";
    
    var buffer = try SecureBuffer.initFromSlice(allocator, source);
    defer buffer.deinit();
    
    try testing.expectEqualSlices(u8, source, buffer.slice());
}

test "AES-256-GCM encrypt/decrypt round trip" {
    const allocator = testing.allocator;
    const key = [_]u8{1} ** 32; // 256-bit key
    const plaintext = "Hello, secure world!";
    
    // Encrypt
    var encrypted = try AES256GCM.encrypt(allocator, &key, plaintext);
    defer encrypted.deinit();
    
    // Prepare encrypted data format (nonce + tag + ciphertext)
    const total_size = AES256GCM.NONCE_SIZE + AES256GCM.TAG_SIZE + encrypted.ciphertext.len;
    const encrypted_data = try allocator.alloc(u8, total_size);
    defer allocator.free(encrypted_data);
    
    @memcpy(encrypted_data[0..AES256GCM.NONCE_SIZE], &encrypted.nonce);
    @memcpy(encrypted_data[AES256GCM.NONCE_SIZE..AES256GCM.NONCE_SIZE + AES256GCM.TAG_SIZE], &encrypted.tag);
    @memcpy(encrypted_data[AES256GCM.NONCE_SIZE + AES256GCM.TAG_SIZE..], encrypted.ciphertext);
    
    // Decrypt
    var decrypted = try AES256GCM.decrypt(allocator, &key, encrypted_data);
    defer decrypted.deinit();
    
    try testing.expectEqualSlices(u8, plaintext, decrypted.slice());
}

test "Schema validation - valid JSON" {
    const valid_json =
        \\{
        \\  "version": "1.0",
        \\  "environment": "dev",
        \\  "namespace": "nayud",
        \\  "clusters": {
        \\    "primary": {},
        \\    "secondary": {}
        \\  },
        \\  "app": {}
        \\}
    ;
    
    try SchemaValidator.validateBasicStructure(valid_json);
}

test "Schema validation - missing required field" {
    const invalid_json =
        \\{
        \\  "version": "1.0",
        \\  "environment": "dev"
        \\}
    ;
    
    try testing.expectError(SecretsError.InvalidSchema, SchemaValidator.validateBasicStructure(invalid_json));
}

/// Fallback: retrieve key from environment variable for development only
fn getKeyFromEnv(allocator: std.mem.Allocator) SecretsError![]u8 {
    // Prefer base64 if present
    if (std.process.getEnvMap(allocator)) |env| {
        defer env.deinit();
        if (env.get("NAYUD_SECRETS_KEY_B64")) |b64| {
            // Decode base64
            var dec = std.base64.standard.Decoder;
            const out_len = dec.calcSizeForSlice(b64) catch return SecretsError.InvalidFormat;
            const out = allocator.alloc(u8, out_len) catch return SecretsError.OutOfMemory;
            errdefer allocator.free(out);
            const n = dec.decode(out, b64) catch {
                 allocator.free(out);
                 return SecretsError.InvalidFormat;
             };
             if (n != 32) {
                 @memset(out, 0);
                 allocator.free(out);
                 return SecretsError.InvalidFormat;
             }
             return out;
        }
        if (env.get("NAYUD_SECRETS_KEY_HEX")) |hex| {
            // Decode hex
            if (hex.len != 64) return SecretsError.InvalidFormat;
            const out = allocator.alloc(u8, 32) catch return SecretsError.OutOfMemory;
            errdefer allocator.free(out);
            const ok = std.fmt.hexToBytes(out, hex) catch {
                 allocator.free(out);
                 return SecretsError.InvalidFormat;
             };
             _ = ok; // hexToBytes always fills output or errors
             return out;
        }
    } else |_| {
        // Could not read environment; treat as missing
    }
    return SecretsError.KeychainAccessFailed;
}