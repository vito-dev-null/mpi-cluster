# MPI Cluster Toolkit

Scripts for running MPI workloads across a locally configured controller and
workers. Tracked files contain generic aliases only; machine inventory,
addresses, credentials, and SSH configuration belong in local, ignored files.

## Configure

Copy `.env.example` to `.env` and set `MPI_CONTROLLER` and `MPI_WORKERS` to
generic SSH aliases. The controller defaults to `localhost`. Configure worker
aliases in the user's SSH config; do not commit keys, known-hosts data, or
machine-specific addresses. Use trusted `known_hosts` entries because the
scripts require `StrictHostKeyChecking=yes`.

Create SSH keys locally when needed, then protect them with restrictive modes:

```bash
install -d -m 700 "$HOME/.ssh"
chmod 600 "$HOME/.ssh/id_ed25519" "$HOME/.ssh/config"
```

`hosts.example` is a generic Open MPI hostfile template. The launcher discovers
configured hosts dynamically and does not consume a committed hostfile.

## Run

Build portable MPI programs with generic CPU targets, then invoke:

```bash
./scripts/run_mpi.sh ./program [args...]
```

The launcher checks discovery and available slots, stages the executable and
compatibility library, verifies SHA-256 hashes, and rejects oversubscription.
Worker paths and host-specific settings are not embedded in the scripts.

## Validate

```bash
./scripts/check_cluster.sh
./tests/test_cluster.sh
REPEATS=3 ITERATIONS=120000000 ./scripts/benchmark.sh
```

Benchmark results are runtime output and should not be committed if they
contain environment details. The health-check workflow reports operational
status without listing interface addresses or actual hostnames.

See [DEV_CLUSTER.md](DEV_CLUSTER.md) for local setup and [RUNNER.md](RUNNER.md)
for optional self-hosted GitHub Actions setup.
