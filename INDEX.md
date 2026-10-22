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
| Lint every playbook in CI | `ansible-lint --profile production` from the repository root | `.github/workflows/examples.yml` |
| Run a pipeline end to end from a script | the commits API with an `actions` list, then poll `pipelines?sha=` | `lab/smoke.sh` |

## Controllers

| To… | Use | Where |
|---|---|---|
| Let a controller clone a private GitLab repository, read-only | a project access token (Reporter, `read_repository`) stored as a Semaphore `login_password` key | `02-semaphore-from-gitlab/run.sh` |
| Set up a Semaphore UI project without the web UI | the API: `projects`, `keys`, `repositories`, `inventory`, `environment`, `templates`, then `tasks` | `02-semaphore-from-gitlab/run.sh` |
| See which commit a controller ran | the task's `commit_message` (and `commit_hash`) in Semaphore's API | `02-semaphore-from-gitlab/run.sh` |
| Know which ansible-core a controller uses | the playbook prints `ansible_version.full`; Semaphore's image bundles its own | `02-semaphore-from-gitlab/repo/site.yml` |

## Pitfalls

| Symptom | Cause | Fix | Where |
|---|---|---|---|
| Jobs fail with `429 Too Many Requests` pulling the image | runner pull policy `always` against Docker Hub's anonymous limit | `--docker-pull-policy if-not-present`, pull the image once | `lab/up.sh` |
| `/-/readiness` returns 404 | health endpoints answer only the monitoring allowlist | wait on `/users/sign_in`, or add your network to `gitlab_rails['monitoring_whitelist']` | `lab/up.sh` |
| Semaphore exits: "Unknown database dialect: bolt" | BoltDB support removed | `SEMAPHORE_DB_DIALECT: sqlite` | `lab/compose.yml` |
| A controller's ansible-core differs from the one the project was tested with | Semaphore UI's image bundles its own ansible-core (2.20.10 in v2.19.17) | check `ansible_version.full` in a task; pin it with a custom image or an execution environment | `02-semaphore-from-gitlab/expected.txt` |
