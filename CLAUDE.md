# Working in iac-controller-series

Companion examples for the "Running IaC from a controller, the GitOps way"
series on til.housni.eu (abdelhousni/til). The plan and state of the series
are in abdelhousni/til-workbench `iac-controller/README.md` (private).

- Each example is `NN-name/` with a `run.sh`, an `expected.txt`, a README,
  a row in the root README table and rows in `INDEX.md` for each technique
  and pitfall it shows. CI fails if an example directory has no row in
  `INDEX.md`.
- Every example runs against the lab in `lab/` (GitLab CE, GitLab Runner,
  Semaphore UI on Docker). An example that needs a new tool or image adds
  it to the README's "Local lab" table and to `lab/check.sh` in the same
  pull request.
- Before opening a pull request, from a fresh clone: `lab/up.sh`, then
  `lab/check.sh` passes and every `run.sh` matches its `expected.txt`.
- Deterministic output only: no timestamps, IDs, tokens or host-specific
  values in `expected.txt`.
- Never commit a secret. `lab/up.sh` generates passwords and tokens into
  `lab/.env`, which is ignored.

## Commits

Commits are authored by the repository owner: check
`git var GIT_AUTHOR_IDENT` before the first commit and expect
`abdelhousni <23284113+abdelhousni@users.noreply.github.com>`. Credit Claude
only with a `Co-Authored-By` trailer, and don't add a `Claude-Session:`
trailer. Commit messages follow Conventional Commits, with the example
directory or `lab` as the scope.
