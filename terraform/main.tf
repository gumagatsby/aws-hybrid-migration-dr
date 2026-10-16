# London runs the application. Ireland holds a pilot light: replicated backups and files,
# with no servers until the DR switch is turned on.

module "primary" {
  source = "./modules/site"

  name                  = "hmd-primary"
  site_label            = "AWS London (${var.primary_region})"
  cidr                  = "10.20.0.0/16"
  allowed_cidr          = var.allowed_cidr
  bucket_id             = module.files_primary.id
  bucket_arn            = module.files_primary.arn
  release_key           = aws_s3_object.release.key
  instance_type         = var.instance_type
  db_instance_class     = var.db_instance_class
  backup_retention_days = var.backup_retention_days
}

# The AWS-managed RDS key in the DR region encrypts the replicated backups.
data "aws_kms_alias" "rds_dr" {
  provider = aws.dr
  name     = "alias/aws/rds"
}

# Continuous copy of the database's automated backups and transaction logs to Ireland.
resource "aws_db_instance_automated_backups_replication" "to_dr" {
  provider               = aws.dr
  source_db_instance_arn = module.primary.db_arn
  kms_key_id             = data.aws_kms_alias.rds_dr.target_key_arn
  retention_period       = var.backup_retention_days
}

module "dr" {
  source    = "./modules/site"
  count     = var.dr_active ? 1 : 0
  providers = { aws = aws.dr }

  name                     = "hmd-dr"
  site_label               = "AWS Ireland (${var.dr_region}), recovered"
  cidr                     = "10.30.0.0/16"
  allowed_cidr             = var.allowed_cidr
  bucket_id                = module.files_dr.id
  bucket_arn               = module.files_dr.arn
  release_key              = aws_s3_object.release.key
  instance_type            = var.instance_type
  db_instance_class        = var.db_instance_class
  backup_retention_days    = var.backup_retention_days
  restore_from_backups_arn = aws_db_instance_automated_backups_replication.to_dr.id
}
