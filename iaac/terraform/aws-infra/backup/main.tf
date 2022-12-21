resource "aws_backup_vault" "kubeflow_vault" {
  name        = "kubeflow_backup_vault"
}

resource "aws_iam_role" "kubeflow_backup_role" {
  name_prefix = "kubeflow_backup_role"
  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": ["sts:AssumeRole"],
      "Effect": "allow",
      "Principal": {
        "Service": ["backup.amazonaws.com"]
      }
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "kubeflow_backup_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
  role       = aws_iam_role.kubeflow_backup_role.name
}

resource "aws_backup_plan" "kubeflow_plan" {
  count = var.use_scheduled_backup ? 1 : 0
  name = "kubeflow_backup_plan"

  rule {
    rule_name         = "kubeflow_backup_rule"
    target_vault_name = aws_backup_vault.kubeflow_vault.name
    schedule          = "cron(0 1 * * ? *)"

    lifecycle {
      delete_after = 14
    }
  }

}

resource "aws_backup_selection" "kubeflow_backup_resources" {
  count = var.use_scheduled_backup ? 1 : 0
  iam_role_arn = aws_iam_role.kubeflow_backup_role.arn
  name         = "kubeflow_backup_resources"
  plan_id      = aws_backup_plan.kubeflow_plan[0].id

  resources = var.resources
}
