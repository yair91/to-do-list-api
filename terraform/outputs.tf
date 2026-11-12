output "api_url" {
  value = "http://${aws_instance.app.public_ip}:8000"
}

output "instance_id" {
  value = aws_instance.app.id
}

output "public_ip" {
  value = aws_instance.app.public_ip
}

output "rds_endpoint" {
  value = aws_db_instance.db.address
}

output "rds_identifier" {
  value = aws_db_instance.db.identifier
}

output "secret_name" {
  value = aws_secretsmanager_secret.db.name
}

output "sns_topic_arn" {
  value = aws_sns_topic.alertas.arn
}

output "dashboard_url" {
  value = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards/dashboard/${aws_cloudwatch_dashboard.app.dashboard_name}"
}

output "ssh_private_key" {
  value     = tls_private_key.ssh.private_key_openssh
  sensitive = true
}
