output "fsx_fs_id" {
    value = aws_fsx_lustre_file_system.eks_fsx_fs.id
}
output "fsx_fs_dns_name" {
    value = aws_fsx_lustre_file_system.eks_fsx_fs.dns_name
}
output "fsx_fs_mount_name" {
    value = aws_fsx_lustre_file_system.eks_fsx_fs.mount_name
}