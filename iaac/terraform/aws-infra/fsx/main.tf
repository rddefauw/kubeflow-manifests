resource "aws_security_group" "kubeflow_fsx_sg" {
  name_prefix = "kubeflow_fsx_sg"
  description = "Kubeflow FSx security group"
  vpc_id      = var.vpc_id
}

resource "aws_security_group_rule" "kubeflow_fsx_sg_ingress" {
  type              = "ingress"
  from_port         = 988 
  to_port           = 988
  protocol          = "tcp"
  source_security_group_id = var.cluster_sg
  security_group_id = aws_security_group.kubeflow_fsx_sg.id
}
resource "aws_security_group_rule" "kubeflow_fsx_sg_ingress_self" {
  type              = "ingress"
  from_port         = 988 
  to_port           = 988
  protocol          = "tcp"
  self = true
  security_group_id = aws_security_group.kubeflow_fsx_sg.id
}