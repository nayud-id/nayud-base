# Aerospike CE Integration — Production-Grade Plan & Checklist

Read this file before executing any task. Check off items as you complete them. Keep tasks small, modular, and DRY.

Legend: ☐ = pending, ☑ = done, 🔒 security, ⚙️ config, 🧪 test, 🚀 deploy, 🧭 ops

---

## 0) How to Use
- ☐ Always read from top to bottom before starting new work
- ☐ Complete tasks in order unless dependencies are satisfied
- ☐ Keep secrets out of logs; never print sensitive values
- ☐ Keep files under 300 lines by splitting into modules as needed

---

## 1) Foundation: Toolchain, Targets, Structure
- ☑ Lock Zig version policy (add .tool-versions or .zig-version alongside build.zig.zon minimum_zig_version)
- ☑ Confirm supported OS/CPU matrix (macOS x86_64/aarch64, Linux x86_64/aarch64) and document
  - Documented Matrix:
    - macOS: x86_64, aarch64
    - Linux: x86_64, aarch64
- ☑ Restrict build targets in build.zig (standardTargetOptions constraints) if needed
  - Enforcement: src/build/target_matrix.zig -> ensureSupportedTarget()
- ☑ Ensure build.zig.zon minimum_zig_version matches policy
  - Verified: .tool-versions → zig 0.15.1; build.zig.zon → minimum_zig_version = "0.15.1"
- ☑ Establish modular folder structure:
  - ☑ src/config/ (scaffold: src/config/mod.zig)
  - ☑ src/security/ (scaffold: src/security/mod.zig)
  - ☑ src/db/ (scaffold: src/db/mod.zig)
  - ☑ src/db/aerospike/ (scaffold: src/db/aerospike/client.zig)
  - ☑ src/observability/ (scaffold: src/observability/mod.zig)
  - ☑ src/tests/ (scaffold: src/tests/mod.zig)
  - ☑ src/infra/ (scaffold: src/infra/mod.zig)

---

## 2) Secrets & Sensitive Config (Single safest file)
- ☑ Create config/secure/.gitignore (ignore real secrets file)
  - Added: strict ignore for secrets.zig and generic secrets/cert/env patterns; allowlisted secrets.zig.example
- ☑ Add config/secure/secrets.zig.example (template only)
  - Added: Secrets struct with placeholders, example() factory, and redaction guidance
- ☑ Define single authoritative secrets file path (e.g., config/secure/secrets.zig) excluded from VCS
  - Added: src/config/paths.zig with secrets_path = "config/secure/secrets.zig" (re-exported via src/config/mod.zig); already gitignored by config/secure/.gitignore
- ☑ Implement secrets loader module (no logs, no fmt printing, sanitize on error) — Added: runtime env-file parser + env fallback, strict sanitized errors; no logging; centralized paths & types.
- ☑ Implement redaction utilities for logging (e.g., redact(key), redactAll(map)) — Added: src/security/redaction/mod.zig (MASK, redact, writePairsRedacted, redactAll); re-exported via src/security/mod.zig
- ☑ Add compile-time guard preventing accidental debug prints of secrets — Added: Secrets.format() triggers @compileError on formatting; use toStringRedacted() or security.redaction utilities
- ☑ Document secure handling (rotation, local-only storage, backups off-repo)
  - Added: config/secure/README.md covering rotation policy, local-only storage rules, and off-repo backups; references to loader/types/redaction modules

---

## 3) Aerospike Cluster Topology (CE) — In-memory with persistence
- ☑ Design 3–5 node CE cluster topology (separate AZs/racks if possible)
  - Added: src/infra/aerospike/topology.zig (Placement, Node, Topology; validate(), seeds(); constructors threeNode/fourNode/fiveNode)
  - Re-exported via src/infra/mod.zig as infra.aerospike.topology for modular access
- ☑ Namespace plan: in-memory with persistence enabled (storage-engine memory + device persistence)
  - Added: src/infra/aerospike/nsplan.zig (NamespacePlan, Device, validate(), renderPseudoConf(); singleDevice constructor)
  - Re-exported via src/infra/aerospike/mod.zig as infra.aerospike.nsplan for modular access
- ☑ Set replication-factor >= 2 for HA
  - Added: replication_factor field (default 2) with validation and render in pseudo-conf via src/infra/aerospike/nsplan.zig (NamespacePlan)
- ☑ Configure heartbeat (mesh or multicast), fabric, and migrate threads
  - Added: src/infra/aerospike/net/heartbeat.zig (HeartbeatConfig with mesh/multicast, zero-alloc validate, renderInto())
  - Added: src/infra/aerospike/net/fabric.zig (FabricConfig with validate, renderInto())
  - Added: src/infra/aerospike/service/migrate.zig (MigrateConfig with validate, renderInto())
  - Re-exported via src/infra/aerospike/net/mod.zig and src/infra/aerospike/service/mod.zig; top-level via src/infra/aerospike/mod.zig as infra.aerospike.net and infra.aerospike.service
- ☑ Configure durable writes (commit-to-device, write-commit-level, stop-writes-pct)
  - Added: src/infra/aerospike/namespace/durable_writes.zig (DurableWritesConfig with validate(), renderInto())
  - Integrated into NamespacePlan via src/infra/aerospike/nsplan.zig: durable field and rendering under namespace block
  - Re-exported via src/infra/aerospike/namespace/mod.zig and top-level src/infra/aerospike/mod.zig as infra.aerospike.namespace
- ☑ Set TTL/default-ttl, eviction, defrag, nsup-period
  - Added: src/infra/aerospike/namespace/ttl.zig (TTLConfig with validate(), renderInto())
  - Added: src/infra/aerospike/namespace/eviction.zig (EvictionConfig with validate(), renderInto())
  - Added: src/infra/aerospike/namespace/defrag.zig (DefragConfig with validate(), renderInto())
  - Added: src/infra/aerospike/namespace/nsup.zig (NsupConfig with validate(), renderInto())
  - Integrated into NamespacePlan via src/infra/aerospike/nsplan.zig: ttl, eviction, defrag, nsup fields and rendering under namespace block
  - Re-exported via src/infra/aerospike/namespace/mod.zig and top-level src/infra/aerospike/mod.zig as infra.aerospike.namespace
- ☐ Plan rack-awareness / rack-id if multi-rack
- ☐ Define seed nodes for client bootstrap

---

## 4) Server Configuration Surfaces (Maximize explicit params)
- ☐ Enumerate all relevant global, network, and namespace config knobs
- ☐ Provide a clean conf template (aerospike.conf) for dev/test
- ☐ Provide production conf template with performance and durability focus
- ☐ Document CE vs. EE feature boundaries and chosen mitigations
- ☐ Define config validation checklist (lint/verify before apply)

---

## 5) Zig FFI Client Integration (Aerospike C client)
- ☐ Add build options to toggle Aerospike client (already scaffolded) and TLS/zlib
- ☐ Define include/lib search paths via build options and env
- ☐ Create src/db/aerospike/client.zig for connection + policies plumbing
- ☐ Implement connection bootstrap with multiple seeds and auth
- ☐ Expose comprehensive client policies:
  - ☐ timeouts (total, socket), retries, backoff
  - ☐ maxConnsPerNode, tendInterval, failIfNotConnected
  - ☐ read/write/batch/scan/query policies
  - ☐ TLS (certs, ciphers, sni, ocsp), compression
- ☐ Implement health check (cluster status, node count, migrations)
- ☐ Add graceful shutdown (drain conns)

---

## 6) Config Layer (flags, env, file)
- ☐ Implement config module reading: CLI args > env vars > defaults
- ☐ Map every Aerospike server/client param (where applicable) to config surface
- ☐ Centralize credentials (user/password, TLS material) via secrets module
- ☐ Validate and normalize at startup; emit only redacted diagnostics
- ☐ Provide example .env/.args docs without real secrets

---

## 7) HA, Failover, Load Balancing, Zero Downtime
- ☐ Configure client seed list with multiple nodes
- ☐ Enable partition-aware routing and round-robin/load balance
- ☐ Tune tend interval and failure detection thresholds
- ☐ Implement active/passive endpoints abstraction (primary/secondary clusters)
- ☐ Add automatic failover policy (probe primary; switch on sustained failure)
- ☐ Ensure write consistency with replication-factor and durable write settings
- ☐ Implement dual-write or write-forwarding guard rails if using active/passive
- ☐ Design zero-downtime rolling upgrade procedure (server + client)

---

## 8) Data Parity & Consistency Strategy
- ☐ Define parity guarantees for CE (cluster-internal replication)
- ☐ If using active/passive clusters, design mirroring pipeline (client-side dual write or external tool)
- ☐ Implement idempotent write semantics
- ☐ Add periodic verification job (sampled read-verify) without logging secrets
- ☐ Document RPO/RTO and verification frequency

---

## 9) Observability & Ops
- ☐ Structured logging with redaction by default
- ☐ Expose health endpoint (app) + Aerospike info metrics
- ☐ Add latency histograms/percentiles, error rates, retries
- ☐ Add startup diagnostics (redacted) and readiness checks
- ☐ Create minimal dashboards/runbooks references

---

## 10) Testing Matrix
- 🧪 Unit tests for config parsing and redaction
- 🧪 Integration tests against local multi-node CE cluster
- 🧪 Chaos tests: kill node, net partition, disk pressure
- 🧪 Persistence tests: restart nodes; validate data durability
- 🧪 Failover tests: primary down → automatic switch
- 🧪 Performance/load tests: throughput, p99 latency, connection limits
- 🧪 Long-running soak with migrations

---

## 11) Backup/Restore & Recovery
- ☐ Define backup approach (asbackup/asrestore or client-driven snapshots)
- ☐ Automate restore drills (non-prod) with validation
- ☐ Document recovery steps and RPO/RTO

---

## 12) Documentation & Compliance
- ☐ Security guidelines (no logs, handling secrets, rotation policy)
- ☐ Operator runbooks (scale up/down, node replace, rolling restarts)
- ☐ Upgrade runbook (server/client)
- ☐ Incident response playbook (failover, data checks)

---

## 13) CI/CD Guardrails
- ☐ Lint configs, validate secrets not committed
- ☐ Run tests (unit/integration) on PR
- ☐ Ship artifacts with configs separated from secrets

---

## Execution Order (Short Form)
1) Foundation & Secrets (Sections 1–2)
2) Cluster Topology & Server Config (Sections 3–4)
3) Client Integration & Config Layer (Sections 5–6)
4) HA/Failover/Parity (Sections 7–8)
5) Observability & Ops (Section 9)
6) Tests & CI/CD (Sections 10 & 13)
7) Backup/Restore & Docs (Sections 11–12)

---

Tip: Keep each code file <300 LOC; split into reusable modules. Avoid duplicate logic and centralize policies in config and security modules.