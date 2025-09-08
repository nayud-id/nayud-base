const std = @import("std");
const topology = @import("../topology.zig");
const rack = @import("../service/rack.zig");
const seed_list = @import("../bootstrap/seed_list.zig");
const nsplan = @import("../nsplan.zig");

/// Cross-surface validation errors that involve multiple modules at once.
pub const Errors = error{
    InsufficientSeedsForNodes,
    DuplicateSeedsAcrossSources,
    ReplicationExceedsNodes,
    RackCoverageInsufficient,
};

/// Cross-checks that rely on multiple inputs. Zero-alloc, caller supplies data.
pub fn validateCross(
    top: topology.Topology,
    seeds: seed_list.SeedList,
    ns: nsplan.NamespacePlan,
    rk: rack.RackConfig,
) Errors!void {
    // Seeds vs node count: ensure seeds.len <= node count and >= 2
    if (seeds.seeds.len > top.nodes.len or seeds.seeds.len < 2) {
        return Errors.InsufficientSeedsForNodes;
    }

    // RF <= nodes
    if (ns.replication_factor > top.nodes.len) {
        return Errors.ReplicationExceedsNodes;
    }

    // Rack coverage: when enabled and RF>1, ensure at least RF distinct racks
    if (rk.enabled and ns.replication_factor > 1) {
        if (rk.distinctRackCount() < ns.replication_factor) {
            return Errors.RackCoverageInsufficient;
        }
    }
}