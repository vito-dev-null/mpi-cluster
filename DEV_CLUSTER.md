# Development Cluster

## Local configuration

Copy `.env.example` to the ignored `.env` file. Set the controller and worker
SSH aliases there; keep addresses, account names, private keys, and SSH config
outside version control. Configure strict host-key verification and populate
`known_hosts` through a trusted channel before running cluster commands.

Protect SSH files locally:

```bash
install -d -m 700 "$HOME/.ssh"
chmod 600 "$HOME/.ssh/id_ed25519" "$HOME/.ssh/config"
```

No SSH key template is committed. Generate a key locally when needed and
install only its public half on authorized workers.

## Daily commands

```bash
./dev status
./dev build
./dev test
./dev run ./program [args...]
./dev benchmark
./scripts/dev_remote.sh worker1
```

The dispatcher sends MPI-aware executables through the MPI launcher. Ordinary
programs remain local unless their own application protocol supports
distribution. Discovery checks configured SSH aliases and available physical
slots for each run. Unavailable workers are excluded; explicitly requested
hosts must be discovered and trusted.

## Operational boundaries

Worker memory and filesystems remain separate. MPI ranks use the resources of
their own host, and the application must partition work and communicate state.
The launcher stages each executable and compatibility library under a
temporary runtime directory, then verifies SHA-256 hashes before execution.

The scripts do not install software, configure SSH, alter system services, or
reboot workers during normal job execution. The worker reboot helper requires
pre-authorized non-interactive `sudo`; review that policy independently.

Keep benchmark output and machine inventories local. Do not commit command
output containing hostnames, addresses, hardware fingerprints, or user data.
