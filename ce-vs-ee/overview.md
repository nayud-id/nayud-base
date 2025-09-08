# Aerospike CE vs EE — Overview

Purpose
- Document key feature boundaries between Community Edition (CE) and Enterprise Edition (EE)
- Capture practical mitigations and design choices when running CE in production-like environments
- Keep guidance modular and DRY: specific topics are split across files in this folder

Scope and audience
- Engineers integrating Aerospike into infrastructure and applications
- Ops/SRE teams planning capacity, durability, and disaster recovery

How to use this folder
- Read features.md for a categorized summary of CE vs EE differences
- Read limits.md for hard limits that impact sizing and topology
- Read mitigations.md for actionable mitigations and design patterns when features are EE-only

Notes
- This documentation summarizes public Aerospike materials and our own operational guidance.
- For production deployments where you need features like Strong Consistency, XDR, TLS/ACLs, or large clusters, plan for Enterprise Edition.