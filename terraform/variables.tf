variable "region" {
  description = "POC region."
  type        = string
  default     = "us-phoenix-1"
}

variable "tenancy_ocid" {
  description = "Tenancy OCID; needed for IAM dynamic-group placement."
  type        = string
}

variable "compartment_ocid" {
  description = "Compartment OCID. All POC resources are created here."
  type        = string
}

variable "compartment_name" {
  description = "Compartment name, used only in IAM policy statements."
  type        = string
  default     = "POC"
}

variable "availability_domain" {
  description = "Availability domain used by the workload VM and test pool placement."
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key authorized on the disposable POC workload VM."
  type        = string
}

variable "vcn_cidr" {
  description = "CIDR block for the isolated POC VCN."
  type        = string
  default     = "10.42.0.0/16"
}

variable "functions_subnet_cidr" {
  description = "Private subnet CIDR used only by the Functions Application."
  type        = string
  default     = "10.42.1.0/24"
}

variable "workload_subnet_cidr" {
  description = "Private subnet CIDR used only by the workload-generator VM."
  type        = string
  default     = "10.42.2.0/24"
}

variable "pool_subnet_cidr" {
  description = "Private subnet CIDR used only by the zero-size test pool."
  type        = string
  default     = "10.42.3.0/24"
}

variable "workload_image_ocid" {
  description = "Ubuntu image OCID for the workload-generator VM; cloud-init installs stress-ng."
  type        = string
}

variable "pool_image_ocid" {
  description = "Image OCID used by instances launched in the isolated POC pool."
  type        = string
}

variable "function_image" {
  description = "Immutable OCIR image reference for the prebuilt scaler Function."
  type        = string
}

variable "function_image_digest" {
  description = "Optional immutable sha256 digest for function_image."
  type        = string
  default     = null
}

variable "workload_shape" {
  type    = string
  default = "VM.Standard.E4.Flex"
}

variable "pool_shape" {
  type    = string
  default = "VM.Standard.E4.Flex"
}

variable "workload_ocpus" {
  type    = number
  default = 2
}

variable "workload_memory_gbs" {
  type    = number
  default = 16
}

variable "pool_ocpus" {
  type    = number
  default = 1
}

variable "pool_memory_gbs" {
  type    = number
  default = 8
}

variable "cpu_threshold_percent" {
  description = "CPU percentage on the workload VM that triggers scale-out."
  type        = number
  default     = 80
}

variable "scale_out_step_size" {
  description = "Number of instances added to the current pool target by each scale-out alarm transition."
  type        = number
  default     = 1

  validation {
    condition     = var.scale_out_step_size >= 1
    error_message = "scale_out_step_size must be at least one."
  }
}

variable "scale_in_cpu_threshold_percent" {
  description = "CPU percentage at or below which the POC triggers scale-in."
  type        = number
  default     = 10

  validation {
    condition     = var.scale_in_cpu_threshold_percent >= 0 && var.scale_in_cpu_threshold_percent < 100
    error_message = "scale_in_cpu_threshold_percent must be from 0 through 99."
  }
}

variable "scale_in_target_pool_size" {
  description = "Target pool size applied by the scale-in alarm. Set to zero for the POC."
  type        = number
  default     = 0

  validation {
    condition     = var.scale_in_target_pool_size >= 0
    error_message = "scale_in_target_pool_size cannot be negative."
  }
}
