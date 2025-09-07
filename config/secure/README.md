# Secure Handling Guide (Secrets)

This document defines how to handle secrets in this repository: rotation, local-only storage, and backups off-repo. Follow these rules in development and operations.

---

## 1) Single Source of Truth (Local-only)
- Real secrets live only in your local, gitignored file: config/secure/secrets.zig
- Template to copy from: config/secure/secrets.zig.example
- Do NOT commit config/secure/secrets.zig. It is excluded by config/secure/.gitignore
- Optional env-style file for local runtime override: config/secure/secrets.env (also gitignored)

Code references:
- Centralized paths: src/config/paths.zig
- Runtime loader (env-file → env vars): src/config/secrets/loader.zig
- Canonical secrets type: src/config/secrets/types.zig
- Redaction utilities: src/security/redaction/mod.zig

---

## 2) Rotation Policy (Keys/Passwords/Certificates)
Secrets must be rotated proactively and on incidents. Aim for no-longer-than-90-day rotation for credentials used by services; shorter for high-risk material.

What to rotate:
- Aerospike client credentials (user/password)
- TLS material (CA, cert, key) if used

Standard rotation steps (developer/local):
1. Prepare new values offline (password manager or secret vault). Never share over chat/email.
2. Update your local config/secure/secrets.zig with the new values (or set env vars for testing).
3. If TLS changes, place new files locally and update only the file paths in secrets.
4. Validate locally: `zig build test` and run the app. Ensure no logs print secret values (they must be redacted).
5. Roll forward peers/operators (if any) via out-of-band secure channel.
6. Remove/revoke old credentials in Aerospike once the switch is confirmed.

Operational rotation (team/cluster):
- Use a proper secret manager (Vault/KMS/1Password/Bitwarden Business/SSM) to stage new values.
- Roll clients in waves. Maintain short overlap windows for cert/key rotations.
- Revoke old credentials as soon as safe.
- Document the rotation in an ops log (never store raw values).

Incident rotation (compromise suspected):
- Immediately generate new values; revoke old ones.
- Force client restarts with updated secrets.
- Audit access logs; increase monitoring temporarily.

---

## 3) Backups: Off-Repo Only
- Never back up real secrets inside this repository or its forks.
- Use organization-approved secure storage (password manager or secrets manager). Enforce least access.
- For TLS files, store originals in secure storage; local copies should be restricted to your workstation.
- Do not upload secrets to issue trackers, chat, CI logs, object storage, or pastebins.

Recovery notes:
- To restore: fetch from secure storage, place locally as config/secure/secrets.zig (and TLS files), and rebuild.
- Verify that .gitignore continues to exclude these files.

---

## 4) In-Code Handling (Safety Rails)
- No logging or printing secrets. Use redaction for any diagnostics.
- Use redacted helpers:
  - `security.redaction.redact("password")` → "***"
  - `security.redaction.writePairsRedacted` or `security.redaction.redactAll` for maps/pairs
  - `Secrets.toStringRedacted()` for a safe summary
- Compile-time guard prevents accidental formatting of Secrets via std.fmt/std.debug; attempting to print Secrets will fail the build.

Loader behavior:
- Load order: env-style file → environment variables
- Errors are sanitized (NotFound/InvalidFormat/Io). No secrets or file contents are logged.
- Returned secrets are owned slices. Callers are responsible for managing lifetimes.

---

## 5) Developer Workflow
1. Copy `config/secure/secrets.zig.example` to `config/secure/secrets.zig` and fill in local values.
2. Keep TLS material outside the repo and reference by path.
3. For quick experiments, you may use a local `config/secure/secrets.env` (gitignored). Prefer `secrets.zig` for authoritative values.
4. Never commit any real secret or env file. Verify with `git status` before committing.
5. Use only redacted diagnostics in commits/PRs.

---

## 6) Operational Runbook (Condensed)
- Rotate on schedule and on incidents.
- Store and distribute secrets via approved secret manager only.
- Restrict access; enforce MFA; audit usage.
- Keep backups of secrets off-repo; test recovery without exposing values.
- Validate redaction and compile-time guard in CI by attempting a forbidden print in a dedicated test if desired (must not be merged).

---

## 7) Do / Don’t
Do:
- Keep secrets local and out of VCS.
- Use redaction utilities for any diagnostics.
- Rotate regularly; clean up leaked or stale credentials.

Don’t:
- Log, print, or paste raw secrets anywhere.
- Email or chat secret values.
- Commit `config/secure/secrets.zig` or TLS files.