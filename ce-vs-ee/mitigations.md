# Mitigations When Using CE

This document lists practical mitigations when Enterprise-only features are not available.

Strong Consistency (EE-only)
- Operate in AP mode with careful data modeling: use idempotent writes and reconcile on read
- Use generation checks (optimistic concurrency) and write-commit-level=all to reduce windows of inconsistency
- Enable durable writes (commit-to-device) to improve durability on power loss

XDR (Cross Datacenter Replication) (EE-only)
- Use scheduled backup & restore for DR and cold-standby clusters
- For near-real-time replication, bridge with Kafka or custom change feeds at the application layer
- Consider dual-writes and per-site reconciliation if acceptable

Rack Awareness (EE-only)
- Use orchestration anti-affinity to spread nodes across racks/zones
- Maintain RF >= 2 and validate topology so single-rack failure leaves quorum
- Plan maintenance with controlled node drains and tuned migration throttles

All-Flash / Fast Restart / Rapid Rebalance (EE-only)
- Use Hybrid Memory with tuned device settings where possible
- Plan maintenance windows for index rebuild time; lower default-ttl and evict-pct to control index pressure
- Tune migrate.threads and migrate.sleep-us to balance rebalance speed vs production load

Security (TLS, ACLs, Vault, LDAP) (EE-only)
- Run CE clusters on private networks with strict firewall rules and no public exposure
- Terminate TLS in front (service mesh, mTLS sidecars, or L4 proxies) and use network policies
- Enforce authN/authZ at the application/API layer; isolate ops access with jump hosts and audit

Compression / Durable Delete (EE-only)
- Compress payloads at the application layer if needed
- Use application-level tombstones or soft-delete markers with GC processes

Capacity & Limits (CE)
- Respect CE limits: 8 nodes, 2 namespaces, ~2.5 TB unique data budget; shard by cluster when needed
- Keep replication and device sizing conservative; test migration behavior under failure scenarios

Operational Hygiene
- Monitor migrations and cluster health; pre-flight checks before maintenance
- Regular backups with verification restores; document RPO/RTO expectations