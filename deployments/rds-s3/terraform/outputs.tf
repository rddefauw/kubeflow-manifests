output "vpc_private_subnet_cidr" {
  description = "VPC private subnet CIDR"
  value       = module.vpc.private_subnets_cidr_blocks
}

output "vpc_public_subnet_cidr" {
  description = "VPC public subnet CIDR"
  value       = module.vpc.public_subnets_cidr_blocks
}

output "vpc_cidr" {
  description = "VPC CIDR"
  value       = module.vpc.vpc_cidr_block
}

output "eks_cluster_id" {
  description = "EKS cluster ID"
  value       = module.eks_blueprints.eks_cluster_id
}

output "eks_managed_nodegroups" {
  description = "EKS managed node groups"
  value       = module.eks_blueprints.managed_node_groups
}

output "eks_managed_nodegroup_ids" {
  description = "EKS managed node group ids"
  value       = module.eks_blueprints.managed_node_groups_id
}

output "eks_managed_nodegroup_arns" {
  description = "EKS managed node group arns"
  value       = module.eks_blueprints.managed_node_group_arn
}

output "eks_managed_nodegroup_role_name" {
  description = "EKS managed node group role name"
  value       = module.eks_blueprints.managed_node_group_iam_role_names
}

output "eks_managed_nodegroup_status" {
  description = "EKS managed node group status"
  value       = module.eks_blueprints.managed_node_groups_status
}

output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = module.eks_blueprints.configure_kubectl
}

output "region" {
  value       = local.region
  description = "AWS region"
}

output "rds_endpoint" {
  value       = try(module.kubeflow_components.rds_endpoint, null)
  description = "The address of the RDS endpoint"
}
output "rds_secret_name" {
  value       = try(module.kubeflow_components.rds_secret_name, null)
}

output "s3_bucket_name" {
  value       = try(module.kubeflow_components.s3_bucket_name, null)
  description = "The name of the created S3 bucket"
}
output "s3_secret_name" {
  value       = try(module.kubeflow_components.s3_secret_name, null)
}

output "efs_fs_id" {
  value       = try(module.kubeflow_components.efs_fs_id, null)
}

output "vpc_private_subnets" {
  description = "VPC private subnets"
  value       = module.vpc.private_subnets
}

output "vpc_public_subnets" {
  description = "VPC public subnets"
  value       = module.vpc.public_subnets
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "cluster_sg_id" {
  value = module.eks_blueprints.cluster_primary_security_group_id
}

output "backup_vault" {
  value       = try(module.kubeflow_components.backup_vault, null)
  description = "The name of the AWS Backup vault"
}

output "backup_role_arn" {
  value       = try(module.kubeflow_components.backup_role_arn, null)
  description = "The IAM role to use when taking backups"
}

output "efs_fs_arn" {
  value       = try(module.kubeflow_components.efs_fs_arn, null)
  description = "The ARN of the EFS file system"
}

output "s3_bucket_arn" {
  value       = try(module.kubeflow_components.s3_bucket_arn, null)
  description = "The ARN of the S3 bucket"
}

output "rds_arn" {
  value       = try(module.kubeflow_components.rds_arn, null)
  description = "The ARN of the RDS database"
}

output "velero_bucket_name" {
  value       = try(module.s3[0].s3_bucket_name, null)
  description = "The name of the bucket created for Velero"
}