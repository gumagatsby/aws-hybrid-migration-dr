# One complete copy of the application in one region: network, database and app server.
# London builds it with a new database; Ireland builds it from London's replicated backups.
terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

data "aws_region" "this" {}

data "aws_availability_zones" "up" {
  state = "available"
}

data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

locals {
  azs     = slice(data.aws_availability_zones.up.names, 0, 2)
  restore = var.restore_from_backups_arn != null
}

# --- Network: public subnets for the app server, private subnets for the database. No NAT gateway.

resource "aws_vpc" "this" {
  cidr_block           = var.cidr
  enable_dns_hostnames = true
  tags                 = { Name = var.name }
}

resource "aws_default_security_group" "locked" {
  vpc_id = aws_vpc.this.id
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = var.name }
}

resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.this.id
  availability_zone = local.azs[count.index]
  cidr_block        = cidrsubnet(var.cidr, 8, count.index)
  tags              = { Name = "${var.name}-public-${count.index}" }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.this.id
  availability_zone = local.azs[count.index]
  cidr_block        = cidrsubnet(var.cidr, 8, count.index + 10)
  tags              = { Name = "${var.name}-private-${count.index}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = { Name = "${var.name}-public" }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Free gateway endpoint: S3 traffic stays on the AWS network.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.this.region}.s3"
  route_table_ids   = [aws_route_table.public.id]
  vpc_endpoint_type = "Gateway"
}

resource "aws_security_group" "app" {
  name        = "${var.name}-app"
  description = "App server: HTTP from the allowed range only"
  vpc_id      = aws_vpc.this.id
}

resource "aws_vpc_security_group_ingress_rule" "app_http" {
  security_group_id = aws_security_group.app.id
  description       = "HTTP from the allowed range"
  cidr_ipv4         = var.allowed_cidr
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "app_https" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS to AWS APIs and package repositories"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "app_db" {
  security_group_id            = aws_security_group.app.id
  description                  = "PostgreSQL to the database"
  referenced_security_group_id = aws_security_group.db.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_security_group" "db" {
  name        = "${var.name}-db"
  description = "Database: PostgreSQL from the app server only"
  vpc_id      = aws_vpc.this.id
}

resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  description                  = "PostgreSQL from the app server"
  referenced_security_group_id = aws_security_group.app.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

# --- Database

resource "aws_db_subnet_group" "this" {
  name       = var.name
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_db_instance" "this" {
  # review: accept RDS_SINGLE_AZ Disaster recovery is the pilot light in Ireland, not a standby in London
  identifier     = var.name
  engine         = "postgres"
  engine_version = local.restore ? null : "17"
  instance_class = var.db_instance_class

  # New database in the primary region; point-in-time restore from replicated backups in DR.
  db_name  = local.restore ? null : "jobs"
  username = local.restore ? null : "jobsadmin"
  dynamic "restore_to_point_in_time" {
    for_each = local.restore ? [1] : []
    content {
      source_db_instance_automated_backups_arn = var.restore_from_backups_arn
      use_latest_restorable_time               = true
    }
  }
  manage_master_user_password = true

  allocated_storage      = 20
  storage_type           = "gp3"
  storage_encrypted      = true
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period    = var.backup_retention_days
  copy_tags_to_snapshot      = true
  auto_minor_version_upgrade = true

  iam_database_authentication_enabled   = true
  performance_insights_enabled          = true
  performance_insights_retention_period = 7 # the free retention period
  apply_immediately                     = true

  # Demo environment, destroyed after each run. A client database would keep a final snapshot
  # and deletion protection on.
  skip_final_snapshot = true
  deletion_protection = false
}

# --- App server

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "app" {
  statement {
    sid       = "ListBucket"
    actions   = ["s3:ListBucket"]
    resources = [var.bucket_arn]
  }
  statement {
    sid       = "ReadReleasesAndMigrationDumps"
    actions   = ["s3:GetObject"]
    resources = ["${var.bucket_arn}/releases/*", "${var.bucket_arn}/migration/*"]
  }
  statement {
    sid       = "ReadWriteUploads"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${var.bucket_arn}/uploads/*"]
  }
  statement {
    sid       = "ReadDatabaseSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_db_instance.this.master_user_secret[0].secret_arn]
  }
}

resource "aws_iam_role" "app" {
  name               = "${var.name}-app"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy" "app" {
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.app.json
}

# Session Manager instead of SSH: no key pairs, no port 22.
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.name}-app"
  role = aws_iam_role.app.name
}

resource "aws_instance" "app" {
  ami                         = nonsensitive(data.aws_ssm_parameter.al2023_arm64.value)
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.app.id]
  iam_instance_profile        = aws_iam_instance_profile.app.name
  associate_public_ip_address = true
  ebs_optimized               = true

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = true
  }

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    region      = data.aws_region.this.region
    bucket      = var.bucket_id
    release_key = var.release_key
    db_host     = aws_db_instance.this.address
    secret_arn  = aws_db_instance.this.master_user_secret[0].secret_arn
    site_label  = var.site_label
  })
  user_data_replace_on_change = true

  tags = { Name = "${var.name}-app" }

  lifecycle {
    ignore_changes = [ami]
  }
}
