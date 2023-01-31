variable "vpc_id" {
    type = string
    description = "VPC to create the FSx file system in"
}

variable "cluster_sg" {
    type = string
    description = "Cluster security group ID"
}
