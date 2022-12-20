SHELL := /bin/bash # Use bash syntax

deploy: init \
 create-vpc \
 create-eks-cluster \
 deploy-eks-blueprints-k8s-addons \
 deploy-kubeflow-components

delete: delete-kubeflow-components \
 delete-eks-blueprints-k8s-addons \
 delete-eks-cluster \
 delete-vpc
	terraform destroy -auto-approve

deploy-velero: init \
  create-velero-role

init:
	terraform init


create-vpc:
	terraform apply -target="module.vpc" -auto-approve

create-eks-cluster:
	terraform apply -target="module.eks_blueprints" -auto-approve
	terraform output -raw configure_kubectl | bash

create-velero-role:
	terraform apply -target="module.iam_eks_role" -auto-approve
	terraform apply -target="module.velero_role" -auto-approve

deploy-eks-blueprints-k8s-addons:
	terraform apply -target="module.eks_blueprints_kubernetes_addons" -auto-approve

deploy-kubeflow-components:
	terraform apply -target="module.kubeflow_components" -auto-approve


delete-vpc:
	terraform destroy -target="module.vpc" -auto-approve

delete-eks-cluster:
	terraform destroy -target="module.eks_blueprints" -auto-approve

delete-eks-blueprints-k8s-addons:
	terraform destroy -target="module.eks_blueprints_kubernetes_addons" -auto-approve

delete-kubeflow-components:
	terraform destroy -target="module.kubeflow_components" -auto-approve

# don't create executables
.PHONY: *
