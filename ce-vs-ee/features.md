# CE vs EE Feature Boundaries (By Category)

Architecture & Clustering
- Cluster size: CE up to 8 nodes; EE up to 256 nodes
- Namespaces per cluster: CE up to 2; EE up to 32
- Multi-site clustering: EE only (additional licensing)
- Strong Consistency: EE only (additional licensing)
- Rack awareness: EE only (additional licensing)

Storage Engine
- In-Memory and Hybrid Memory: available
- All-Flash engine: EE only
- Intel Optane PMem: EE only

Security
- TLS transport encryption: EE
- ACLs and role-based access: EE
- Vault integration: EE
- LDAP integration: EE (additional licensing)
- Encryption at rest: EE (additional licensing)
- FIPS 140-2 compliance: EE

Operations & Data Movement
- Backup & Restore: available
- Cross Data Center Replication (XDR): EE
- Rapid Rebalance / Uniform Balance / Delay Fill Migrations / Quiescence: EE
- Compression: EE (additional licensing)
- Fast Restart: EE
- Durable Delete: EE
- IPv6, Read Page Cache, LRU eviction: available

Connectors (Aerospike Connect)
- Kafka, Spark, Elasticsearch, JMS, Pulsar, Trino, ESP: EE (additional licensing)

Licensing & Support
- Server license: CE (AGPLv3), EE (Commercial)
- Binaries: CE available; EE tested & verified
- Hot patches and 24x7 Enterprise support: EE

See limits.md for system limits that impact design; see mitigations.md for workarounds when using CE.