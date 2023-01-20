SHELL := /bin/bash # Use bash syntax

deploy: init \
 create-eks-cluster \
 deploy-eks-blueprints-k8s-addons \
 deploy-kubeflow-components \
 deploy-alb-redirect

delete: delete-alb-redirect \
 delete-kubeflow-components \
 delete-eks-blueprints-k8s-addons \
 delete-eks-cluster 

init:
	terraform init


create-eks-cluster:
	terraform apply -target="module.eks_blueprints" -auto-approve
	terraform output -raw configure_kubectl | bash

deploy-eks-blueprints-k8s-addons:
	terraform apply -target="module.eks_blueprints_kubernetes_addons" -auto-approve

deploy-kubeflow-components:
	terraform apply -target="module.kubeflow_components" -auto-approve

deploy-alb-redirect:
	terraform apply -target="module.alb_redirection" -auto-approve

delete-eks-cluster:
	terraform destroy -target="module.eks_blueprints" -auto-approve

delete-eks-blueprints-k8s-addons:
	terraform destroy -target="module.eks_blueprints_kubernetes_addons" -auto-approve

delete-kubeflow-components:
	terraform destroy -target="module.kubeflow_components" -auto-approve

delete-alb-redirect:
	terraform destroy -target="module.alb_redirection" -auto-approve

# don't create executables
.PHONY: *