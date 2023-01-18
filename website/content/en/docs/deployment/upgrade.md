+++
title = "Upgrade"
description = "Upgrading Kubeflow"
weight = 90
+++

Kubeflow does not natively offer an upgrade process. An in-place upgrade often works, but we recommend a blue/green upgrade process that provides a fail-back capability. We will leverage integration with AWS storage and database services to let us deploy a new EKS cluster with Kubeflow and connect it to the external data stores. We will also use an open-source tool to copy certain resources from the production EKS cluster to the new one, and use AWS Backup to snapshot the state of our external data stores.

At this time, the upgrade process is only tested using these two configurations:

* RDS and S3 with EFS and the Terraform deployment option
* Cognito, RDS, and S3 with EFS and the Terraform deployment option

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

On the EC2 or Cloud9 instance you are using, [install the Velero CLI](https://velero.io/docs/v1.10/basic-install/#install-the-cli). Make sure you are using version 1.10 or later.

### Configure Velero in production cluster

Make sure that you enabled Velero when deploying the production cluster. If not, enable it and redeploy the Terraform stack.

If your production deployment used a version of Kubeflow on AWS that did not include support for deploying Velero with Terraform, see the note about [installing Velero manually)({{< ref "#Installing Velero manually" >}})..

### Switch to new version of Kubeflow release

We will create a new clone of the GitHub repository for the new deployment. 

#### Optional: Deploy new Cloud9 or EC2 instance

Using a new Cloud9 or EC2 instance lets you maintain clear separation between deployments. If you want to do this, follow the steps in [Create Ubuntu environment]({{< ref "./prerequisites/#Create Ubuntu environment" >}}). 

#### Complete other prerequisites

Follow the steps in [Clone repository]({{< ref "./prerequisites/#Clone repository" >}}). Be sure to use the newer version of Kubeflow in these steps.

#### Optional: Deploy other prerequisites on new Cloud9 or EC2 instance

If you set up a new Cloud9 or EC2 instance, follow the steps in [Install necessary tools]({{< ref "./prerequisites/#Install necessary tools" >}}) and [Configure AWS Credentials and Region for Deployment]({{< ref "./prerequisites/#Configure AWS Credentials and Region for Deployment" >}}). Then [install the Velero CLI](https://velero.io/docs/v1.10/basic-install/#install-the-cli).

### Deploy backup EKS cluster

Next, we will create a new `tfvars` file with the name of the backup cluster and necessary information about the original deployment.

#### Generate variable file for new cluster

Execute this step on the Cloud9 or EC2 instance you are using for the new cluster. 

In the new clone of the GitHub repository, go to the `upgrade` directory.

```bash
cd $REPO_ROOT/deployments/upgrade/terraform
```

Copy the `sample.auto.tfvars` file from the production deployment into this directory. If you did not use Terraform to create the production deployment, create the file `sample.auto.tfvars` with these entries:

```bash
cluster_name="<cluster name>"
cluster_region="<cluster region>"
generate_db_password="true"
use_rds="true"
use_s3="true"
```

Edit the `sample.auto.tfvars` file and make these changes:

* Set the name of the backup EKS cluster in the `cluster_name` variable. 
* If you want to use a different version of EKS, set the `eks_version` variable.

The other variables can stay the same.

#### Get information about production cluster

Execute this step on the Cloud9 or EC2 instance you are using for the production cluster. 

Next, we need to add information about the production deployment to the new `tfvars` file. 

If you installed with kustomize, make sure you have set all the proper environment variables as you did when you installed the cluster. If you do not have these environment variables set because you installed with Terraform, you can obtain the values by searching for the variables `s3_secret`, `rds_secret`, and `artifact_store` in `terraform.tfstate`.

Go to the directory `deployments/upgrade-baseline` and run:

```bash
python get_cluster_variables.py \
    --region $CLUSTER_REGION \
    --cluster $CLUSTER_NAME \
    --bucket $S3_BUCKET \
    --rds_secret_name $RDS_SECRET_NAME \
    --s3_secret_name $S3_SECRET_NAME \
    --efs_name $CLAIM_NAME
```

Add new lines to the output file `upgrade.tfvars` with the name of the S3 bucket you are using for Velero and a deployment stage name:

```bash
src_velero_bucket_name = "<bucket>"
stage = "candidate"
```

If you are using Cognito, also add lines for the user pool and certificate information:

```bash
user_pool_id = ""
cognito_user_pool_arn = ""
cognito_user_pool_domain = ""
certificate_arn = ""
```

Copy the output file `upgrade.tfvars` to the EC2 or Cloud9 instance you are using for the new deployment.

In the directory for the new deployment, copy the `upgrade.tfvars` file into the directory, then run:

```bash
cat upgrade.tfvars >> sample.auto.tfvars
```

#### Deploy new cluster

Execute this step on the Cloud9 or EC2 instance you are using for the new cluster. 

Now deploy the backup cluster.

```bash
make deploy
```

### Execute an on-demand backup

Execute this step on the Cloud9 or EC2 instance you are using for the production cluster. 

The deployment process creates an AWS Backup vault and associated IAM role to use. Go to the production deployment directory and run this script:

```bash
cd $REPO_ROOT/deployments/rds-s3/terraform
../../../tests/e2e/utils/snapshot-state.sh
```

The script will wait for the jobs to complete. Confirm that all backups completed successfully.

If the version of Kubeflow for AWS that you used to create your production cluster did not create a backup vault, you can create one manually following the [instructions in the documentation](https://docs.aws.amazon.com/aws-backup/latest/devguide/creating-a-vault.html). 

If you did not deploy your cluster with Terraform, you can manually enter the variables in the `snapshot-state.sh` script:

```bash
VAULT=<name of backup vault>
ROLE_ARN=<ARN of backup role>
EFS_ARN=<ARN of EFS file system>
S3_ARN=<ARN of artifact bucket>
RDS_ARN=<ARN of database instance>
```

### Execute the upgrade

#### Mark the persistent volumes you want to back up

Execute this section on the Cloud9 or EC2 instance you are using for the production cluster.

Persistent volumes for notebooks are cluster-level resources, although the volume claims are in the user-level namespaces. However, the Velero custom resources that represent volume backups live in the `velero` namespace. We do not want to restore the entire `velero` namespace later, as that would include volumes from Velero pods.

So, we will annotate the volumes we want to back up. For each persistent volume, run this command:

```bash
kubectl -n <namespace> annotate pod/<pod name> backup.velero.io/backup-volumes=<volume name>
```

For example, if the user `user@example.com` has a notebook called `mynb`, you would run:

```bash
kubectl -n kubeflow-user-example-com annotate pod/mynb-0 backup.velero.io/backup-volumes=mynb-volume
```

#### Back up resources from production cluster

Execute this section on the Cloud9 or EC2 instance you are using for the production cluster.

Execute a velero backup. We need to include at least the following resources:

* The `velero` namespace, as it contains information about persistent volume backups
* All user namespaces
* Cluster-scoped resources like profiles

For the sake of convenience, you can back up the entire cluster and selectively restore the correct resources later on.

```bash
velero backup create test1 --wait --default-volumes-to-fs-backup=false
```

Wait until the backup is completed.

```bash
velero backup describe test1 # check for the Phase output
```

#### Configure new cluster for knative serving

If you use knative serving, you need to set up the new cluster for model serving.

First, edit the config map `config-domain` in the `knative-serving` namespace. Set the default domain to the subdomain you are using for Kubeflow.

Next, follow the steps in the [Create ingress](https://awslabs.github.io/kubeflow-manifests/docs/component-guides/kserve/tutorial/#create-ingress) section to configure the ingress controller. You can reuse the same certificate you used for the production cluster.

Finally, follow the steps in [Run a sample inference service](https://awslabs.github.io/kubeflow-manifests/docs/component-guides/kserve/tutorial/#run-a-sample-inferenceservice) to add an authorization policy.

#### Restore resources into new cluster.

Execute this section on the Cloud9 or EC2 instance you are using for the new cluster.

Restore the backup. You must include all user namespaces and the `velero` namespace.

```bash
velero restore create --from-backup test1 \
    --include-namespaces kubeflow-user-example-com,velero \
    --include-resources persistentvolume,persistentvolumeclaim,namespace,workflow,image,notebook,profile,inferenceservice,configmap,podvolumebackup \
    --include-cluster-resources \
    --wait
```

Wait until the restore completes.

If you have serving endpoints deployed, you will need to update the CNAME record that you created in [Add DNS records](https://awslabs.github.io/kubeflow-manifests/docs/component-guides/kserve/tutorial/#add-dns-records).

## Notes

### Installing Velero manually

If you deployed your production cluster without Velero, you will need to install it. We recommend using the [EKS Terraform Blueprints](https://github.com/aws-ia/terraform-aws-eks-blueprints). 

Clone the latest copy of the GitHub repository on the EC2 or Cloud9 instance you are using for the production cluster. If you installed with kustomize, make sure you have set all the proper environment variables as you did when you installed the cluster. If you do not have these environment variables set because you installed with Terraform, you can obtain the values by searching for the variables `s3_secret`, `rds_secret`, and `artifact_store` in `terraform.tfstate`.

Go to the directory `deployments/upgrade-baseline` and run this script to create a Terraform variables file:

```bash
python get_cluster_variables.py \
    --region $CLUSTER_REGION \
    --cluster $CLUSTER_NAME \
    --bucket $S3_BUCKET \
    --rds_secret_name $RDS_SECRET_NAME \
    --s3_secret_name $S3_SECRET_NAME \
    --efs_name $CLAIM_NAME
```

If you do not have Terraform installed, follow the normal [installation process](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli). You will need Terraform < 1.3.0.

Now deploy the stack.

```bash
cd terraform
terraform init
terraform apply -auto-approve
```

### Multiple upgrades

The original production cluster deployment creates the underlying AWS storage resources in S3, RDS, and EFS. Future deployments read information about those resources from the Terraform state of the original deployment. You can continue to follow the upgrade process in the future to deploy new versions of Kubeflow and/or EKS. Just remember to use the correct kubectl contexts when executing the Velero backups.

### Deleting old clusters

You can remove older deployments when satisfied with testing. Specifically, you can delete the EKS cluster used for an older deployment, as the upgrade process only needs information about the VPC, RDS, EFS, S3, Cognito, Route 53, and any certificates created. You should retain the backup vault as we reuse that. We also use the original EKS cluster security group for the RDS database as well, so you will need to retain that security group.

If you deployed with Cognito, you will need to make sure that you adjust the `A` record for the subdomain apex to point to the ingress controller for the new cluster.

### Resources in scope for Velero backup

While Velero can back up an entire EKS cluster, we only need a few resource types.

* persistentvolume (global)
* persistentvolumeclaim (user profile namespace)
* namespace (only for user profile namespaces)
* workflow (user profile namespace)
* image (user profile namespace)
* notebook (user profile namespace)
* profile (global)
* inferenceservice (user profile namespace)
* configmap (user profile namespace)
* podvolumebackup (velero namespace)