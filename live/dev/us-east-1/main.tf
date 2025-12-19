locals {
  # Build full repo names with a prefix, e.g. "jimag-dev-inventory-svc"
  full_repo_names = [
    for r in var.ecr_repos : "${var.name_prefix}-${r}"
  ]
}

module "ecr_repos" {
  source = "../../../terraform/modules/ecr-repo"

  for_each = toset(local.full_repo_names)

  name = each.value
}