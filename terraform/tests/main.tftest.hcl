# Runs against a mocked AWS provider: no account, no credentials, no cost.

mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111122223333:role/mock" }
  }
  mock_resource "aws_s3_bucket" {
    defaults = { arn = "arn:aws:s3:::mock-bucket" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }
  mock_data "aws_availability_zones" {
    defaults = { names = ["eu-west-2a", "eu-west-2b", "eu-west-2c"] }
  }
  mock_data "aws_ssm_parameter" {
    defaults = { value = "ami-0123456789abcdef0" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_resource "aws_db_instance" {
    defaults = {
      arn                = "arn:aws:rds:eu-west-2:111122223333:db:hmd-primary"
      master_user_secret = [{ secret_arn = "arn:aws:secretsmanager:eu-west-2:111122223333:secret:rds-db-abc", kms_key_id = "", secret_status = "active" }]
    }
  }
}

mock_provider "aws" {
  alias = "dr"
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111122223333:role/mock" }
  }
  mock_resource "aws_s3_bucket" {
    defaults = { arn = "arn:aws:s3:::mock-bucket" }
  }
  mock_data "aws_kms_alias" {
    defaults = { target_key_arn = "arn:aws:kms:eu-west-1:111122223333:key/0000" }
  }
  mock_data "aws_availability_zones" {
    defaults = { names = ["eu-west-1a", "eu-west-1b", "eu-west-1c"] }
  }
  mock_data "aws_ssm_parameter" {
    defaults = { value = "ami-0123456789abcdef0" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_resource "aws_db_instance_automated_backups_replication" {
    defaults = { id = "arn:aws:rds:eu-west-1:111122223333:auto-backup:ab-0000" }
  }
  mock_resource "aws_db_instance" {
    defaults = {
      arn                = "arn:aws:rds:eu-west-1:111122223333:db:hmd-dr"
      master_user_secret = [{ secret_arn = "arn:aws:secretsmanager:eu-west-1:111122223333:secret:rds-db-def", kms_key_id = "", secret_status = "active" }]
    }
  }
}

variables {
  allowed_cidr = "203.0.113.10/32"
}

run "pilot_light_off_by_default" {
  assert {
    condition     = length(module.dr) == 0
    error_message = "No servers or databases should run in the DR region until dr_active is set."
  }
  assert {
    condition     = aws_db_instance_automated_backups_replication.to_dr.source_db_instance_arn == module.primary.db_arn
    error_message = "London's backups must replicate to the DR region even while the pilot light is off."
  }
  assert {
    condition     = one(aws_s3_bucket_replication_configuration.files.rule).status == "Enabled"
    error_message = "Files must replicate to the DR bucket."
  }
}

run "site_is_locked_down" {
  module {
    source = "./modules/site"
  }
  variables {
    name                  = "hmd-test"
    site_label            = "test"
    cidr                  = "10.20.0.0/16"
    bucket_id             = "hmd-files"
    bucket_arn            = "arn:aws:s3:::hmd-files"
    release_key           = "releases/app.zip"
    instance_type         = "t4g.micro"
    db_instance_class     = "db.t4g.micro"
    backup_retention_days = 1
  }
  assert {
    condition     = !aws_db_instance.this.publicly_accessible && aws_db_instance.this.storage_encrypted
    error_message = "Database must be private and encrypted."
  }
  assert {
    condition     = aws_db_instance.this.manage_master_user_password && aws_db_instance.this.password == null
    error_message = "Database password must be generated and held by Secrets Manager, never in code."
  }
  assert {
    condition     = aws_db_instance.this.db_name == "jobs" && length(aws_db_instance.this.restore_to_point_in_time) == 0
    error_message = "Without a backup source the site should create a new database."
  }
  assert {
    condition     = aws_instance.app.metadata_options[0].http_tokens == "required" && aws_instance.app.root_block_device[0].encrypted
    error_message = "App server must require IMDSv2 and encrypt its disk."
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.app_http.cidr_ipv4 == "203.0.113.10/32"
    error_message = "HTTP must be limited to the allowed range."
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.db_from_app.referenced_security_group_id == aws_security_group.app.id
    error_message = "Only the app server may reach the database."
  }
}

run "site_restores_when_given_backups" {
  module {
    source = "./modules/site"
  }
  variables {
    name                     = "hmd-test-dr"
    site_label               = "test"
    cidr                     = "10.30.0.0/16"
    bucket_id                = "hmd-files"
    bucket_arn               = "arn:aws:s3:::hmd-files"
    release_key              = "releases/app.zip"
    instance_type            = "t4g.micro"
    db_instance_class        = "db.t4g.micro"
    backup_retention_days    = 1
    restore_from_backups_arn = "arn:aws:rds:eu-west-1:111122223333:auto-backup:ab-0000"
  }
  assert {
    condition     = aws_db_instance.this.restore_to_point_in_time[0].source_db_instance_automated_backups_arn == "arn:aws:rds:eu-west-1:111122223333:auto-backup:ab-0000"
    error_message = "DR database must be restored from the replicated backups."
  }
  assert {
    condition     = aws_db_instance.this.restore_to_point_in_time[0].use_latest_restorable_time
    error_message = "Restore should use the latest restorable time, to lose as little data as possible."
  }
}

run "dr_restores_from_replicated_backups" {
  variables {
    dr_active = true
  }
  assert {
    condition     = length(module.dr) == 1
    error_message = "Turning on the pilot light should build the DR site."
  }
  assert {
    condition     = output.dr_url != null
    error_message = "DR site should expose its URL."
  }
}

run "app_is_never_open_to_the_internet" {
  command = plan
  variables {
    allowed_cidr = "0.0.0.0/0"
  }
  expect_failures = [var.allowed_cidr]
}

run "backups_must_be_on" {
  command = plan
  variables {
    backup_retention_days = 0
  }
  expect_failures = [var.backup_retention_days]
}
