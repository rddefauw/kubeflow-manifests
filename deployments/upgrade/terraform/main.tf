data "terraform_remote_state" "production" {
  backend = "local"

  config = {
    path = "../../rds-s3/terraform/terraform.tfstate"
  }
}

locals {
  cluster_name = var.cluster_name
  region       = var.cluster_region
  eks_version = var.eks_version

  using_gpu = var.node_instance_type_gpu != null

  using_velero  = var.velero_bucket != null
  velero_bucket_name = local.using_velero ? var.velero_bucket : ""

  # fix ordering using toset
  available_azs_cpu = toset(data.aws_ec2_instance_type_offerings.availability_zones_cpu.locations)
  available_azs_gpu = toset(try(data.aws_ec2_instance_type_offerings.availability_zones_gpu[0].locations, []))

  available_azs = local.using_gpu ? tolist(setintersection(local.available_azs_cpu, local.available_azs_gpu)) : tolist(local.available_azs_cpu)

  az_count = min(length(local.available_azs), 3)
  azs      = slice(local.available_azs, 0, local.az_count)

  tags = {
    Blueprint  = local.cluster_name
    GithubRepo = "github.com/awslabs/kubeflow-manifests"
    Platform = "kubeflow-on-aws"
    KubeflowVersion = "1.6"
  }

  kf_helm_repo_path = var.kf_helm_repo_path


  managed_node_group_cpu = {
    node_group_name = "managed-ondemand-cpu"
    instance_types  = [var.node_instance_type]
    min_size        = 5
    desired_size    = 5
    max_size        = 10
    subnet_ids      = data.terraform_remote_state.production.outputs.vpc_private_subnets
  }

  managed_node_group_gpu = local.using_gpu ? {
    node_group_name = "managed-ondemand-gpu"
    instance_types  = [var.node_instance_type_gpu]
    min_size        = 3
    desired_size    = 3
    max_size        = 5
    ami_type        = "AL2_x86_64_GPU"
    subnet_ids      = data.terraform_remote_state.production.outputs.vpc_private_subnets
  } : null

  potential_managed_node_groups = {
    mg_cpu = local.managed_node_group_cpu,
    mg_gpu = local.managed_node_group_gpu
  }

  managed_node_groups = { for k, v in local.potential_managed_node_groups : k => v if v != null}
}

provider "aws" {
  region = local.region
}

provider "kubernetes" {
  host                   = module.eks_blueprints.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_blueprints.eks_cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks_blueprints.eks_cluster_id]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks_blueprints.eks_cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks_blueprints.eks_cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      # This requires the awscli to be installed locally where Terraform is executed
      args = ["eks", "get-token", "--cluster-name", module.eks_blueprints.eks_cluster_id]
    }
  }
}

data "aws_ec2_instance_type_offerings" "availability_zones_cpu" {
  filter {
    name   = "instance-type"
    values = [var.node_instance_type]
  }

  location_type = "availability-zone"
}

data "aws_ec2_instance_type_offerings" "availability_zones_gpu" {
  count = local.using_gpu ? 1 : 0

  filter {
    name   = "instance-type"
    values = [var.node_instance_type_gpu]
  }

  location_type = "availability-zone"
}

#---------------------------------------------------------------
# EKS Blueprints
#---------------------------------------------------------------
module "eks_blueprints" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints?ref=v4.12.1"

  cluster_name    = local.cluster_name
  cluster_version = local.eks_version

  vpc_id             = data.terraform_remote_state.production.outputs.vpc_id
  private_subnet_ids = data.terraform_remote_state.production.outputs.vpc_private_subnets

  # configuration settings: https://github.com/aws-ia/terraform-aws-eks-blueprints/blob/main/modules/aws-eks-managed-node-groups/locals.tf
  managed_node_groups = local.managed_node_groups

  tags = local.tags
}

module "eks_blueprints_kubernetes_addons" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints//modules/kubernetes-addons?ref=v4.12.1"

  eks_cluster_id       = module.eks_blueprints.eks_cluster_id
  eks_cluster_endpoint = module.eks_blueprints.eks_cluster_endpoint
  eks_oidc_provider    = module.eks_blueprints.oidc_provider
  eks_cluster_version  = module.eks_blueprints.eks_cluster_version

  # EKS Managed Add-ons
  enable_amazon_eks_vpc_cni    = true
  enable_amazon_eks_coredns    = true
  enable_amazon_eks_kube_proxy = true
  enable_amazon_eks_aws_ebs_csi_driver = true

  # EKS Blueprints Add-ons
  enable_cert_manager = true
  enable_aws_load_balancer_controller = true
  enable_aws_efs_csi_driver = true
  enable_aws_fsx_csi_driver = true

  enable_nvidia_device_plugin = local.using_gpu
  enable_velero = local.using_velero
  velero_backup_s3_bucket = local.velero_bucket_name

  secrets_store_csi_driver_helm_config = {
    namespace   = "kube-system"
    set = [
      {
        name = "syncSecret.enabled",
        value = "true"
      }
    ]
  }
  enable_secrets_store_csi_driver = true


  csi_secrets_store_provider_aws_helm_config = {
    namespace = "kube-system"
    set = [
      {
        name = "secrets-store-csi-driver.install",
        value = "false"
      }
    ]
  }
  enable_secrets_store_csi_driver_provider_aws = true

  tags = local.tags

}

# todo: update the blueprints repo code to export the desired values as outputs
module "eks_blueprints_outputs" {
  source = "../../../iaac/terraform/utils/blueprints-extended-outputs"

  eks_cluster_id       = module.eks_blueprints.eks_cluster_id
  eks_cluster_endpoint = module.eks_blueprints.eks_cluster_endpoint
  eks_oidc_provider    = module.eks_blueprints.oidc_provider
  eks_cluster_version  = module.eks_blueprints.eks_cluster_version

  tags = local.tags
}

module "kubeflow_components" {
  source = "./rds-s3-components"

  kf_helm_repo_path = local.kf_helm_repo_path
  addon_context = module.eks_blueprints_outputs.addon_context
  enable_aws_telemetry = var.enable_aws_telemetry

  notebook_enable_culling = var.notebook_enable_culling
  notebook_cull_idle_time = var.notebook_cull_idle_time
  notebook_idleness_check_period = var.notebook_idleness_check_period
  
  use_rds = var.use_rds
  use_s3 = var.use_s3
  use_efs = var.use_efs

  vpc_id     = data.terraform_remote_state.production.outputs.vpc_id
  cidr_block = data.terraform_remote_state.production.outputs.vpc_cidr
  subnet_ids = var.publicly_accessible ? data.terraform_remote_state.production.outputs.vpc_public_subnets : data.terraform_remote_state.production.outputs.vpc_private_subnets
  security_group_id = module.eks_blueprints.cluster_primary_security_group_id
  db_security_group_id = data.terraform_remote_state.production.outputs.cluster_sg_id
  db_name = var.db_name
  db_username = var.db_username
  db_password = var.db_password
  db_class = var.db_class
  mlmdb_name = var.mlmdb_name
  db_allocated_storage = var.db_allocated_storage
  mysql_engine_version = var.mysql_engine_version
  backup_retention_period = var.backup_retention_period
  storage_type = var.storage_type
  deletion_protection = var.deletion_protection
  max_allocated_storage = var.max_allocated_storage
  publicly_accessible = var.publicly_accessible
  multi_az = var.multi_az
  secret_recovery_window_in_days = var.secret_recovery_window_in_days
  generate_db_password = var.generate_db_password

  minio_service_region = var.minio_service_region
  force_destroy_s3_bucket = var.force_destroy_s3_bucket
  minio_aws_access_key_id = var.minio_aws_access_key_id
  minio_aws_secret_access_key = var.minio_aws_secret_access_key

  s3_secret_name = data.terraform_remote_state.production.outputs.s3_secret_name
  s3_bucket_name = data.terraform_remote_state.production.outputs.s3_bucket_name
  rds_secret_name = data.terraform_remote_state.production.outputs.rds_secret_name
  rds_endpoint = data.terraform_remote_state.production.outputs.rds_endpoint
}