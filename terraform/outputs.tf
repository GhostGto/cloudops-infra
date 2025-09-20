output "ec2_public_ip" {
  description = "Public IP of EC2 instance"
  value       = aws_instance.app.public_ip
}

output "ec2_public_dns" {
  description = "Public DNS of EC2 instance"
  value       = aws_instance.app.public_dns
}

output "frontend_s3_bucket" {
  description = "Frontend S3 bucket name (if created)"
  value       = try(aws_s3_bucket.frontend_bucket[0].bucket, "")
  sensitive   = false
}

output "rds_endpoint" {
  description = "RDS endpoint (if created)"
  value       = try(aws_db_instance.postgres[0].address, "")
}
