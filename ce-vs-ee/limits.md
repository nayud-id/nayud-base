# System Limits (CE vs EE)

Core limits affecting sizing and topology
- Max nodes per cluster: CE 8; EE 256
- Max namespaces: CE 2; EE 32
- Max records per namespace per node: CE ~4.29B; EE up to ~5.5e11 (or 2^39 at certain index settings)
- Cluster data limit: CE roughly ~2.5 TB unique data across 8 nodes (assumes overhead); EE unlimited
- Max device/file size: 2 TiB; Max devices per namespace per node: 128

Notes
- Actual maximums are bounded by RAM and storage capacity
- Review replication factor implications for AP vs SC modes