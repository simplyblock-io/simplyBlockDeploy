variable "cluster_name" {
  default     = "simplyblock-eks-cluster"
  description = "EKS Cluster name"
}

variable "whitelist_ips" {
  type = list(string)
  default = [ "195.176.32.0/24", "84.254.107.0/24"]
}

variable "enable_eks" {
  default = 0
  type = number
}

variable "key_name" {
  default = "simplyblock-us-east-2.pem"
  type = string
}

variable "mgmt_nodes" {
  default = 3
  type  = number
}

variable "storage_nodes" {
  default = 3
  type  = number
}

variable "extra_nodes" {
  default = 1
  type  = number
}