+++
title = "Upgrading Kubeflow"
description = "Use blue/green deployment to safely upgrade Kubeflow or EKS"
weight = 90
+++

The Kubeflow project does not provide a documented upgrade path between versions of Kubeflow. In most cases an in-place upgrade is possible, but for production deployments we recommend following a blue/green upgrade procedure. That lets you quickly fail back to the older version of Kubeflow if you encounter any upgrade problems.

Similarly, if you are upgrading your EKS cluster itself, you may want to preserve the older cluster rather than doing an in-place upgrade. While EKS provides managed kubernetes upgrades, by doing a blue/green upgrade you can fail back if the new kubernetes version is incompatible with the Kubeflow version.

In order to perform a blue/green upgrade, you should use RDS and S3 for the database and artifact storage. That decouples these storage layers from the kubernetes cluster and the Kubeflow components running in the cluster. You can also choose to use a clone of the storage layers for the new deployment, in case temporarily using a new version of Kubeflow introduces any incompatible changes in the database.

## High level scenarios and steps

### Optional: Cloning the storage layers

Cloning the storage layers to use for a new deployment of Kubeflow provides an easier fail-back path. Cloning the database requires two steps:

* [Create a snapshot of the database](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_CreateSnapshot.html). Creating the snapshot does not require any down time, as RDS takes the snapshot from the standby instance in a multi-AZ configuration.
* [Restore from snapshot](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_RestoreFromSnapshot.html) into a new database using the same configuration options such as VPC and security groups.

Cloning the S3 bucket is also easy using the [s3 sync](https://docs.aws.amazon.com/cli/latest/reference/s3/sync.html) command. For buckets with large numbers of objects, setting the [max_concurrent_requests](https://docs.aws.amazon.com/cli/latest/topic/s3-config.html#max-concurrent-requests) and [max_queue_size](https://docs.aws.amazon.com/cli/latest/topic/s3-config.html#max-queue-size) options will give better performance.

### Upgrading Kubeflow

Let's start with the scenario where we want to upgrade Kubeflow but use the same version of kubernetes. The high level steps are:

* Deploy a new EKS cluster using the same kubernetes version and configuration.
* Clone the database and S3 bucket.
* Deploy the new version of Kubeflow to the new EKS cluster pointing to the cloned copy of the database and S3 bucket.
* Run any tests necessary.
* If you ran the tests during a maintenance window, redirect production traffic to the new cluster. Or, if changes were made to the production database and S3 bucket while you were testing, repeat this procedure during a maintenance window so that the cloned database and S3 bucket are up to date.
* If you encounter problems, you can fail back to the original cluster.

### Upgrading kubernetes

Next, let's consider the case where you want to upgrade the EKS cluster to a newer version of kubernetes. EKS provides a managed in-place [upgrade path](https://docs.aws.amazon.com/eks/latest/userguide/update-cluster.html) for EKS clusters and managed node groups. However, you should test your Kubeflow deployment against the newer version of kubernetes before upgrading a production cluster. Alternatively, you can simply deploy a new EKS cluster using the new kubernetes version and test Kubeflow on the new cluster. 

The high level steps are:

* Deploy a new EKS cluster using the new kubernetes version
* Clone the database and S3 bucket
* Deploy Kubeflow to the new cluster pointing to the cloned copy of the database and S3 bucket
* Run any tests necessary.
* If you ran the tests during a maintenance window, redirect production traffic to the new cluster. Or, if changes were made to the production database and S3 bucket while you were testing, repeat this procedure during a maintenance window so that the cloned database and S3 bucket are up to date.
* If you encounter problems, you can fail back to the original cluster.

## Detailed steps

### Step 1: Deploy a new EKS cluster

Similar to the process in [Create an EKS Cluster]({{< ref "/docs/deployment/create-eks-cluster.md" >}}), we'll use `eksctl` to create a new cluster. Review the more detailed information in [Create an EKS Cluster]({{< ref "/docs/deployment/create-eks-cluster.md" >}}) before proceeding.

In the code below, note that you need to provide a new cluster name (`BLUE_CLUSTER_NAME`) and specify a cluster version (`BLUE_CLUSTER_VERSION`). If you are upgrading EKS, specify the new version you want to use. If you are upgrading Kubeflow, use the same version as the production EKS cluster. 

```bash
export BLUE_CLUSTER_NAME=$BLUE_CLUSTER_NAME
export CLUSTER_REGION=$CLUSTER_REGION
export BLUE_CLUSTER_VERSION=1.23
```

Run the following command to create an EKS cluster:
```bash
eksctl create cluster \
--name ${BLUE_CLUSTER_NAME} \
--version ${BLUE_CLUSTER_VERSION} \
--region ${CLUSTER_REGION} \
--nodegroup-name linux-nodes \
--node-type m5.xlarge \
--nodes 5 \
--nodes-min 5 \
--nodes-max 10 \
--managed \
--with-oidc
```

If you have performed any other customizations on the production cluster, be sure to perform those on the new cluster as well.

### Step 2: Clone database and S3 bucket

First define the name of the new database instance, bucket, and database subnet group, plus a name to use for an IAM role for DataSync.

```bash
export S3_BUCKET_BLUE=$S3_BUCKET_BLUE
export DATASYNC_ROLE_NAME=datasyncrolekubeflow
export DB_INSTANCE_NAME_BLUE=$DB_INSTANCE_NAME_BLUE
export DB_SUBNET_GROUP_NAME_BLUE=$DB_SUBNET_GROUP_NAME_BLUE
```

Now execute the upgrade script.

```bash
    cd $REPO_ROOT
    cd tests/e2e
    PYTHONPATH=.. python utils/rds-s3/auto-rds-s3-upgrade.py \
        --region $CLUSTER_REGION \
        --bucket_green $S3_BUCKET \
        --bucket_blue $S3_BUCKET_BLUE \
        --datasync_role_name $DATASYNC_ROLE_NAME \
        --cluster_blue $BLUE_CLUSTER_NAME \
        --db_instance_name_green $DB_INSTANCE_NAME \
        --db_instance_name_blue $DB_INSTANCE_NAME_BLUE \
        --s3_secret_name $S3_SECRET_NAME \
        --rds_secret_name $RDS_SECRET_NAME \
        --db_subnet_group_name_blue $DB_SUBNET_GROUP_NAME_BLUE
```

