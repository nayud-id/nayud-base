const std = @import("std");

/// Scope of a configuration knob in Aerospike server.
pub const Scope = enum {
    global,   // service-level (node) config
    network,  // heartbeat/fabric and related networking
    namespace, // inside a namespace block
};

/// Basic type/kind of a knob value. Keep broad to avoid overfitting.
pub const ValueKind = enum {
    bool,
    int,
    uint,
    string,
    enum_,
    list,
    duration_ms,
    percent,
    bytes,
};

/// Descriptor of a single config knob. Zero-alloc, static strings only.
pub const Knob = struct {
    /// Canonical key path (e.g., "heartbeat.port", "stop-writes-pct").
    key: []const u8,
    /// Logical section/group (e.g., "heartbeat", "migrate", "durable_writes").
    section: []const u8,
    /// Where this knob lives.
    scope: Scope,
    /// Coarse-grained kind info.
    kind: ValueKind,
    /// Short description. Keep concise; detailed docs live elsewhere.
    description: []const u8,
    /// Whether known to be available in CE (Community Edition).
    ce_supported: bool = true,

    pub fn format(self: Knob, comptime _: []const u8, _: std.fmt.FormatOptions, w: anytype) !void {
        try w.print("Knob(key=\"{s}\", section=\"{s}\", scope={s}, kind={s})",
            .{ self.key, self.section, @tagName(self.scope), @tagName(self.kind) });
    }
};

/// Helper to render a simple list of knobs with a header.
pub fn renderKnobList(w: anytype, indent: []const u8, title: []const u8, items: []const Knob) !void {
    try w.print("{s}# {s}\n", .{ indent, title });
    var i: usize = 0;
    while (i < items.len) : (i += 1) {
        const it = items[i];
        try w.print("{s}- [{s}/{s}] {s} : {s}\n",
            .{ indent, @tagName(it.scope), it.section, it.key, it.description });
    }
}

pub fn noop() void {} // keep file non-empty when stripped by dead code