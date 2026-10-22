# 05: GitLab as code with the GitLab provider

For the entry *GitLab as code: projects, CI/CD variables, protected branches
and runners with OpenTofu's GitLab provider*.

`run.sh`:

1. **Bootstraps by hand** the one thing OpenTofu can't create for itself: the
   configuration project `root/gitlab-config`, with two protected CI/CD
   variables for the provider, `GITLAB_BASE_URL` and `GITLAB_TOKEN` (masked).
   The lab uses root's token; see the entry for what a real setup uses.
2. **Starts from nothing**: schedules the `platform` group of a previous run
   for deletion (GitLab renames it, which frees the path) and deletes the
   state.
3. **Pushes [`repo/`](repo/)**: [`main.tf`](repo/main.tf) (a group, a
   project in it, protection for its `main` branch, a protected CI/CD variable
   and a project runner), the provider lock file
   [`.terraform.lock.hcl`](repo/.terraform.lock.hcl) (gitlabhq/gitlab 19.5.0),
   and the same `.gitlab-ci.yml` as example 04.
4. **Runs the pipeline**, prints what the plan creates, and plays the manual
   apply.
5. **Reads back through GitLab's API** what now exists, and whether the
   runner's authentication token is in the OpenTofu state (it is).
6. **Runs the pipeline again**: the plan reports no changes.

```sh
lab/up.sh
05-gitlab-as-code/run.sh | diff 05-gitlab-as-code/expected.txt -
```

The jobs download the provider from the OpenTofu registry, so they need
internet access, as do the first run's component copy (gitlab.com) and job
image (registry.gitlab.com).
