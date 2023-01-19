variable "vpc_id" {
    description = "VPC for the ALB"
    type = string
}
variable "subnet_ids" {
    description = "Public subnets to use for the ALB"
    type = list
}
variable "certificate_arn" {
    description = "Certificate to use with the ALB" 
    type = string
}
variable "redirect_to" {
    description = "The CNAME record of the Kubeflow cluster to redirect traffic to"
    type = string
}
variable "redirect_from" {
    description = "The alias DNS record used for the ALB"
    type = string
}
variable "zone_id" {
    description = "The Route 53 zone ID used for the alias record"
    type = string
}