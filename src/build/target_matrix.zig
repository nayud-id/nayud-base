const std = @import("std");

pub const SupportedCombo = struct {
    os: std.Target.Os.Tag,
    arch: std.Target.Cpu.Arch,
};

pub fn allowed() []const SupportedCombo {
    return &.{
        .{ .os = .macos, .arch = .x86_64 },
        .{ .os = .macos, .arch = .aarch64 },
        .{ .os = .linux, .arch = .x86_64 },
        .{ .os = .linux, .arch = .aarch64 },
    };
}

fn isAllowed(os: std.Target.Os.Tag, arch: std.Target.Cpu.Arch) bool {
    const combos = allowed();
    for (combos) |c| {
        if (c.os == os and c.arch == arch) return true;
    }
    return false;
}

/// Ensure the selected target matches the supported OS/CPU matrix.
/// Fails the build early with a clear message if the target is unsupported.
pub fn ensureSupportedTarget(b: *std.Build, target: std.Build.ResolvedTarget) void {
    _ = b; // reserved for potential future use (e.g., logging/diagnostics)
    const os = target.result.os.tag;
    const arch = target.result.cpu.arch;

    if (!isAllowed(os, arch)) {
        // Keep message static to avoid allocator usage in the build script.
        std.debug.panic(
            "Unsupported target: {s}/{s}. Allowed targets: macos/x86_64, macos/aarch64, linux/x86_64, linux/aarch64",
            .{ @tagName(os), @tagName(arch) },
        );
    }
}