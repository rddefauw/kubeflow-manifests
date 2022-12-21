variable "resources" {
    type = list
    description = "Resource ARNs to include in backup plan"
}

variable "use_scheduled_backup" {
    type = bool
    description = "Use scheduled backup plan"
    default = false
}