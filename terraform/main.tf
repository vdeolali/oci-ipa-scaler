locals {
  name_prefix = "oci-ipa-scaler-poc"
  tags = {
    "purpose" = "oci-ipa-scaler-poc"
    "owner"   = "compute"
  }
}

resource "oci_core_instance" "workload_generator" {
  availability_domain = var.availability_domain
  compartment_id      = var.compartment_ocid
  display_name        = "${local.name_prefix}-workload"
  shape               = var.workload_shape
  freeform_tags       = local.tags

  shape_config {
    ocpus         = var.workload_ocpus
    memory_in_gbs = var.workload_memory_gbs
  }

  create_vnic_details {
    subnet_id        = var.workload_subnet_ocid
    assign_public_ip = false
    display_name     = "${local.name_prefix}-workload-vnic"
  }

  source_details {
    source_type = "image"
    source_id   = var.workload_image_ocid
  }

  agent_config {
    is_monitoring_disabled = false
  }

  metadata = {
    user_data = base64encode(<<-CLOUDINIT
      #cloud-config
      package_update: true
      packages:
        - stress-ng
      CLOUDINIT
    )
  }
}

resource "oci_core_instance_configuration" "test_pool" {
  compartment_id = var.compartment_ocid
  display_name   = "${local.name_prefix}-config"
  freeform_tags  = local.tags

  instance_details {
    instance_type = "compute"

    launch_details {
      compartment_id = var.compartment_ocid
      shape          = var.pool_shape

      shape_config {
        ocpus         = var.pool_ocpus
        memory_in_gbs = var.pool_memory_gbs
      }

      create_vnic_details {
        subnet_id        = var.pool_subnet_ocid
        assign_public_ip = false
      }

      source_details {
        source_type = "image"
        image_id    = var.pool_image_ocid
      }
    }
  }
}

resource "oci_core_instance_pool" "test_pool" {
  compartment_id            = var.compartment_ocid
  display_name              = "${local.name_prefix}-pool"
  instance_configuration_id = oci_core_instance_configuration.test_pool.id
  size                      = 0
  freeform_tags             = local.tags

  placement_configurations {
    availability_domain = var.availability_domain
    primary_subnet_id   = var.pool_subnet_ocid
  }
}

resource "oci_functions_application" "scaler" {
  compartment_id = var.compartment_ocid
  display_name   = "${local.name_prefix}-app"
  subnet_ids     = [var.function_subnet_ocid]
  # The POC image is built on an Apple Silicon workstation. This shape permits
  # OCI Functions to run the ARM64 image while retaining x86 compatibility.
  shape         = "GENERIC_X86_ARM"
  freeform_tags = local.tags
}

resource "oci_ons_notification_topic" "cpu_alarm" {
  compartment_id = var.compartment_ocid
  name           = "${local.name_prefix}-cpu-topic"
  description    = "POC CPU alarm delivery topic for the direct pool scaler"
  freeform_tags  = local.tags
}

resource "oci_monitoring_alarm" "workload_cpu" {
  compartment_id        = var.compartment_ocid
  metric_compartment_id = var.compartment_ocid
  display_name          = "${local.name_prefix}-cpu-high"
  namespace             = "oci_computeagent"
  query                 = "CpuUtilization[1m]{resourceId = \"${oci_core_instance.workload_generator.id}\"}.mean() > ${var.cpu_threshold_percent}"
  resolution            = "1m"
  pending_duration      = "PT1M"
  severity              = "WARNING"
  destinations          = [oci_ons_notification_topic.cpu_alarm.id]
  is_enabled            = true
  message_format        = "RAW"
  freeform_tags         = local.tags
}

resource "oci_identity_dynamic_group" "scaler_functions" {
  compartment_id = var.tenancy_ocid
  name           = "${local.name_prefix}-functions"
  description    = "Functions that may update only the isolated OCI IPA scaler POC pool"
  matching_rule  = "ALL {resource.type = 'fnfunc', resource.compartment.id = '${var.compartment_ocid}'}"
}

resource "oci_identity_policy" "function_pool_access" {
  compartment_id = var.tenancy_ocid
  name           = "${local.name_prefix}-function-pool-access"
  description    = "Allows the POC Function resource principal to resize pools in K8s"
  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.scaler_functions.name} to manage instance-pools in compartment ${var.compartment_name}",
    "Allow service ons to use functions-family in compartment ${var.compartment_name}"
  ]
}

resource "oci_functions_function" "scaler" {
  application_id     = oci_functions_application.scaler.id
  display_name       = "${local.name_prefix}-function"
  image              = var.function_image
  image_digest       = var.function_image_digest
  memory_in_mbs      = 256
  timeout_in_seconds = 30
  freeform_tags      = local.tags

  config = {
    CPU_ALARM_OCID            = oci_monitoring_alarm.workload_cpu.id
    TARGET_INSTANCE_POOL_OCID = oci_core_instance_pool.test_pool.id
    TARGET_POOL_SIZE          = tostring(var.target_pool_size)
  }
}

resource "oci_ons_subscription" "invoke_scaler" {
  compartment_id = var.compartment_ocid
  topic_id       = oci_ons_notification_topic.cpu_alarm.id
  protocol       = "ORACLE_FUNCTIONS"
  endpoint       = oci_functions_function.scaler.id
}
