+++
title = "Upgrade"
description = "Upgrading Kubeflow"
weight = 90
+++

Kubeflow does not natively offer an upgrade process. An in-place upgrade often works, but we recommend a blue/green upgrade process that provides a fail-back capability. We will leverage integration with AWS storage and database services to let us deploy a new EKS cluster with Kubeflow and connect it to the external data stores. We will also use an open-source tool to copy certain resources from the production EKS cluster to the new one, and use AWS Backup to snapshot the state of our external data stores.

At this time, the upgrade process is only tested when using the RDS and S3 configuration with EFS and the Terraform deployment option.

## Upgrade methodology

Using a blue/green pattern lets us deploy a new EKS cluster with a new version of kubernetes, a new version of Kubeflow, or both. We do need to transfer all relevant state from the old deployment to the new one. Once the new deployment is running, you can test it and then switch traffic if the deployment was successful. We recommend performing the upgrade and associated testing during a maintenance window, as both EKS clusters will be connected to the same underlying data stores.

There are several data stores to consider.

### AWS data stores

The recommended configuration uses S3 for artifact storage, RDS as the database, EFS for volume storage, and Cognito as an identity provider. We will use AWS Backup to take a snapshot of S3, RDS, and EFS, so that we can restore them to a known-good state if something goes wrong with the new deployment.

We will not back up Cognito as normally you don't need to make changes to identities during an upgrade test cycle.

### Kubernetes resources

During Kubeflow use, users create resources like notebook instances and model serving endpoints. These exist in the user-specific namespaces. We will use [Velero](https://velero.io/), an open-source tool, to backup resources from these namespaces and recover them into the new cluster.

## Upgrade steps

Now let's walk through a detailed example of a blue/green upgrade.

### Declare a maintenance window

Some Kubeflow resources, like pipeline runs, take some time to persist into the database. Wait one hour after pausing user activity before starting the upgrade.

### Install Velero CLI

On the EC2 or Cloud9 instance you are using, [install the Velero CLI](https://velero.io/docs/v1.10/basic-install/#install-the-cli).

### Configure Velero in production cluster

Make sure that you enabled Velero when deploying the production cluster. If not, enable it and redeploy the Terraform stack.

If your production deployment used a version of Kubeflow on AWS that did not include support for deploying Velero with Terraform, see the note about [installing Velero manually)({{< ref "#Installing Velero manually" >}})..

### Switch to new version of Kubeflow release

If you want to use a newer version of Kubeflow, perform these steps.

```bash
cd $REPO_ROOT
export KUBEFLOW_RELEASE_VERSION=v1.6.1 # set to new version
export AWS_RELEASE_VERSION=v1.6.1-aws-b1.0.0 # set to new version
git checkout ${AWS_RELEASE_VERSION}
rm -rf upstream
git clone --branch ${KUBEFLOW_RELEASE_VERSION} https://github.com/kubeflow/manifests.git upstream
```

### Deploy backup EKS cluster

Next, we will create a new `tfvars` file with the name of the backup cluster.

```bash
cd $REPO_ROOT/deployments/upgrade/terraform
cp ../../rds-s3/terraform/sample.auto.tfvars .
```

Edit the `sample.auto.tfvars` file and make these changes:

* Set the name of the backup EKS cluster in the `cluster_name` variable. 
* If you want to use a different version of EKS, set the `eks_version` variable.

The other variables can stay the same.

Now deploy the backup cluster.

```bash
make deploy
```

### Execute an on-demand backup

The deployment process creates an AWS Backup vault and associated IAM role to use. On your EC2 or Cloud9 instance, run this command:

```bash
cd $REPO_ROOT/deployments/rds-s3/terraform
../../../tests/e2e/utils/snapshot-state.sh
```

The script will wait for the jobs to complete. Confirm that all backups completed successfully.

If the version of Kubeflow for AWS that you used to create your production cluster did not create a backup vault, you can create one manually following the [instructions in the documentation](https://docs.aws.amazon.com/aws-backup/latest/devguide/creating-a-vault.html).

### Execute the upgrade

Switch kubectl to use the context for the production cluster.

```bash
kubectl config use-context <production context>
```

Now execute a velero backup. We will include all namespaces as we need the user profiles and related config maps, which are not scoped to the user namespaces.

```bash
velero backup create test1 --wait --default-volumes-to-fs-backup
```

Wait until the backup is completed.

```bash
velero backup describe test1 # check for the Phase output
```

Now switch kubectl to use the context for the new cluster.

```bash
kubectl config use-context <restore context>
```

Restore the backup. In this step, first restore all user profiles, then the associated namespaces.

```bash
velero restore create --from-backup test1 --include-resources profiles,configmaps --wait
velero restore create --from-backup test1 --include-namespaces kubeflow-user-example-com --wait
```

Wait until the backup completes.

```bash
velero restore describe # check for the Phase output
```

## Notes

### Installing Velero manually

If you deployed your production cluster without Velero, you will need to install it. We recommend using the [EKS Terraform Blueprints](https://github.com/aws-ia/terraform-aws-eks-blueprints). 

In the file `deployments/rds-s3/terraform/main.tf`, add an S3 bucket resource to use for Velero.

```bash
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

```

Next in the same file find the module named `eks_blueprints_kubernetes_addons`. Add the following snippet:

```bash
module "eks_blueprints_kubernetes_addons" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints//modules/kubernetes-addons?ref=v4.12.1"

  ...

  enable_velero = true
  velero_backup_s3_bucket = aws_s3_bucket.velero_store.id
  velero_helm_config = {
    version     = "3.0.0",
    set = [
      {
        name = "deployNodeAgent",
        value = "true"
      },
      {
        name = "configuration.defaultVolumesToFsBackup",
        value = "true"
      },
      {
        name = "snapshotsEnabled",
        value = "false"
      }
    ]
  }

  ...
}
```

Now redeploy the stack.

### Multiple upgrades

The original production cluster deployment creates the underlying AWS storage resources in S3, RDS, and EFS. Future deployments read information about those resources from the Terraform state of the original deployment. You can continue to follow the upgrade process in the future to deploy new versions of Kubeflow and/or EKS. Just remember to use the correct kubectl contexts when executing the Velero backups.

### Deleting old clusters

You can remove older deployments when satisfied with testing. Specifically, you can delete the EKS cluster used for an older deployment, as the upgrade process only needs information about the VPC, RDS, EFS, and S3. You should retain the backup vault as we reuse that. We also use the original EKS cluster security group for the RDS database as well, so you will need to retain that security group.