# tflint-ignore: terraform_unused_declarations
variable "cluster_name" {
  description = "Name of cluster"
  type        = string
}

variable "cluster_region" {
  description = "Region to create the cluster"
  type        = string
}

variable "eks_version" {
  description = "The EKS version to use"
  type        = string
  default     = "1.22"
}

variable "node_instance_type" {
  description = "The instance type of an EKS node"
  type        = string
  default     = "m5.xlarge"
}

variable "node_instance_type_gpu" {
  description = "The instance type of a gpu EKS node. Will result in the creation of a separate gpu node group when not null"
  type        = string
  default     = null
}

variable "using_velero" {
  description = "Enable velero for backups"
  type        = bool 
  default     = true
}

variable "use_rds" {
  type = bool
  default = true
}

variable "use_s3" {
  type = bool
  default = true
}

variable "use_cognito" {
  type = bool
  default = true
}

variable "use_efs" {
  type = bool
  default = true
}

variable "use_fsx" {
  type = bool
  default = true
}

variable "enable_aws_telemetry" {
  description = "Enable AWS telemetry component"
  type = bool
  default = true
}

variable "publicly_accessible" {
  type        = bool
  description = "Makes the instance publicly accessible when true"
  default = false
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

variable "kf_helm_repo_path" {
  description = "Full path to the location of the helm repo for KF"
  type        = string
  default = "../../.."
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

variable "src_vpc_private_subnets" {
  description = "EKS private subnets for production cluster"
  type = list
}
variable "src_vpc_public_subnets" {
  description = "EKS public subnets for production cluster"
  type = list
}
variable "src_vpc_id" {
  description = "VPC ID"
  type = string
}
variable "src_velero_bucket_name" {
  description = "Bucket used for Velero"
  type = string
}
variable "src_vpc_cidr" {
  description = "VPC CIDR block"
  type = string
}
variable "src_efs_fs_id" {
  description = "EFS file system ID for production cluster"
  type = string
}
variable "src_cluster_sg_id" {
  description = "Cluster security group for production cluster"
  type = string
}
variable "src_s3_secret_name" {
  description = "S3 secret for production cluster"
  type = string
}
variable "src_s3_bucket_name" {
  description = "Artifact bucket for production cluster"
  type = string
}
variable "src_rds_secret_name" {
  description = "Database secret for production cluster"
  type = string
}
variable "src_rds_endpoint" {
  description = "RDS endpoint for production cluster"
  type = string
}
variable "stage" {
  description = "Deployment stage"
  type = string
}
variable "user_pool_id" {
  description = "Cognito user pool to use"
  type = string
  default = ""
}
variable "aws_route53_subdomain_zone_name" {
  description = "Subdomain for Route 53"
  type = string
  default = ""
}
variable "cognito_user_pool_arn" {
  description = "ARN of existing user pool"
  type = string
  default = ""
}
variable "cognito_user_pool_domain" {
  description = "Domain of existing user pool"
  type = string
  default = ""
}
variable "load_balancer_scheme" {
  description = "Load Balancer Scheme"
  type        = string
  default = "internet-facing"
}
variable "certificate_arn" {
  description = "ARN of wildcard certificate for subdomain"
  type = string
  default = ""
}
variable "use_alb_redirect" {
  description = "Deploy ALB for redirection between clusters"
  type = bool
  default = false
}
variable "redirect_alias" {
  description = "DNS alias used for ALB redirection"
  type = string
  default = "kflive"
}
variable "src_stage" {
  description = "Deployment stage of production cluster"
  type = string
  default = ""
}