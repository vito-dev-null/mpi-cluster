# Self-hosted GitHub Actions Runner

Use a self-hosted runner only on an isolated controller host with access to
the intended workers. Limit repository access, review workflow changes before
execution, and do not use this runner for untrusted pull requests. The runner
can access the host's SSH credentials and private network.

Pass the repository URL at setup time; no owner, repository slug, hostname, or
registration token is stored in this repository:

```bash
./scripts/bootstrap_runner.sh https://github.com/OWNER/REPOSITORY
```

The script obtains a short-lived registration token through the authenticated
GitHub CLI, uses it for runner registration, and unsets it on exit. Service
installation requires non-interactive `sudo`. The default runner name is the
generic `mpi-controller`; set `RUNNER_NAME` locally if multiple runners need
distinct names. The workflows request read-only repository permissions and
serialize cluster operations.

Validate service state through the host's service manager. Runner service
configuration and credentials remain local and must never be committed.
