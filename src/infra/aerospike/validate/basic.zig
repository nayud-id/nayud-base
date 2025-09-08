const std = @import("std");
const topology = @import("../topology.zig");
const heartbeat = @import("../net/heartbeat.zig");
const fabric = @import("../net/fabric.zig");
const migrate = @import("../service/migrate.zig");
const seed_list = @import("../bootstrap/seed_list.zig");
const nsplan = @import("../nsplan.zig");

/// Aggregate errors for basic validators across submodules.
pub const Errors = error{
    // topology
    InvalidNodeCount, DuplicateHost, LowPlacementDiversity, InvalidInput,
    // heartbeat
    HB_InvalidPort, HB_InvalidTiming, HB_MissingSeeds, HB_DuplicateSeed, HB_MissingMulticastGroup,
    // fabric
    FB_InvalidPort, FB_InvalidThreads,
    // migrate
    MG_InvalidThreads, MG_InvalidSleepUs,
    // seed list
    SL_MissingSeeds, SL_InvalidPort, SL_DuplicateSeed, SL_BufferTooSmall,
    // namespace plan
    NS_InvalidName, NS_SizeZero, NS_MissingDevices, NS_DuplicateDevice, NS_ReplicationTooLow,
};

/// Wrap and normalize error sets from each module into Errors above (namespaced).
pub fn validateAllBasic(
    top: topology.Topology,
    hb: heartbeat.HeartbeatConfig,
    fb: fabric.FabricConfig,
    mig: migrate.MigrateConfig,
    seeds: seed_list.SeedList,
    ns: nsplan.NamespacePlan,
) Errors!void {
    // Topology
    top.validate() catch |e| switch (e) {
        topology.Errors.InvalidNodeCount => return Errors.InvalidNodeCount,
        topology.Errors.DuplicateHost => return Errors.DuplicateHost,
        topology.Errors.LowPlacementDiversity => return Errors.LowPlacementDiversity,
        topology.Errors.InvalidInput => return Errors.InvalidInput,
        else => return e,
    };

    // Heartbeat
    hb.validate() catch |e| switch (e) {
        heartbeat.Errors.InvalidPort => return Errors.HB_InvalidPort,
        heartbeat.Errors.InvalidTiming => return Errors.HB_InvalidTiming,
        heartbeat.Errors.MissingSeeds => return Errors.HB_MissingSeeds,
        heartbeat.Errors.DuplicateSeed => return Errors.HB_DuplicateSeed,
        heartbeat.Errors.MissingMulticastGroup => return Errors.HB_MissingMulticastGroup,
        else => return e,
    };

    // Fabric
    fb.validate() catch |e| switch (e) {
        fabric.Errors.InvalidPort => return Errors.FB_InvalidPort,
        fabric.Errors.InvalidThreads => return Errors.FB_InvalidThreads,
        else => return e,
    };

    // Migrate
    mig.validate() catch |e| switch (e) {
        migrate.Errors.InvalidThreads => return Errors.MG_InvalidThreads,
        migrate.Errors.InvalidSleepUs => return Errors.MG_InvalidSleepUs,
        else => return e,
    };

    // Seed list
    seeds.validate() catch |e| switch (e) {
        seed_list.Errors.MissingSeeds => return Errors.SL_MissingSeeds,
        seed_list.Errors.InvalidPort => return Errors.SL_InvalidPort,
        seed_list.Errors.DuplicateSeed => return Errors.SL_DuplicateSeed,
        seed_list.Errors.BufferTooSmall => return Errors.SL_BufferTooSmall,
        else => return e,
    };

    // Namespace plan
    ns.validate() catch |e| switch (e) {
        nsplan.Errors.InvalidName => return Errors.NS_InvalidName,
        nsplan.Errors.SizeZero => return Errors.NS_SizeZero,
        nsplan.Errors.MissingDevices => return Errors.NS_MissingDevices,
        nsplan.Errors.DuplicateDevice => return Errors.NS_DuplicateDevice,
        nsplan.Errors.ReplicationTooLow => return Errors.NS_ReplicationTooLow,
        else => return e,
    };
}