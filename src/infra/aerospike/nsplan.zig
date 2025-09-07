const std = @import("std");

/// Errors for namespace planning and validation.
pub const Errors = error{
    InvalidName,
    SizeZero,
    MissingDevices,
    DuplicateDevice,
    ReplicationTooLow,
};

/// Persistence device descriptor (path + size in bytes).
pub const Device = struct {
    path: []const u8,
    size_bytes: u64,

    pub fn format(self: Device, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("Device(path=\"{s}\", size_bytes={})", .{ self.path, self.size_bytes });
    }
};

/// Aerospike namespace plan for storage-engine memory with persistence to device(s).
/// This models an in-memory namespace with durability by persisting to one or more devices/files.
///
pub const NamespacePlan = struct {
    /// Aerospike namespace name
    name: []const u8,
    /// Total memory budget for the namespace (bytes)
    memory_size: u64,
    /// One or more persistence devices/files
    devices: []const Device,
    /// Replication factor for HA (must be >= 2)
    replication_factor: u8 = 2,

    /// Validate the plan for common mistakes and safety checks.
    pub fn validate(self: NamespacePlan) Errors!void {
        if (self.name.len == 0) return Errors.InvalidName;
        if (self.memory_size == 0) return Errors.SizeZero;
        if (self.devices.len == 0) return Errors.MissingDevices;
        if (self.replication_factor < 2) return Errors.ReplicationTooLow;

        // Ensure unique device paths and non-zero sizes.
        var i: usize = 0;
        while (i < self.devices.len) : (i += 1) {
            if (self.devices[i].size_bytes == 0) return Errors.SizeZero;
            var j: usize = i + 1;
            while (j < self.devices.len) : (j += 1) {
                if (std.mem.eql(u8, self.devices[i].path, self.devices[j].path)) {
                    return Errors.DuplicateDevice;
                }
            }
        }
    }

    /// Render a pseudo configuration snippet for aerospike.conf based on this plan.
    /// This is a helper for ops visibility; consult Aerospike docs to translate
    /// into exact config syntax for your version/edition.
    pub fn renderPseudoConf(self: NamespacePlan, writer: anytype) !void {
        try self.validate();
        try writer.print("# Pseudo-conf snippet for namespace '{s}'\n", .{self.name});
        try writer.print("namespace {s} {{\n", .{self.name});
        try writer.print("    # In-memory namespace with persistence to device(s)\n", .{});
        try writer.print("    storage-engine memory\n", .{});
        try writer.print("    replication-factor {}\n", .{self.replication_factor});
        try writer.print("    memory-size {} # bytes\n", .{self.memory_size});
        try writer.print("    # Persistence devices (translate to file/device stanzas as appropriate)\n", .{});
        for (self.devices) |d| {
            try writer.print("    device \"{s}\" {} # bytes\n", .{ d.path, d.size_bytes });
        }
        try writer.print("}}\n", .{});
    }
};

/// Convenience constructor for a simple single-device plan.
pub fn singleDevice(name: []const u8, memory_size: u64, device_path: []const u8, device_size: u64) NamespacePlan {
    return .{
        .name = name,
        .memory_size = memory_size,
        .devices = &.{.{ .path = device_path, .size_bytes = device_size }},
        // replication_factor left as default (2) for HA
    };
}