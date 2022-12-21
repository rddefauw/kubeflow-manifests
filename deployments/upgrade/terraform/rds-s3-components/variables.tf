variable "kf_helm_repo_path" {
  description = "Full path to the location of the helm folder to install from for KF 1.6"
  type        = string
}

variable "addon_context" {
  description = "Input configuration for the addon"
  type = object({
    aws_caller_identity_account_id = string
    aws_caller_identity_arn        = string
    aws_eks_cluster_endpoint       = string
    aws_partition_id               = string
    aws_region_name                = string
    eks_cluster_id                 = string
    eks_oidc_issuer_url            = string
    eks_oidc_provider_arn          = string
    tags                           = map(string)
    irsa_iam_role_path             = string
    irsa_iam_permissions_boundary  = string
  })
}

variable "enable_aws_telemetry" {
  description = "Enable AWS telemetry component"
  type = bool
  default = true
}

variable "use_rds" {
  type = bool
  default = true
}

variable "use_s3" {
  type = bool
  default = true
}

variable "use_efs" {
  type = bool
  default = true
}

variable "vpc_id" {
  type        = string
  description = "VPC of the EKS cluster"
}

variable "cidr_block" {
  type        = string
  description = "VPC CIDR block"
}

variable "efs_fs_id" {
  type        = string
  description = "EFS file system ID"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet ids of the EKS cluster"
}

variable "security_group_id" {
  type        = string
  description = "SecurityGroup Id of a EKS Worker Node"
}
variable "db_security_group_id" {
  type        = string
}

variable "mlmdb_name" {
  type        = string
  default = "metadb"
  description = "Name of the mlm DB to create"
}

variable "minio_service_region" {
  type        = string
  default = null
  description = "S3 service region. Change this field if the S3 bucket will be in a different region than the EKS cluster"
}

variable "minio_service_host" {
  type        = string
  default = "s3.amazonaws.com"
  description = "S3 service host DNS. This field will need to be changed when making requests from other partitions e.g. China Regions"
}

variable "notebook_enable_culling" {
  description = "Enable Notebook culling feature. If set to true then the Notebook Controller will scale all Notebooks with Last activity older than the notebook_cull_idle_time to zero"
  type = string
  default = false
}

variable "notebook_cull_idle_time" {
  description = "If a Notebook's LAST_ACTIVITY_ANNOTATION from the current timestamp exceeds this value then the Notebook will be scaled to zero (culled). ENABLE_CULLING must be set to 'true' for this setting to take effect.(minutes)"
  type = string
  default = 30
}

variable "notebook_idleness_check_period" {
  description = "How frequently the controller should poll each Notebook to update its LAST_ACTIVITY_ANNOTATION (minutes)"
  type = string
  default = 5
}

variable "s3_secret_name" {
  type = string
}
variable "s3_bucket_name" {
  type = string
}
variable "rds_secret_name" {
  type = string
}
variable "rds_endpoint" {
  type = string
}
