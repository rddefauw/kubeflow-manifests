variable "vpc_id" {
    type = string
    description = "VPC to create the EFS file system in"
}

variable "cidr_block" {
    type = string
    description = "VPC CIDR block"
}

variable "cluster_subnet_ids" {
    type = list
    description = "EKS cluster public subnet ids"
}