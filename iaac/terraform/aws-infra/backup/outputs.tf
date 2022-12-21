output "backup_role_arn" {
    value = aws_iam_role.kubeflow_backup_role.arn
}

output "backup_vault" {
    value = aws_backup_vault.kubeflow_vault.name
}