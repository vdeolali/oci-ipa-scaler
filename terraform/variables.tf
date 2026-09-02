variable "region" {
  description = "POC region. The approved sandbox target is us-phoenix-1."
  type        = string
  default     = "us-phoenix-1"
}

variable "tenancy_ocid" {
  description = "sanjpill_sandbox tenancy OCID; needed for IAM dynamic-group placement."
  type        = string
}

variable "compartment_ocid" {
  description = "K8s compartment OCID. All POC resources are created here."
  type        = string
}

variable "compartment_name" {
  description = "K8s compartment name, used only in IAM policy statements."
  type        = string
  default     = "K8s"
}

variable "availability_domain" {
  description = "Availability domain used by the workload VM and test pool placement."
  type        = string
}

variable "function_subnet_ocid" {
  description = "Existing private subnet for the Functions Application; it needs registry egress."
  type        = string
}

variable "workload_subnet_ocid" {
  description = "Existing subnet for the dedicated workload-generator VM."
  type        = string
}

variable "pool_subnet_ocid" {
  description = "Existing subnet for instances created by the isolated POC pool."
  type        = string
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
  description = "CPU percentage on the workload VM that fires the POC alarm."
  type        = number
  default     = 80
}

variable "target_pool_size" {
  description = "Fixed target applied by the POC Function after its approved alarm fires."
  type        = number
  default     = 5

  validation {
    condition     = var.target_pool_size >= 1
    error_message = "target_pool_size must be at least one."
  }
}
