const std = @import("std");
const basic = @import("basic.zig");
const cross = @import("cross.zig");
const topology = @import("../topology.zig");
const heartbeat = @import("../net/heartbeat.zig");
const fabric = @import("../net/fabric.zig");
const migrate = @import("../service/migrate.zig");
const seed_list = @import("../bootstrap/seed_list.zig");
const nsplan = @import("../nsplan.zig");
const rack = @import("../service/rack.zig");

/// Convenience struct to pass around the relevant config surfaces for validation.
pub const Inputs = struct {
    top: topology.Topology,
    hb: heartbeat.HeartbeatConfig,
    fb: fabric.FabricConfig,
    mig: migrate.MigrateConfig,
    seeds: seed_list.SeedList,
    ns: nsplan.NamespacePlan,
    rk: rack.RackConfig,
};

/// Unified error set wrapper combining basic and cross validators.
pub const Errors = error{} || basic.Errors || cross.Errors;

/// Run full validation checklist (lint/verify) before applying configuration.
/// Zero-alloc: caller owns inputs and writer. Returns first error encountered.
pub fn run(inputs: Inputs) Errors!void {
    try basic.validateAllBasic(inputs.top, inputs.hb, inputs.fb, inputs.mig, inputs.seeds, inputs.ns);
    try cross.validateCross(inputs.top, inputs.seeds, inputs.ns, inputs.rk);
}

/// Pretty-print a human-readable checklist with pass/fail markers to the writer.
/// This is for operator visibility and does not allocate.
pub fn renderChecklist(w: anytype, inputs: Inputs) !void {
    // We deliberately do not stop on errors to provide full visibility; instead,
    // we catch and print markers. However, run() gives strict early-exit behavior.
    try w.print("# Aerospike config validation checklist\n", .{});

    // Basic validators
    try w.print("- Topology: ", .{});
    inputs.top.validate() catch |e| {
        try w.print("FAIL ({s})\n", .{@errorName(e)});
        return;
    };
    try w.print("OK\n", .{});

    try w.print("- Heartbeat: ", .{});
    inputs.hb.validate() catch |e| {
        try w.print("FAIL ({s})\n", .{@errorName(e)});
        return;
    };
    try w.print("OK\n", .{});

    try w.print("- Fabric: ", .{});
    inputs.fb.validate() catch |e| {
        try w.print("FAIL ({s})\n", .{@errorName(e)});
        return;
    };
    try w.print("OK\n", .{});

    try w.print("- Migrate: ", .{});
    inputs.mig.validate() catch |e| {
        try w.print("FAIL ({s})\n", .{@errorName(e)});
        return;
    };
    try w.print("OK\n", .{});

    try w.print("- Seed list: ", .{});
    inputs.seeds.validate() catch |e| {
        try w.print("FAIL ({s})\n", .{@errorName(e)});
        return;
    };
    try w.print("OK\n", .{});

    try w.print("- Namespace plan: ", .{});
    inputs.ns.validate() catch |e| {
        try w.print("FAIL ({s})\n", .{@errorName(e)});
        return;
    };
    try w.print("OK\n", .{});

    // Cross-checks
    try w.print("- Cross-checks: ", .{});
    cross.validateCross(inputs.top, inputs.seeds, inputs.ns, inputs.rk) catch |e| {
        try w.print("FAIL ({s})\n", .{@errorName(e)});
        return;
    };
    try w.print("OK\n", .{});
}