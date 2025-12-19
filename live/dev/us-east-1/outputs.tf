output "ecr_repository_urls" {
  description = "Map of ECR repository URLs for dev"
  value = {
    for name, mod in module.ecr_repos :
    name => mod.repository_url
  }
}