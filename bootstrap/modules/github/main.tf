resource "github_repository" "workload" {
  name                   = var.repository
  description            = "Azure Red Hat OpenShift application landing zone managed by ALZ.ARO."
  visibility             = "private"
  auto_init              = true
  has_issues             = true
  has_discussions        = false
  delete_branch_on_merge = true
  allow_merge_commit     = false
  allow_squash_merge     = true
  allow_rebase_merge     = false
}

resource "github_repository_vulnerability_alerts" "workload" {
  repository = github_repository.workload.name
  enabled    = true
}

resource "github_branch_default" "workload" {
  repository = github_repository.workload.name
  branch     = "main"
}

data "github_user" "approver" {
  for_each = var.apply_environment_reviewers_enabled ? toset(var.apply_approvers) : toset([])
  username = each.value
}

resource "github_repository_environment" "plan" {
  repository  = github_repository.workload.name
  environment = "plan"
}

resource "github_repository_environment" "apply" {
  repository          = github_repository.workload.name
  environment         = "apply"
  prevent_self_review = var.apply_environment_reviewers_enabled

  dynamic "reviewers" {
    for_each = var.apply_environment_reviewers_enabled ? [1] : []
    content {
      users = [for user in data.github_user.approver : user.id]
    }
  }
}

resource "github_repository_file" "managed" {
  for_each            = var.repository_files
  repository          = github_repository.workload.name
  branch              = github_branch_default.workload.branch
  file                = each.key
  content             = each.value
  commit_message      = "chore: bootstrap ALZ.ARO workload"
  overwrite_on_create = true
}

locals {
  repository_variables = {
    AZURE_TENANT_ID              = var.tenant_id
    AZURE_SUBSCRIPTION_ID        = var.workload_subscription_id
    CONNECTIVITY_SUBSCRIPTION_ID = var.connectivity_subscription_id
    TF_BACKEND_RESOURCE_GROUP    = var.backend_resource_group_name
    TF_BACKEND_STORAGE_ACCOUNT   = var.backend_storage_account_name
    TF_BACKEND_CONTAINER         = var.backend_container_name
    TF_BACKEND_KEY               = "aro.tfstate"
  }
}

resource "github_actions_variable" "repository" {
  for_each      = local.repository_variables
  repository    = github_repository.workload.name
  variable_name = each.key
  value         = each.value
}

resource "github_actions_environment_variable" "client_id" {
  for_each      = var.client_ids
  repository    = github_repository.workload.name
  environment   = each.key == "plan" ? github_repository_environment.plan.environment : github_repository_environment.apply.environment
  variable_name = "AZURE_CLIENT_ID"
  value         = each.value
}
