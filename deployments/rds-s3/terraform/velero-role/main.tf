resource "aws_s3_bucket" "velero_store" {
  bucket_prefix = "velero-"
  force_destroy = var.force_destroy_bucket
}

resource "aws_s3_bucket_acl" "velero_store_private" {
  bucket = aws_s3_bucket.velero_store.id
  acl    = "private"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "velero_store_encrypt" {
  bucket = aws_s3_bucket.velero_store.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "AES256"
    }
  }
}

resource "aws_iam_policy" "velero_policy" {
  name_prefix        = "velero-policy"
  description = "Policy for Velero"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeVolumes",
                "ec2:DescribeSnapshots",
                "ec2:CreateTags",
                "ec2:CreateVolume",
                "ec2:CreateSnapshot",
                "ec2:DeleteSnapshot"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:DeleteObject",
                "s3:PutObject",
                "s3:AbortMultipartUpload",
                "s3:ListMultipartUploadParts"
            ],
            "Resource": [
                "${aws_s3_bucket.velero_store.arn}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket"
            ],
            "Resource": [
                "${aws_s3_bucket.velero_store.arn}"
            ]
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "attach_velero_role" {
  role       = var.velero_role_name
  policy_arn = aws_iam_policy.velero_policy.arn
}