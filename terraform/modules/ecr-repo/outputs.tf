output "repository_url" {
  description = "full URL of the ECR repository"
  value       = aws_ecr_repository.this.repository_url
}