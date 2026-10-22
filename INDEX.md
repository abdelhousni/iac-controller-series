# Technique index

The [README](README.md) lists the examples by entry. This page lists them by
the problem they solve, so you can find "how do I…" without opening each
one. Every path is relative to the repository root.

## The lab

| To… | Use | Where |
|---|---|---|
| Run GitLab CE, a runner and Semaphore UI on one machine | Docker Compose, one network for all three | `lab/compose.yml` |
| Fit GitLab CE in about 3 GB | turn off Prometheus monitoring, fewer Puma workers and Sidekiq threads | `lab/compose.yml` (`GITLAB_OMNIBUS_CONFIG`) |
| Create a GitLab access token without the web UI | `gitlab-rails runner` with `personal_access_tokens.create!` and `set_token` | `lab/up.sh` |
| Register a runner the GitLab 16+ way | `POST /api/v4/user/runners`, then `gitlab-runner register --token` | `lab/up.sh` |
| Let job containers reach GitLab by name | `--docker-network-mode` and `--clone-url` at registration | `lab/up.sh` |
| Check the lab before running anything | `lab/check.sh` | `lab/check.sh` |
| Run a pipeline end to end from a script | the commits API with an `actions` list, then poll `pipelines?sha=` | `lab/smoke.sh` |

## Pitfalls

| Symptom | Cause | Fix | Where |
|---|---|---|---|
| Jobs fail with `429 Too Many Requests` pulling the image | runner pull policy `always` against Docker Hub's anonymous limit | `--docker-pull-policy if-not-present`, pull the image once | `lab/up.sh` |
| `/-/readiness` returns 404 | health endpoints answer only the monitoring allowlist | wait on `/users/sign_in`, or add your network to `gitlab_rails['monitoring_whitelist']` | `lab/up.sh` |
| Semaphore exits: "Unknown database dialect: bolt" | BoltDB support removed | `SEMAPHORE_DB_DIALECT: sqlite` | `lab/compose.yml` |
