# Running IaC and CaC from a controller: examples

Runnable examples for the **Running IaC and CaC from a controller**
series on [til.housni.eu](https://til.housni.eu/): OpenTofu/Terraform, Packer
and Ansible, run from GitLab pipelines and from a controller, against a lab
that starts on one machine. Configuration as code covers the servers
(Ansible) and GitLab itself (OpenTofu's GitLab provider).

| Directory | Entry |
|---|---|
| [`02-semaphore-from-gitlab/`](02-semaphore-from-gitlab/) | Ansible controllers in 2026: AWX paused, AAP, Semaphore UI, or plain CI |
| [`04-opentofu-gitlab-state/`](04-opentofu-gitlab-state/) | OpenTofu in a GitLab pipeline: GitLab-managed state and the OpenTofu CI/CD component |
| [`05-gitlab-as-code/`](05-gitlab-as-code/) | GitLab as code: projects, CI/CD variables, protected branches and runners with OpenTofu's GitLab provider |

Looking for a technique rather than an entry? [INDEX.md](INDEX.md) maps
each problem to the feature that solves it and the file that shows it.

## Running them

From the repository root:

```sh
lab/up.sh       # starts GitLab CE, a runner and Semaphore UI; first start takes 5 to 10 minutes
lab/check.sh    # reports anything missing; changes nothing
lab/smoke.sh    # runs a one-job pipeline end to end
lab/down.sh     # stops the lab; --wipe also deletes its data and lab/.env
```

Then each example, once the lab is up:

```sh
NN-name/run.sh | diff NN-name/expected.txt -
```

## Local lab

What the examples need, and how it was tested: Docker Engine on Linux, with
15 GB of memory and 4 CPUs; the lab itself uses about 4 GB.

| What | Version tested | Needed by | How |
|---|---|---|---|
| Docker Engine | 29.9.1 | the lab | Docker Engine or Docker Desktop, with the daemon running and your user allowed to use it |
| Docker Compose | 5.6.0 | the lab | the `docker-compose-plugin` package, or bundled with Docker Desktop |
| curl, jq, openssl | jq 1.7 | `lab/*.sh` | your distribution's packages |
| GitLab CE | 19.5.1 (`gitlab/gitlab-ce:19.5.1-ce.0`) | every example | `lab/compose.yml`, pulled by `lab/up.sh` |
| GitLab Runner | 19.5.1 (`gitlab/gitlab-runner:v19.5.1`), Docker executor | every pipeline | `lab/compose.yml`, registered by `lab/up.sh` |
| Semaphore UI | 2.19.17 (`semaphoreui/semaphore:v2.19.17`), SQLite; bundles ansible-core 2.20.10 | 02 | `lab/compose.yml` |
| Job images | `alpine:3.22`; `registry.gitlab.com/components/opentofu/gitlab-opentofu:4.9.0-opentofu1.12.6-alpine` (OpenTofu 1.12.6) | `lab/smoke.sh`; 04 | listed in `lab/job-images.txt`, pulled once by `lab/up.sh` |
| GitLab OpenTofu CI/CD component | 4.9.0 | 04, 05 | copied from gitlab.com into the lab by `lab/opentofu-component.sh` |
| OpenTofu GitLab provider (`gitlabhq/gitlab`) | 19.5.0 | 05 | downloaded by the pipeline's jobs from the OpenTofu registry, checked against `05-gitlab-as-code/repo/.terraform.lock.hcl` |
| git | 2.43 | 04, 05 | your distribution's package |

- **Nothing is exposed beyond your machine.** GitLab listens on
  `http://127.0.0.1:8929` and Semaphore UI on `http://127.0.0.1:3000`.
  Inside the lab's Docker network, `iac-lab`, GitLab is `http://gitlab`.
- **Passwords and tokens are generated** by `lab/up.sh` into `lab/.env`
  (mode 600, ignored by Git): the GitLab `root` password and an API token,
  and the Semaphore `admin` password. Compose reads that file, so
  `docker compose -f lab/compose.yml logs gitlab` and the like work as is.
- **The runner talks to the host's Docker daemon** through
  `/var/run/docker.sock`, so jobs run as sibling containers. That gives the
  jobs control of the host's Docker; fine for a lab, not for a shared
  runner.

Three things to know:

- **Docker Hub's anonymous rate limit.** With its default pull policy,
  `always`, the runner asks Docker Hub for the job image on every job and
  soon gets `429 Too Many Requests`. The lab registers the runner with
  `--docker-pull-policy if-not-present` and pulls the job image once.
- **`/-/readiness` answers 404 from the host.** GitLab serves its health
  endpoints only to its monitoring allowlist, which is `127.0.0.1` inside
  the container; `lab/up.sh` waits for the sign-in page instead.
- **Semaphore UI 2.19 has no BoltDB.** Older guides set
  `SEMAPHORE_DB_DIALECT=bolt`; 2.19 accepts `mysql`, `postgres` or
  `sqlite` and exits with "Unknown database dialect: bolt".
