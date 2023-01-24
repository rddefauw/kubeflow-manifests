provider "aws" {
  region = var.region
}

provider "kubernetes" {
  host                   = var.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(var.eks_cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", var.eks_cluster_id]
  }
}

provider "helm" {
  kubernetes {
    host                   = var.eks_cluster_endpoint
    cluster_ca_certificate = base64decode(var.eks_cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      # This requires the awscli to be installed locally where Terraform is executed
      args = ["eks", "get-token", "--cluster-name", var.eks_cluster_id]
    }
  }
}

resource "aws_s3_bucket" "velero_store" {
  bucket_prefix = "kf-velero-"
  force_destroy = var.force_destroy_bucket
}

resource "aws_s3_bucket_versioning" "velero_store_versioning" {
  bucket = aws_s3_bucket.velero_store.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifact_store_encryption" {
  bucket = aws_s3_bucket.velero_store.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "velero_store_block_access" {
  bucket = aws_s3_bucket.velero_store.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

module "eks_blueprints_kubernetes_addons" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints//modules/kubernetes-addons?ref=v4.12.1"

  eks_cluster_id       = var.eks_cluster_id
  eks_cluster_endpoint = var.eks_cluster_endpoint
  eks_oidc_provider    = var.oidc_provider
  eks_cluster_version  = var.eks_cluster_version

  enable_velero = true
  velero_backup_s3_bucket = aws_s3_bucket.velero_store.id
  velero_helm_config = {
    version     = "3.0.0",
    set = [
      {
        name = "deployNodeAgent",
        value = "true"
      }
    ]
  }

}