# Files: one bucket per region. Everything written in London is replicated to Ireland.
data "aws_caller_identity" "me" {}

locals {
  account = data.aws_caller_identity.me.account_id
}

module "files_primary" {
  source = "./modules/bucket"
  name   = "hmd-files-${local.account}-${var.primary_region}"
}

module "files_dr" {
  source    = "./modules/bucket"
  providers = { aws = aws.dr }
  name      = "hmd-files-${local.account}-${var.dr_region}"
}

data "aws_iam_policy_document" "replication_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "replication" {
  statement {
    actions   = ["s3:GetReplicationConfiguration", "s3:ListBucket"]
    resources = [module.files_primary.arn]
  }
  statement {
    actions   = ["s3:GetObjectVersionForReplication", "s3:GetObjectVersionAcl", "s3:GetObjectVersionTagging"]
    resources = ["${module.files_primary.arn}/*"]
  }
  statement {
    actions   = ["s3:ReplicateObject", "s3:ReplicateDelete", "s3:ReplicateTags"]
    resources = ["${module.files_dr.arn}/*"]
  }
}

resource "aws_iam_role" "replication" {
  name               = "hmd-s3-replication"
  assume_role_policy = data.aws_iam_policy_document.replication_assume.json
}

resource "aws_iam_role_policy" "replication" {
  role   = aws_iam_role.replication.id
  policy = data.aws_iam_policy_document.replication.json
}

resource "aws_s3_bucket_replication_configuration" "files" {
  bucket = module.files_primary.id
  role   = aws_iam_role.replication.arn

  rule {
    id     = "all-to-dr"
    status = "Enabled"
    filter {}
    delete_marker_replication { status = "Enabled" }
    destination {
      bucket        = module.files_dr.arn
      storage_class = "STANDARD"
    }
  }

  depends_on = [module.files_primary, module.files_dr]
}

# The app itself is shipped as a release archive in the bucket, so it replicates
# to the DR region with everything else.
data "archive_file" "release" {
  type        = "zip"
  source_dir  = "${path.module}/../app"
  output_path = "${path.module}/.build/app.zip"
  excludes    = ["tests", "__pycache__", "Dockerfile", ".pytest_cache"]
}

resource "aws_s3_object" "release" {
  bucket      = module.files_primary.id
  key         = "releases/app-${data.archive_file.release.output_md5}.zip"
  source      = data.archive_file.release.output_path
  source_hash = data.archive_file.release.output_md5

  depends_on = [aws_s3_bucket_replication_configuration.files]
}
