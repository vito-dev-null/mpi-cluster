# MPI Cluster Architecture

## Roles

- Controller: local entry point for builds, status checks, and job submission.
- Workers: SSH-reachable hosts that execute MPI ranks.
- Discovery: validates configured aliases and estimates available slots for
  each invocation.
- Launcher: stages executable inputs, checks SHA-256 integrity, and invokes
  Open MPI with explicit mapping and binding options.

Host aliases are provided through the ignored `.env` file and the user's SSH
configuration. No inventory, address, account name, key, or runtime output is
part of the architecture artifact.

## Execution model

This is a distributed job environment, not a shared-memory system. Each MPI
rank uses the memory and filesystem of its own host. Applications must express
parallel work and communicate state explicitly; ordinary single-process
programs remain local.

The launcher discovers workers at job start, rejects unavailable or
unconfigured targets, validates requested slots, transfers required inputs,
and verifies their hashes before execution. SSH is non-interactive and uses
strict host-key checking against locally trusted known-hosts data.

## Security boundaries

- Keep host mappings and SSH configuration outside version control.
- Do not store credentials or private keys in the repository.
- Use least-privilege accounts and avoid passwordless privileged commands.
- Keep CI runners isolated and restrict who can modify workflows.
- Treat benchmark and diagnostic output as potentially identifying data.
- Keep generated binaries and runtime artifacts out of source control unless
  their provenance and contents have been reviewed.
