# My AWS Provider region
provider "aws" {
  region = "us-east-1"
}

#All data current
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

#DynamoDB table. Has not been connected to Lambda2 yet
resource "aws_dynamodb_table" "transaction_table" {

  #hash-key represents my primary key in my defined schema
  hash_key     = "transaction_id"
  name         = "TransactionTable"
  billing_mode = "PAY_PER_REQUEST"


  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.kms_key.arn
  }

  attribute {
    name = "transaction_id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name        = "DynamoDB Table"
    Environment = "Production"
  }
}

#KMS Key
resource "aws_kms_key" "kms_key" {
  description             = "Encryption key"
  enable_key_rotation     = true
  deletion_window_in_days = 20
  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "key_1"
    Statement = [
      {
        Sid    = "EnableIAMUserPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        },
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowLambda1roletousekey"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${aws_iam_role.lambda_1.name}"
        },
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ],
        Resource = "*"
      },
      {
        Sid    = "AllowLambda2roletousekey"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${aws_iam_role.lambda_2.name}"
        },
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ],
        Resource = "*"
      },
      {
        Sid    = "AllowCloudTrailtousekey"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = [
          "kms:GenerateDataKey",
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowSQStousekey"
        Effect = "Allow"
        Principal = {
          Service = "sqs.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowCloudWatchLogstousekey"
        Effect = "Allow"
        Principal = {
          Service = "logs.us-east-1.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
}

#CloudTrail 
resource "aws_cloudtrail" "trails" {
  depends_on = [aws_s3_bucket_policy.dynamobucket, aws_sns_topic_policy.sns_policy]

  name                          = "trailfordynamodb002"
  s3_bucket_name                = aws_s3_bucket.dynamodbbucket001.id
  s3_key_prefix                 = "prefix"
  include_global_service_events = true
  is_multi_region_trail         = true
  sns_topic_name                = aws_sns_topic.output.name
  enable_log_file_validation    = true
  kms_key_id                    = aws_kms_key.kms_key.arn
  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail_loggroup.arn}:*"
  cloud_watch_logs_role_arn = aws_iam_role.cloudtrail.arn

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::DynamoDB::Table"
      values = ["arn:${data.aws_partition.current.partition}:dynamodb:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:table/TransactionTable"]
    }
  }

}

#CloudWatch Log Group
resource "aws_cloudwatch_log_group" "cloudtrail_loggroup" {
  name = "CTLogGroup"
  kms_key_id = aws_kms_key.kms_key.arn

  tags = {
    Environment = "Production"
  }
}

#IAM execution role for CloudTrail
resource "aws_iam_role" "cloudtrail" {
  name = "execution_role_cloudtrail"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = "AssumeRole"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Name        = "Execution Role"
    Environment = "Production"
  }
}

#IAM policy for CloudTrail
resource "aws_iam_policy" "cloudtrail_policy" {
  name        = "cloudtrail_policy"
  path        = "/"
  description = "Policy for CloudTrail"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "logs:PutLogEvents"
        Effect   = "Allow"
        Sid      = "PutLogsEvents"
        Resource = "arn:aws:logs:us-east-1:${data.aws_caller_identity.current.account_id}:log-group:${aws_cloudwatch_log_group.cloudtrail_loggroup.name}:log-stream:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cloudtrail_attach" {
  role       = aws_iam_role.cloudtrail.name
  policy_arn = aws_iam_policy.cloudtrail_policy.arn
}


#CloudTrail bucket
#checkov:skip=CKV2_AWS_61:Lifecycle policy not required for this portfolio project
#checkov:skip=CKV_AWS_144:Cross-region replication not required for this use case
#checkov:skip=CKV2_AWS_62:S3 event notifications not required for this portfolio project
resource "aws_s3_bucket" "dynamodbbucket001" {
  bucket        = "dynamodbtrails1244"
  force_destroy = true
}

resource "aws_s3_bucket_logging" "logging_bucket" {
  bucket = aws_s3_bucket.dynamodbbucket001.id

  target_bucket = aws_s3_bucket.dynamodbbucket001.id
  target_prefix = "log/"
  target_object_key_format {
    partitioned_prefix {
      partition_date_source = "EventTime"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "block_public_access" {
  bucket = aws_s3_bucket.dynamodbbucket001.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

#CloudTrail bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "encrypted" {
  bucket = aws_s3_bucket.dynamodbbucket001.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.kms_key.arn
    }
  }
}

#CloudTrail bucket versioning
resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.dynamodbbucket001.id
  versioning_configuration {
    status = "Enabled"
  }
}

#IAM Policy on S3 Cloudtrail bucket
data "aws_iam_policy_document" "dynamodbbucket" {
  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.dynamodbbucket001.arn]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:cloudtrail:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:trail/trailfordynamodb002"]
    }
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.dynamodbbucket001.arn}/prefix/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:cloudtrail:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:trail/trailfordynamodb002"]
    }
  }
}

resource "aws_s3_bucket_policy" "dynamobucket" {
  bucket = aws_s3_bucket.dynamodbbucket001.id
  policy = data.aws_iam_policy_document.dynamodbbucket.json
}

# Dead letter queue for lambda functions
resource "aws_sqs_queue" "queue_deadletter" {
  name              = "deadletter-queue"
  kms_master_key_id = aws_kms_key.kms_key.id
}

#SQS resource poilicy
resource "aws_sqs_queue_policy" "deadletter_policy" {
  queue_url = aws_sqs_queue.queue_deadletter.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowLambdaToSendMessage"
        Effect = "Allow"
        Principal = {
          AWS = [
            aws_iam_role.lambda_1.arn,
            aws_iam_role.lambda_2.arn
          ]
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.queue_deadletter.arn
      }
    ]
  })
}

#SNS Topic
resource "aws_sns_topic" "output" {
  name              = "transactions"
  kms_master_key_id = aws_kms_key.kms_key.arn
}

#SNS Subscription
resource "aws_sns_topic_subscription" "to_email" {
  topic_arn = aws_sns_topic.output.arn
  protocol  = "email"
  endpoint  = var.email
}

#SNS Policy Document
resource "aws_sns_topic_policy" "sns_policy" {
  arn = aws_sns_topic.output.arn

  policy = data.aws_iam_policy_document.sns_topic_policy.json
}

data "aws_iam_policy_document" "sns_topic_policy" {
  policy_id = "AllowCloudTrail"

  statement {
    actions = [
      "SNS:Publish",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"

      values = [
        "arn:${data.aws_partition.current.partition}:cloudtrail:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:trail/trailfordynamodb002",
      ]
    }

    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    resources = [
      aws_sns_topic.output.arn,
    ]

    sid = "ToAllowCloudTrail"
  }
}

#Eventbridge to send requests from Lambda1 to Lambda2. Has not been connected yet
resource "aws_cloudwatch_event_bus" "transaction_event_bus" {
  name = "transaction-event-bus"

  tags = {
    Name        = "Transaction Event Bus"
    Environment = "Production"
  }

}

#IAM execution role for lambda1
resource "aws_iam_role" "lambda_1" {
  name = "execution_role_lambda1"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = "AssumeRole"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Name        = "Execution Role"
    Environment = "Production"
  }
}

#IAM policy for Lambda1
resource "aws_iam_policy" "lambda1_policy" {
  name        = "lambda1_policy"
  path        = "/"
  description = "Policy for Lambda 1"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "events:PutEvents"
        Effect   = "Allow"
        Sid      = "PutEvents"
        Resource = "arn:aws:events:us-east-1:${data.aws_caller_identity.current.account_id}:event-bus/transaction-event-bus"
      },
      {
        Action   = "logs:CreateLogGroup"
        Effect   = "Allow"
        Sid      = "CreateLogGroup"
        Resource = "arn:aws:logs:us-east-1:${data.aws_caller_identity.current.account_id}:log-group:*"
      },
      {
        Action   = "logs:CreateLogStream"
        Effect   = "Allow"
        Sid      = "CreateLogStream"
        Resource = "arn:aws:logs:us-east-1:${data.aws_caller_identity.current.account_id}:log-group:*:log-stream:*"
      },
      {
        Action   = "logs:PutLogEvents"
        Effect   = "Allow"
        Sid      = "PutLogsEvents"
        Resource = "arn:aws:logs:us-east-1:${data.aws_caller_identity.current.account_id}:log-group:*:log-stream:*"
      },
      {
        Action   = "sqs:SendMessage"
        Effect   = "Allow"
        Sid      = "Sendmessagetosqsdeadletterqueue"
        Resource = "arn:aws:sqs:us-east-1:${data.aws_caller_identity.current.account_id}:${aws_sqs_queue.queue_deadletter.name}"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_attach_1" {
  role       = aws_iam_role.lambda_1.name
  policy_arn = aws_iam_policy.lambda1_policy.arn
}

# Package the Lambda1 function code
data "archive_file" "lambda1" {
  type        = "zip"
  source_file = "${path.module}/lambda1.py"
  output_path = "${path.module}/lambda1.zip"
}

# Lambda generator function
#checkov:skip=CKV_AWS_117:Lambda functions communicate with AWS managed services via IAM-controlled endpoints. VPC not required.
#checkov:skip=CKV_AWS_272:Code signing not required for this single-developer portfolio project
resource "aws_lambda_function" "lambda1" {
  filename                       = data.archive_file.lambda1.output_path
  function_name                  = "lambda1_generator"
  role                           = aws_iam_role.lambda_1.arn
  handler                        = "lambda1.lambda_generate"
  code_sha256                    = data.archive_file.lambda1.output_base64sha256
  kms_key_arn                    = aws_kms_key.kms_key.arn
  reserved_concurrent_executions = 10

  runtime = "python3.13"

  #For X-ray tracing
  tracing_config {
    mode = "Active"
  }

  #For messages not sent to SNS
  dead_letter_config {
    target_arn = aws_sqs_queue.queue_deadletter.arn
  }

  #Environment variables
  environment {
    variables = {
      ENVIRONMENT = "Production"
      LOG_LEVEL   = "info"
    }
  }

  tags = {
    Environment = "Production"
    Application = "Transaction Generator"
  }
}

#IAM execution role for Lambda 2
resource "aws_iam_role" "lambda_2" {
  name = "execution_role_lambda2"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = "AssumeRole"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Name        = "Lambda Processor"
    Environment = "Production"
  }
}

#IAM policy for Lambda 2
resource "aws_iam_policy" "lambda2_policy" {
  name        = "lambda2_policy"
  path        = "/"
  description = "Policy for Lambda 2"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "sns:Publish"
        Effect   = "Allow"
        Sid      = "PutMessage"
        Resource = "arn:aws:sns:us-east-1:${data.aws_caller_identity.current.account_id}:${aws_sns_topic.output.name}"
      },
      {
        Action   = "logs:CreateLogGroup"
        Effect   = "Allow"
        Sid      = "CreateLogGroup"
        Resource = "arn:aws:logs:us-east-1:${data.aws_caller_identity.current.account_id}:log-group:*"
      },
      {
        Action   = "logs:CreateLogStream"
        Effect   = "Allow"
        Sid      = "CreateLogStream"
        Resource = "arn:aws:logs:us-east-1:${data.aws_caller_identity.current.account_id}:log-group:*:log-stream:*"
      },
      {
        Action   = "logs:PutLogEvents"
        Effect   = "Allow"
        Sid      = "PutLogsEvents"
        Resource = "arn:aws:logs:us-east-1:${data.aws_caller_identity.current.account_id}:log-group:*:log-stream:*"
      },
      {
        Action   = "dynamodb:PutItem"
        Effect   = "Allow"
        Sid      = "PutItemInDynamoDB"
        Resource = "arn:aws:dynamodb:us-east-1:${data.aws_caller_identity.current.account_id}:table/TransactionTable"
      },
      {
        Action   = "dynamodb:GetItem"
        Effect   = "Allow"
        Sid      = "GetItemFromDynamoDB"
        Resource = "arn:aws:dynamodb:us-east-1:${data.aws_caller_identity.current.account_id}:table/TransactionTable"
      },
      {
        Action   = "sqs:SendMessage"
        Effect   = "Allow"
        Sid      = "Sendmessagetosqsdeadletterqueue"
        Resource = "arn:aws:sqs:us-east-1:${data.aws_caller_identity.current.account_id}:${aws_sqs_queue.queue_deadletter.name}"
      }
    ]
  })
}

#Attaches IAM Role and Policy to Lambda2
resource "aws_iam_role_policy_attachment" "lambda_attach_2" {
  role       = aws_iam_role.lambda_2.name
  policy_arn = aws_iam_policy.lambda2_policy.arn
}

# Package the Lambda2 function code
data "archive_file" "lambda2" {
  type        = "zip"
  source_file = "${path.module}/lambda2.py"
  output_path = "${path.module}/lambda2.zip"
}

# Lambda processor function
#checkov:skip=CKV_AWS_117:Lambda functions communicate with AWS managed services via IAM-controlled endpoints. VPC not required.
#checkov:skip=CKV_AWS_272:Code signing not required for this single-developer portfolio project
resource "aws_lambda_function" "lambda2" {
  filename                       = data.archive_file.lambda2.output_path
  function_name                  = "lambda2_processor"
  role                           = aws_iam_role.lambda_2.arn
  handler                        = "lambda2.lambda_processor"
  code_sha256                    = data.archive_file.lambda2.output_base64sha256
  kms_key_arn                    = aws_kms_key.kms_key.arn
  reserved_concurrent_executions = 10

  runtime = "python3.13"

  #For X-ray tracing
  tracing_config {
    mode = "Active"
  }

  # For messages not sent to SNS
  dead_letter_config {
    target_arn = aws_sqs_queue.queue_deadletter.arn
  }

  environment {
    variables = {
      ENVIRONMENT   = "Production"
      LOG_LEVEL     = "info"
      SNS_TOPIC_ARN = aws_sns_topic.output.arn
    }
  }

  tags = {
    Environment = "Production"
    Application = "Transaction Processor"
  }
}

#EventBridge Rule
resource "aws_cloudwatch_event_rule" "allow_access_to_lambda_2" {
  name           = "events_lambda2"
  description    = "Put events in Lambda2 function"
  event_bus_name = aws_cloudwatch_event_bus.transaction_event_bus.name

  event_pattern = jsonencode({
    source      = ["transaction.generator"]
    detail-type = ["TransactionEvent"]
  })
}

#EventBridge targets the Lambda function
resource "aws_cloudwatch_event_target" "lambda2" {
  rule           = aws_cloudwatch_event_rule.allow_access_to_lambda_2.name
  target_id      = "SendToLambda"
  arn            = aws_lambda_function.lambda2.arn
  event_bus_name = aws_cloudwatch_event_bus.transaction_event_bus.name
}


#Lambda2 permission to allow EventBridge invoke it
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda2.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.allow_access_to_lambda_2.arn
}