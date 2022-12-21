resource "aws_efs_file_system" "eks_efs_fs" {
    encrypted = true
}

resource "aws_efs_mount_target" "eks_efs_mount" {
  depends_on = [aws_security_group_rule.kubeflow_efs_sg_ingress]
  count           = length(var.cluster_subnet_ids)
  file_system_id = aws_efs_file_system.eks_efs_fs.id
  subnet_id       = var.cluster_subnet_ids[count.index]
  security_groups = [aws_security_group.kubeflow_efs_sg.id]
}

resource "aws_security_group" "kubeflow_efs_sg" {
  name_prefix = "kubeflow_efs_sg"
  description = "Kubeflow EFS security group"
  vpc_id      = var.vpc_id
}

resource "aws_security_group_rule" "kubeflow_efs_sg_ingress" {
  type              = "ingress"
  from_port         = 2049 
  to_port           = 2049
  protocol          = "tcp"
  cidr_blocks       = [var.cidr_block]
  security_group_id = aws_security_group.kubeflow_efs_sg.id
}