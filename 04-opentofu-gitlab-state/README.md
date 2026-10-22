# 04: OpenTofu in a GitLab pipeline, with GitLab-managed state

For the entry *OpenTofu in a GitLab pipeline: GitLab-managed state and the
OpenTofu CI/CD component*.

`run.sh`:

1. **Copies GitLab's OpenTofu CI/CD component** into the lab at
   `components/opentofu`, tag `4.9.0`, from gitlab.com. A self-managed GitLab
   can't include components from gitlab.com; the component's README says to
   mirror the project under the same path. The lab's GitLab has no internet
   access, so the script pushes the tag from a clone instead of setting up a
   pull mirror, with `-o ci.skip` so the component's own image-building
   pipeline doesn't start.
2. **Pushes [`repo/`](repo/)** to the private project `root/ctl-04`:
   [`main.tf`](repo/main.tf), one built-in `terraform_data` resource and an
   empty `backend "http" {}`, and [`.gitlab-ci.yml`](repo/.gitlab-ci.yml),
   which only includes `validate-plan-apply@4.9.0`. It deletes the state left
   by a previous run, so each run starts from nothing.
3. **Runs the pipeline**: `fmt`, `validate` and `plan` run on `main`; `apply`
   waits as a manual job, which the script then starts, as a Maintainer would.
4. **Reads the state GitLab now holds**: its name, serial, the job that wrote
   it and whether it is locked (GraphQL), then its resources and outputs
   (REST).
5. **Reads the same state from outside CI**, as from an engineer's machine:
   `tofu init` and `tofu output` with the HTTP backend pointed at the
   project's state and a personal access token instead of the job token.

```sh
lab/up.sh
04-opentofu-gitlab-state/run.sh | diff 04-opentofu-gitlab-state/expected.txt -
```

Needs access to gitlab.com (the component's repository) and
registry.gitlab.com (its job image) on the first run.
