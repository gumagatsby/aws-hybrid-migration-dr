variable "name" {
  type = string
}

variable "site_label" {
  description = "Shown on the app's pages, so you can see which region served them."
  type        = string
}

variable "cidr" {
  type = string
}

variable "allowed_cidr" {
  type = string
}

variable "bucket_id" {
  type = string
}

variable "bucket_arn" {
  type = string
}

variable "release_key" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "db_instance_class" {
  type = string
}

variable "backup_retention_days" {
  type = number
}

variable "restore_from_backups_arn" {
  description = "Replicated automated backups to restore from. Null creates a new, empty database."
  type        = string
  default     = null
}
