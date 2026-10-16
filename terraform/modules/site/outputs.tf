output "app_url" {
  value = "http://${aws_instance.app.public_dns}"
}

output "instance_id" {
  value = aws_instance.app.id
}

output "db_arn" {
  value = aws_db_instance.this.arn
}

output "db_address" {
  value = aws_db_instance.this.address
}

output "db_secret_arn" {
  value = aws_db_instance.this.master_user_secret[0].secret_arn
}
