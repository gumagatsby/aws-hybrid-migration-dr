variable "primary_region" {
  type    = string
  default = "eu-west-2"
}

variable "dr_region" {
  type    = string
  default = "eu-west-1"
}

variable "allowed_cidr" {
  description = "Who may reach the app over HTTP, e.g. your office IP as x.x.x.x/32."
  type        = string
  validation {
    condition     = can(cidrhost(var.allowed_cidr, 0)) && var.allowed_cidr != "0.0.0.0/0"
    error_message = "Give a specific CIDR; the app is not opened to the whole internet."
  }
}

variable "dr_active" {
  description = "Pilot light off (false): only data is copied to the DR region. On (true): the app is rebuilt there."
  type        = bool
  default     = false
}

variable "instance_type" {
  type    = string
  default = "t4g.micro"
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "backup_retention_days" {
  description = "Automated backups kept in each region; also the point-in-time restore window."
  type        = number
  default     = 1
  validation {
    condition     = var.backup_retention_days >= 1
    error_message = "Cross-region backup replication needs automated backups on (at least 1 day)."
  }
}
