output "efs_fs_id" {
    value = aws_efs_file_system.eks_efs_fs.id
}
output "efs_fs_arn" {
    value = aws_efs_file_system.eks_efs_fs.arn
}