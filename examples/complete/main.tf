provider "aws" {
  region = var.region
}

## This is the module being used
module "cis_alarms" {
  source         = "../../"
  log_group_name = aws_cloudwatch_log_group.default.name
}

## Everything after this is standard cloudtrail setup
data "aws_caller_identity" "current" {}

module "cloudtrail_s3_bucket" {
  source = "git::https://github.com/cloudposse/terraform-aws-cloudtrail-s3-bucket.git?ref=0.12.0"

  force_destroy = true

  context = module.this.context
}

resource "aws_cloudwatch_log_group" "default" {
  name = module.this.id
  tags = module.this.tags
}

data "aws_iam_policy_document" "log_policy" {
  statement {
    effect  = "Allow"
    actions = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = [
      "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:${aws_cloudwatch_log_group.default.name}:log-stream:*"
    ]
  }
}

data "aws_iam_policy_document" "assume_policy" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      identifiers = ["cloudtrail.amazonaws.com"]
      type        = "Service"
    }
  }
}

resource "aws_iam_role" "cloudtrail_cloudwatch_events_role" {
  name               = lower(join(module.this.delimiter, [module.this.id, "role"]))
  assume_role_policy = data.aws_iam_policy_document.assume_policy.json
  tags               = module.this.tags
}

resource "aws_iam_role_policy" "policy" {
  name   = lower(join(module.this.delimiter, [module.this.id, "policy"]))
  policy = data.aws_iam_policy_document.log_policy.json
  role   = aws_iam_role.cloudtrail_cloudwatch_events_role.id
}

module "cloudtrail" {
  // https://github.com/cloudposse/terraform-aws-cloudtrail
  source                        = "git::https://github.com/cloudposse/terraform-aws-cloudtrail.git?ref=0.14.0"
  context                       = module.this.context
  enable_log_file_validation    = true
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_logging                = true
  // TODO: Add event_selector
  s3_bucket_name = module.cloudtrail_s3_bucket.bucket_id
  // https://github.com/terraform-providers/terraform-provider-aws/issues/14557#issuecomment-671975672
  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.default.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_cloudwatch_events_role.arn
}
