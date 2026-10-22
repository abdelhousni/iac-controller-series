# 02: Semaphore UI runs a playbook kept in GitLab

For the entry *Ansible controllers in 2026: AWX paused, AAP, Semaphore UI,
or plain CI*.

`run.sh` does what an administrator would do by hand in Semaphore UI, through
its API:

1. Pushes [`repo/site.yml`](repo/site.yml) to a **private** GitLab project,
   `root/ctl-02`.
2. Creates a GitLab **project access token** with the Reporter role and the
   `read_repository` scope, valid one day, and revokes the previous run's.
3. In Semaphore UI, creates a project `ctl-02` (replacing the previous run's)
   with a key store entry holding that token (type `login_password`), a
   repository pointing at `http://gitlab/root/ctl-02.git`, a static inventory
   (the Semaphore container itself), a variable group holding
   `ansible_connection: local`, and a template for `site.yml` on branch
   `main`. A lab shortcut: the Red Hat CoP good practices pin production
   references to a tag, never to a branch.
4. Runs the template, waits for the task and prints its status, the commit
   it ran and the lines of its log that matter.

```sh
lab/up.sh
02-semaphore-from-gitlab/run.sh | diff 02-semaphore-from-gitlab/expected.txt -
```

What the output shows:

- **Semaphore clones the repository for each task** and reports the commit
  message, so a task is tied to a commit.
- **It looks for `requirements.yml`** in `collections/`, `roles/` and the
  root, and runs `ansible-galaxy install` when it finds one.
- **The ansible-core version is Semaphore's**: 2.20.10, the one bundled in the
  `semaphoreui/semaphore:v2.19.17` image, not one pinned by the project.
