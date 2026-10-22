terraform {
  required_version = ">= 1.12"

  required_providers {
    gitlab = {
      source  = "gitlabhq/gitlab"
      version = "19.5.0"
    }
  }

  # GitLab-managed state, as in example 04.
  backend "http" {}
}

# GITLAB_BASE_URL and GITLAB_TOKEN come from this project's CI/CD variables.
provider "gitlab" {}

resource "gitlab_group" "platform" {
  name             = "platform"
  path             = "platform"
  visibility_level = "private"
}

resource "gitlab_project" "app" {
  name                   = "app"
  namespace_id           = gitlab_group.platform.id
  visibility_level       = "private"
  default_branch         = "main"
  initialize_with_readme = true
}

resource "gitlab_branch_protection" "main" {
  project            = gitlab_project.app.id
  branch             = "main"
  push_access_level  = "maintainer"
  merge_access_level = "developer"
  allow_force_push   = false
}

resource "gitlab_project_variable" "deploy_env" {
  project   = gitlab_project.app.id
  key       = "DEPLOY_ENV"
  value     = "lab"
  protected = true
}

# A runner for the project: GitLab returns its authentication token once,
# at creation, and the provider keeps it in the state.
resource "gitlab_user_runner" "app" {
  runner_type = "project_type"
  project_id  = gitlab_project.app.id
  description = "app runner"
  tag_list    = ["app"]
  untagged    = false
}

output "app_path" {
  value = gitlab_project.app.path_with_namespace
}
