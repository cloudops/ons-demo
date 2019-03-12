# Required variables
variable "api_key" {}

variable "organization" {
    default = "workshops"
}

variable "username" {
    default = "demo"
}

variable "admin_role" {
    type = "list"
    default = ["wstevens", "opilotte", "amenezes", "sahmed"]
}

variable "api_url" {
    default = "https://compute-east.cloud.ca/client/api"
}

variable "service_name" {
    default = "compute-qc"
}

variable "zone" {
    default = "QC-2"
}

# default network offering w/ LB
variable "network_offering" {
    default = "Load Balanced Tier"
}

# default template type
variable "template" {
    default = "CentOS 7.6"
}

# default compute offering
variable "compute_offering" {
    default = "Standard"
}

variable "master_vcpu_count" {
    default = 8
}
variable "master_ram_in_mb" {
    default = 32768
}
variable "master_root_volume_size_in_gb" {
    default = 100
}

variable "worker_vcpu_count" {
    default = 8
}
variable "worker_ram_in_mb" {
    default = 16384
}
variable "worker_root_volume_size_in_gb" {
    default = 50
}

variable "tf_release" {
    default = "latest"
}