locals {
  cluster_name = var.cluster_name
  region       = var.cluster_region
  eks_version = var.eks_version

  using_gpu = var.node_instance_type_gpu != null

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
    subnet_ids      = var.src_vpc_private_subnets
  }

  managed_node_group_gpu = local.using_gpu ? {
    node_group_name = "managed-ondemand-gpu"
    instance_types  = [var.node_instance_type_gpu]
    min_size        = 3
    desired_size    = 3
    max_size        = 5
    ami_type        = "AL2_x86_64_GPU"
    subnet_ids      = var.src_vpc_private_subnets
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

data "aws_route53_zone" "platform" {
  count = var.use_alb_redirect ? 1 : 0
  name = var.aws_route53_subdomain_zone_name
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

  vpc_id             = var.src_vpc_id
  private_subnet_ids = var.src_vpc_private_subnets

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

  enable_aws_cloudwatch_metrics = var.use_cloudwatch
  enable_aws_for_fluentbit = var.use_fluentbit
  aws_for_fluentbit_create_cw_log_group = false
  aws_for_fluentbit_cw_log_group_name = var.cw_log_group_name

  enable_nvidia_device_plugin = local.using_gpu
  enable_velero = var.using_velero
  velero_backup_s3_bucket = var.using_velero ? var.src_velero_bucket_name: ""
  velero_helm_config = {
    version     = "3.0.0",
    set = [
      {
        name = "deployNodeAgent",
        value = "true"
      }
    ]
  }

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
  use_fsx = var.use_fsx

  vpc_id     = var.src_vpc_id
  cidr_block = var.src_vpc_cidr
  efs_fs_id = var.src_efs_fs_id
  private_subnet_ids = var.src_vpc_private_subnets
  public_subnet_ids = var.src_vpc_public_subnets 
  security_group_id = module.eks_blueprints.cluster_primary_security_group_id
  db_security_group_id = var.src_cluster_sg_id
  mlmdb_name = var.mlmdb_name

  minio_service_region = var.minio_service_region

  s3_secret_name = var.src_s3_secret_name
  s3_bucket_name = var.src_s3_bucket_name
  rds_secret_name = var.src_rds_secret_name
  rds_endpoint = var.src_rds_endpoint

  # cognito
  use_cognito = var.use_cognito
  stage = var.stage
  user_pool_id = var.user_pool_id
  aws_route53_subdomain_zone_name = var.aws_route53_subdomain_zone_name
  load_balancer_scheme = var.load_balancer_scheme
  certificate_arn = var.certificate_arn
  cognito_user_pool_arn = var.cognito_user_pool_arn
  cognito_user_pool_domain = var.cognito_user_pool_domain


}

module "alb_redirection" {
  count = var.use_alb_redirect ? 1 : 0
  source = "../../../iaac/terraform/aws-infra/alb-redirect"

  vpc_id = var.src_vpc_id
  subnet_ids = var.src_vpc_public_subnets
  certificate_arn = var.certificate_arn
  redirect_to = "kubeflow${var.src_stage}.${var.aws_route53_subdomain_zone_name}"
  redirect_from = "${var.redirect_alias}.${var.aws_route53_subdomain_zone_name}"
  zone_id         = data.aws_route53_zone.platform[0].zone_id
}