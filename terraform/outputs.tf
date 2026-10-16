output "primary_url" {
  value = module.primary.app_url
}

output "primary_instance_id" {
  value = module.primary.instance_id
}

output "primary_bucket" {
  value = module.files_primary.id
}

output "dr_bucket" {
  value = module.files_dr.id
}

output "replicated_backups_arn" {
  value = aws_db_instance_automated_backups_replication.to_dr.id
}

output "dr_url" {
  value = var.dr_active ? module.dr[0].app_url : null
}

output "dr_instance_id" {
  value = var.dr_active ? module.dr[0].instance_id : null
}

output "primary_region" {
  value = var.primary_region
}

output "dr_region" {
  value = var.dr_region
}
