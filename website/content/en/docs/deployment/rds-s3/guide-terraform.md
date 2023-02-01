+++
title = "Terraform Deployment Guide"
description = "Deploy Kubeflow with RDS and S3 using Terraform"
weight = 30
+++

> Note: Terraform deployment options are still in preview.

## Background

This guide will walk you through using Terraform to:
- Create a VPC
- Create an EKS cluster
- Create a S3 bucket
- Create an RDS DB instance
- Create an EFS or FSx file system
- Configure CloudWatch for metrics and logs
- Deploy Kubeflow with RDS as a KFP and Katib persistence layer, S3 as an artifact store, EFS for persistent volumes, and Velero for supporting backups and upgrades

Terraform documentation can be found [here](https://www.terraform.io/docs).

## Prerequisites

Be sure that you have satisfied the [installation prerequisites]({{< ref "../prerequisites.md" >}}) before working through this guide.

Specifially, you must:
- [Create a Ubuntu environment]({{< ref "../prerequisites/#create-ubuntu-environment" >}})
- [Clone the repository]({{< ref "../prerequisites/#clone-repository" >}})
- [Install the necessary tools]({{< ref "../prerequisites/#install-necessary-tools" >}})


Additionally, ensure you are in the `REPO_ROOT/deployments/rds-s3/terraform` folder.

If you are in repository's root folder, run:
```sh
cd deployments/rds-s3/terraform
pwd
```

## Deployment Steps

### Configure

1. Create an IAM user to use with the Minio Client

    [Create an IAM user](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_users_create.html#id_users_create_cliwpsapi) with permissions to get bucket locations and allow read and write access to objects in an S3 bucket where you want to store the Kubeflow artifacts. Take note of the AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY of the IAM user that you created to use in the following step, which will be referenced as `TF_VAR_minio_aws_access_key_id` and `TF_VAR_minio_aws_secret_access_key` respectively.

1. Define the following environment variables:

    ```sh
    # Region to create the cluster in
    export CLUSTER_REGION=
    # Name of the cluster to create
    export CLUSTER_NAME=
    # AWS access key id of the static credentials used to authenticate the Minio Client
    export TF_VAR_minio_aws_access_key_id=
    # AWS secret access key of the static credentials used to authenticate the Minio Client
    export TF_VAR_minio_aws_secret_access_key=
    # true/false flag to configure and deploy with RDS
    export USE_RDS="true"
    # true/false flag to configure and deploy with S3
    export USE_S3="true"
    # true/false flag to configure and deploy with EFS
    export USE_EFS="true"
    # true/false flag to configure and deploy with FSx
    export USE_FSX="true"
    # true/false flag to configure and deploy with Velero
    export USE_VELERO="true"
    # true/false flag to configure and deploy with CloudWatch
    export USE_CLOUDWATCH="true"
    # true/false flag to configure and deploy with FluentBit
    export USE_FLUENTBIT="true"
    # name of CloudWatch log group to use
    export CW_LOG_GROUP="kubeflow"
    # use Prometheus
    export USE_PROMETHEUS="false"
    ```

    We strongly suggest enabling both EFS and Velero, as that will make for an easier [upgrade]({{< ref "../upgrade" >}}). path.

1. Save the variables to a `.tfvars` file:

    ```sh
    cat <<EOF > sample.auto.tfvars
    cluster_name="${CLUSTER_NAME}"
    cluster_region="${CLUSTER_REGION}"
    generate_db_password="true"
    use_rds="${USE_RDS}"
    use_s3="${USE_S3}"
    use_efs="${USE_EFS}"
    use_fsx="${USE_FSX}"
    using_velero = "${USE_VELERO}"
    use_cloudwatch="${USE_CLOUDWATCH}"
    use_fluentbit="${USE_FLUENTBIT}"
    cw_log_group_name="${CW_LOG_GROUP}"
    use_prometheus="${USE_PROMETHEUS}"

    # The below values are set to make cleanup easier but are not recommended for production
    deletion_protection="false"
    secret_recovery_window_in_days="0"
    force_destroy_s3_bucket="true"
    EOF
    ```

    If you want to use a specific version of EKS, add the `eks_version` variable.

### (Optional) Configure Culling for Notebooks
Enable culling for notebooks by following the [instructions]({{< ref "/docs/deployment/configure-notebook-culling.md#" >}}) in configure culling for notebooks guide.

### All Configurations

A full list of inputs for the terraform stack can be found [here](https://github.com/awslabs/kubeflow-manifests/blob/main/deployments/rds-s3/terraform/variables.tf).

### Preview

View a preview of the configuration you are about apply:
```sh
terraform init && terraform plan
```

### Apply

Run the following command:
```sh
make deploy
```

## Connect to your Kubeflow dashboard

For information on connecting to your Kubeflow dashboard depending on your deployment environment, see [Port-forward (Terraform deployment)]({{< ref "../connect-kubeflow-dashboard/#port-forward-terraform-deployment" >}}). Then, [log into the Kubeflow UI]({{< ref "../connect-kubeflow-dashboard/#log-into-the-kubeflow-ui" >}}).

## Check EFS configuration

If you are using EFS, check the additional information starting in [Section 3 of the EFS add-on guide]({{< ref "../../add-ons/storage/efs/guide/#3.0 Using EFS storage in Kubeflow" >}}).

## Check FSx configuration

If you are using FSx, check the additional information starting in [Section 3 of the FSx add-on guide]({{< ref "../../storage/fsx-for-lustre/guide/#30-using-fsx-storage-in-kubeflow" >}}).

## Cleanup

Uninstall Kubeflow on AWS with a single command. 
```sh
make delete
```
