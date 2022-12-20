+++
title = "Upgrade"
description = "Upgrading Kubeflow"
weight = 90
+++

Kubeflow does not natively offer an upgrade process. An in-place upgrade often works, but we recommend a blue/green upgrade process that provides a fail-back capability. We will leverage integration with AWS storage and database services to let us deploy a new EKS cluster with Kubeflow and connect it to the external data stores. We will also use an open-source tool to copy certain resources from the production EKS cluster to the new one, and use AWS Backup to snapshot the state of our external data stores.

## Configure Velero in production cluster

First, we will configure Velero in the production cluster.

```bash
cd $REPO_ROOT/deployments/rds-s3/terraform
make deploy-velero
```

## Deploy backup EKS cluster

Next, we will create a new `tfvars` file with the name of the backup cluster.

```bash
cd $REPO_ROOT/deployments/upgrade/terraform
cp ../../rds-s3/terraform/sample.auto.tfvars .
```

Edit the `sample.auto.tfvars` file and set the name of the backup EKS cluster in the `cluster_name` variable. The other variables can stay the same.

Now deploy the backup cluster.

```bash
make deploy
```