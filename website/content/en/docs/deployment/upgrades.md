+++
title = "Upgrading Kubeflow"
description = "Use blue/green deployment to safely upgrade Kubeflow or EKS"
weight = 90
+++

The Kubeflow project does not provide a documented upgrade path between versions of Kubeflow. In most cases an in-place upgrade is possible, but for production deployments we recommend following a blue/green upgrade procedure. That lets you quickly fail back to the older version of Kubeflow if you encounter any upgrade problems.

Similarly, if you are upgrading your EKS cluster itself, you may want to preserve the older cluster rather than doing an in-place upgrade. While EKS provides managed kubernetes upgrades, by doing a blue/green upgrade you can fail back if the new kubernetes version is incompatible with the Kubeflow version.

In order to perform a blue/green upgrade, you should use RDS and S3 for the database and artifact storage, and EFS for volume storage. That decouples these storage layers from the kubernetes cluster and the Kubeflow components running in the cluster. You can also choose to use a clone of the storage layers for the new deployment, in case temporarily using a new version of Kubeflow introduces any incompatible changes in the database.

## High level scenarios and steps

### Recommended: Cloning the storage layers

Cloning the storage layers to use for a new deployment of Kubeflow provides an easier fail-back path. Cloning the database requires two steps:

* [Create a snapshot of the database](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_CreateSnapshot.html). Creating the snapshot does not require any down time, as RDS takes the snapshot from the standby instance in a multi-AZ configuration.
* [Restore from snapshot](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_RestoreFromSnapshot.html) into a new database.

Cloning the S3 bucket is also easy. While the [s3 sync](https://docs.aws.amazon.com/cli/latest/reference/s3/sync.html) command is how you'd clone a bucket manually, for automated purposes we use AWS DataSync. 

Similarly, we use DataSync to clone the EFS volume.

### Upgrading Kubeflow, Kubernetes, or both

Whether we choose to upgrade Kubeflow, Kubernetes, or both, the high-level steps are:

* Deploy a new EKS cluster using the target kubernetes version and similar configuration to the production cluster.
* Clone the database, EFS volume, and S3 bucket.
* Deploy the target version of Kubeflow to the new EKS cluster pointing to the cloned copy of the database, EFS volume, and S3 bucket.
* Run any tests necessary.
* If you ran the tests during a maintenance window, redirect production traffic to the new cluster. Or, if changes were made to the storage layers while you were testing, repeat this procedure during a maintenance window so that the cloned storage layers are up to date.
* If you encounter problems, you can fail back to the original cluster.

We recommend performing these steps during a maintenance window so there is no inconsistency between the data in the original storage layers and the cloned storage layers.

## Detailed steps

### Step 1: Prerequisites

As we're essentially doing a new Kubeflow installation, start with the [Prerequisites]({{< ref "/docs/deployment/prerequisites.md" >}}). While you can reuse the same EC2 or Cloud9 instance, be sure to clone the repository into a unique directory using the desired Kubeflow version. For example:

```bash
export KUBEFLOW_RELEASE_VERSION=v1.6.1
export AWS_RELEASE_VERSION=v1.6.1-aws-b1.0.0
git clone https://github.com/awslabs/kubeflow-manifests.git kubeflow-manifests-v161 && cd kubeflow-manifests-v161
git checkout ${AWS_RELEASE_VERSION}
git clone --branch ${KUBEFLOW_RELEASE_VERSION} https://github.com/kubeflow/manifests.git upstream

```

### Step 2: Deploy a new EKS cluster

Similar to the process in [Create an EKS Cluster]({{< ref "/docs/deployment/create-eks-cluster.md" >}}), we'll use `eksctl` to create a new cluster. Review the more detailed information in [Create an EKS Cluster]({{< ref "/docs/deployment/create-eks-cluster.md" >}}) before proceeding.

In the code below, note that you need to provide a new cluster name and specify a cluster version. If you are upgrading EKS, specify the new version you want to use. If you are only upgrading Kubeflow, use the same version as the production EKS cluster. 

```bash
export CLUSTER_NAME=my_new_eks_cluster_name
export CLUSTER_VERSION=1.24
```

Run the following command to create an EKS cluster:
```bash
eksctl create cluster \
--name ${CLUSTER_NAME} \
--version ${CLUSTER_VERSION} \
--region ${CLUSTER_REGION} \
--nodegroup-name linux-nodes \
--node-type m5.xlarge \
--nodes 5 \
--nodes-min 5 \
--nodes-max 10 \
--managed \
--with-oidc
```

If you have performed any other customizations on the production cluster, be sure to perform those on the new cluster as well. We cover one common case (EFS add-on) below.

#### EFS

If you have deployed EFS on the production EKS cluster to use for Kubeflow storage, we will deploy it on the new cluster in two steps. In the first step here, we will provision a new EFS volume and register it as a storage class. We will clone the contents of the original EFS volume and configure it for Kubeflow later on.

First, make sure you're in the root directory of the new `kubeflow-manifests` working copy, and configure a few environment variables.

```bash
export REPO_ROOT=$(pwd)
export PVC_NAMESPACE=kubeflow-user-example-com # set to proper namespace
export CLAIM_NAME=efsclaim # use the same claim name as the previous installation
export VOLUME_NAME=efsvol # provide your own volume name
export SECURITY_GROUP_TO_CREATE=$VOLUME_NAME
```

Now run the EFS setup script.

```bash
cd $REPO_ROOT/tests/e2e

python utils/auto-efs-setup.py \
    --region $CLUSTER_REGION \
    --cluster $CLUSTER_NAME \
    --efs_file_system_name $VOLUME_NAME \
    --efs_security_group_name $SECURITY_GROUP_TO_CREATE

```

### Step 3: Automated installation with cloned storage

Now we can follow the steps in the [automated RDS and S3 manifest installation process]({{< ref "/docs/deployment/rds-s3/guide.md" >}}) with a few minor changes. 

First, make sure you're in the root directory of the new `kubeflow-manifests` working copy.

```bash
export REPO_ROOT=$(pwd)
```

Now define the necessary variables, including variables that let the script know the names of the original S3 bucket and database

```bash
export CLUSTER_REGION=<>
export CLUSTER_NAME=<>
export S3_BUCKET=<>
export DB_INSTANCE_NAME=<>
export DB_SUBNET_GROUP_NAME=<>
export MINIO_AWS_ACCESS_KEY_ID=<>
export MINIO_AWS_SECRET_ACCESS_KEY=<>
export RDS_SECRET_NAME=<>
export S3_SECRET_NAME=<>
export PRIOR_BUCKET=<name of bucket used in previous installation>
export PRIOR_DB_INSTANCE_NAME=<name of database used in previous installation>
export PRIOR_RDS_SECRET_NAME=<name of database secret used in previous installation>
export DATASYNC_ROLE_NAME=<name of IAM role to make for DataSync>
```

If using EFS, also provide the name of the previous volume.

```bash
export PRIOR_VOLUME_NAME=oldvolume # use name of EFS volume for previous installation
export PRIOR_EFS_SECURITY_GROUP=oldsg # use name of EFS security group for previous installation
export PRIOR_CLUSTER_NAME=oldcluster # use name of previous installation's EKS cluster
```

Now execute the automated script.

```bash
cd tests/e2e
PYTHONPATH=.. python utils/rds-s3/auto-rds-s3-setup.py \
    --region $CLUSTER_REGION \
    --cluster $CLUSTER_NAME \
    --bucket $S3_BUCKET \
    --s3_aws_access_key_id $MINIO_AWS_ACCESS_KEY_ID \
    --s3_aws_secret_access_key $MINIO_AWS_SECRET_ACCESS_KEY \
    --db_instance_name $DB_INSTANCE_NAME \
    --s3_secret_name $S3_SECRET_NAME \
    --rds_secret_name $RDS_SECRET_NAME \
    --db_subnet_group_name $DB_SUBNET_GROUP_NAME \
    --prior_bucket $PRIOR_BUCKET \
    --prior_database $PRIOR_DB_INSTANCE_NAME \
    --prior_rds_secret_name $PRIOR_RDS_SECRET_NAME \
    --datasync_role_name $DATASYNC_ROLE_NAME \
    --upgrade
```

If using EFS, also provide these arguments:

```bash
    --efs_volume $VOLUME_NAME \
    --prior_efs_volume $PRIOR_VOLUME_NAME \
    --efs_security_group_name $SECURITY_GROUP_TO_CREATE \
    --prior_efs_security_group_name $PRIOR_EFS_SECURITY_GROUP \
    --prior_cluster $PRIOR_CLUSTER_NAME \
    --upgrade_efs
```

Once complete, you can follow the rest of the normal process starting with Step `3.0 Build Manifests and install Kubeflow`.

#### Final EFS configuration

Re-run the EFS setup script to reinstall the storage class, which may have been overridden during the other setup steps.

```bash
cd $REPO_ROOT/tests/e2e
python utils/auto-efs-setup.py \
    --region $CLUSTER_REGION \
    --cluster $CLUSTER_NAME \
    --efs_file_system_name $VOLUME_NAME \
    --efs_security_group_name $SECURITY_GROUP_TO_CREATE
```

If using EFS, set up the PVC.

```bash
export GITHUB_STORAGE_DIR="$REPO_ROOT/deployments/add-ons/storage/"
yq e '.metadata.namespace = env(PVC_NAMESPACE)' -i $GITHUB_STORAGE_DIR/efs/dynamic-provisioning/pvc.yaml
yq e '.metadata.name = env(CLAIM_NAME)' -i $GITHUB_STORAGE_DIR/efs/dynamic-provisioning/pvc.yaml

kubectl apply -f $GITHUB_STORAGE_DIR/efs/dynamic-provisioning/pvc.yaml
```

Optionally, configure EFS as the default storage class.

```bash
kubectl patch storageclass gp2 -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
kubectl patch storageclass efs-sc -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

Review the [EFS Add-on Guide]({{< ref "/docs/add-ons/storage/efs/guide.md" >}}) if you have used any of the EFS add-on advanced options.