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

## OpenTofu

| To… | Use | Where |
|---|---|---|
| Use a gitlab.com CI/CD component on a self-managed GitLab | copy the project to the same path (`components/opentofu`) with its release tag; push with `-o ci.skip` | `04-opentofu-gitlab-state/run.sh` |
| Run fmt, validate, plan and a manual apply with three lines of CI | `include: component: $CI_SERVER_FQDN/components/opentofu/validate-plan-apply@4.9.0` | `04-opentofu-gitlab-state/repo/.gitlab-ci.yml` |
| Keep OpenTofu state in GitLab | `backend "http" {}`; `gitlab-tofu` fills in the address and the job token | `04-opentofu-gitlab-state/repo/main.tf` |
| Start a manual job from a script | `POST /projects/:id/jobs/:job_id/play` | `04-opentofu-gitlab-state/run.sh` |
| See a project's states, serials and locks | GraphQL `project { terraformStates { nodes { name lockedAt latestVersion { serial } } } }` | `04-opentofu-gitlab-state/run.sh` |
| Read GitLab-managed state from outside CI | `TF_HTTP_ADDRESS`, `TF_HTTP_USERNAME`, `TF_HTTP_PASSWORD` (a personal access token), then `tofu init` | `04-opentofu-gitlab-state/run.sh` |
| Start a run from no state | `DELETE /projects/:id/terraform/state/:name` | `04-opentofu-gitlab-state/run.sh` |
| Pre-pull every job image once | `lab/job-images.txt`, read by `lab/up.sh` and `lab/check.sh` | `lab/job-images.txt` |

## Pitfalls

| Symptom | Cause | Fix | Where |
|---|---|---|---|
| Jobs fail with `429 Too Many Requests` pulling the image | runner pull policy `always` against Docker Hub's anonymous limit | `--docker-pull-policy if-not-present`, pull the image once | `lab/up.sh` |
| `/-/readiness` returns 404 | health endpoints answer only the monitoring allowlist | wait on `/users/sign_in`, or add your network to `gitlab_rails['monitoring_whitelist']` | `lab/up.sh` |
| Semaphore exits: "Unknown database dialect: bolt" | BoltDB support removed | `SEMAPHORE_DB_DIALECT: sqlite` | `lab/compose.yml` |
| A controller's ansible-core differs from the one the project was tested with | Semaphore UI's image bundles its own ansible-core (2.20.10 in v2.19.17) | check `ansible_version.full` in a task; pin it with a custom image or an execution environment | `02-semaphore-from-gitlab/expected.txt` |
| A Semaphore task reports `success` but its log lacks the last lines | the status can be stored before the last log lines | poll the task's `output` until the play recap appears | `02-semaphore-from-gitlab/run.sh` |
| `include: component: gitlab.com/components/opentofu/…` fails on a self-managed GitLab | components can't be included across instances | copy the component project to the same path on your instance | `04-opentofu-gitlab-state/run.sh` |
| Pushing a copy of the component starts its own pipeline, which builds images | the component's `.gitlab-ci.yml` runs on push | `git push -o ci.skip` | `04-opentofu-gitlab-state/run.sh` |
