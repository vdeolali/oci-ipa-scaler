locals {
  name_prefix = "oci-ipa-scaler-poc"
  tags = {
    "purpose" = "oci-ipa-scaler-poc"
    "owner"   = "compute"
  }
}

resource "oci_core_vcn" "poc" {
  compartment_id = var.compartment_ocid
  display_name   = "${local.name_prefix}-vcn"
  cidr_blocks    = [var.vcn_cidr]
  dns_label      = "ipapoc"
  freeform_tags  = local.tags
}

# The pool and Function use private addresses. The disposable workload VM is
# intentionally public so the POC operator can SSH in and generate CPU load.
resource "oci_core_nat_gateway" "poc" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.poc.id
  display_name   = "${local.name_prefix}-nat"
  freeform_tags  = local.tags
}

resource "oci_core_internet_gateway" "poc" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.poc.id
  display_name   = "${local.name_prefix}-igw"
  enabled        = true
  freeform_tags  = local.tags
}

resource "oci_core_route_table" "private" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.poc.id
  display_name   = "${local.name_prefix}-private-rt"
  freeform_tags  = local.tags

  route_rules {
    network_entity_id = oci_core_nat_gateway.poc.id
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
  }
}

resource "oci_core_route_table" "workload_public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.poc.id
  display_name   = "${local.name_prefix}-workload-public-rt"
  freeform_tags  = local.tags

  route_rules {
    network_entity_id = oci_core_internet_gateway.poc.id
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
  }
}

resource "oci_core_security_list" "private" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.poc.id
  display_name   = "${local.name_prefix}-private-sl"
  freeform_tags  = local.tags

  # No inbound rule is needed: the VM, pool, and Function are private-only.
  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }
}

resource "oci_core_security_list" "workload_public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.poc.id
  display_name   = "${local.name_prefix}-workload-public-sl"
  freeform_tags  = local.tags

  # Temporary POC access. Remove this rule when the test VM is destroyed.
  ingress_security_rules {
    protocol = "6"

    source = "0.0.0.0/0"

    tcp_options {
      min = 22
      max = 22
    }
  }

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }
}

resource "oci_core_subnet" "functions" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.poc.id
  display_name               = "${local.name_prefix}-functions-subnet"
  cidr_block                 = var.functions_subnet_cidr
  dns_label                  = "functions"
  route_table_id             = oci_core_route_table.private.id
  security_list_ids          = [oci_core_security_list.private.id]
  prohibit_public_ip_on_vnic = true
  freeform_tags              = local.tags
}

resource "oci_core_subnet" "workload" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.poc.id
  display_name               = "${local.name_prefix}-workload-subnet"
  cidr_block                 = var.workload_subnet_cidr
  dns_label                  = "workload"
  route_table_id             = oci_core_route_table.workload_public.id
  security_list_ids          = [oci_core_security_list.workload_public.id]
  prohibit_public_ip_on_vnic = false
  freeform_tags              = local.tags
}

resource "oci_core_subnet" "pool" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.poc.id
  display_name               = "${local.name_prefix}-pool-subnet"
  cidr_block                 = var.pool_subnet_cidr
  dns_label                  = "pool"
  route_table_id             = oci_core_route_table.private.id
  security_list_ids          = [oci_core_security_list.private.id]
  prohibit_public_ip_on_vnic = true
  freeform_tags              = local.tags
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
    subnet_id        = oci_core_subnet.workload.id
    assign_public_ip = true
    display_name     = "${local.name_prefix}-workload-vnic"
  }

  source_details {
    source_type = "image"
    source_id   = var.workload_image_ocid
  }

  agent_config {
    is_monitoring_disabled = false

    plugins_config {
      name          = "Compute Instance Run Command"
      desired_state = "ENABLED"
    }
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
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
        subnet_id        = oci_core_subnet.pool.id
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
    primary_subnet_id   = oci_core_subnet.pool.id
  }
}

resource "oci_functions_application" "scaler" {
  compartment_id = var.compartment_ocid
  display_name   = "${local.name_prefix}-app"
  subnet_ids     = [oci_core_subnet.functions.id]
  # The POC image is built on an Apple Silicon workstation and is ARM64.
  shape         = "GENERIC_ARM"
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

resource "oci_monitoring_alarm" "workload_cpu_low" {
  compartment_id        = var.compartment_ocid
  metric_compartment_id = var.compartment_ocid
  display_name          = "${local.name_prefix}-cpu-low"
  namespace             = "oci_computeagent"
  query                 = "CpuUtilization[1m]{resourceId = \"${oci_core_instance.workload_generator.id}\"}.mean() <= ${var.scale_in_cpu_threshold_percent}"
  resolution            = "1m"
  # Kept short for the demonstration. Use a longer duration in production to
  # avoid scaling in during a temporary lull in workload demand.
  pending_duration = "PT1M"
  severity         = "WARNING"
  destinations     = [oci_ons_notification_topic.cpu_alarm.id]
  is_enabled       = true
  message_format   = "RAW"
  freeform_tags    = local.tags
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
  description    = "Allows the POC Function resource principal to resize its test pool"
  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.scaler_functions.name} to manage compute-management-family in compartment id ${var.compartment_ocid}",
    "Allow dynamic-group ${oci_identity_dynamic_group.scaler_functions.name} to manage instance-pools in compartment id ${var.compartment_ocid}",
    "Allow dynamic-group ${oci_identity_dynamic_group.scaler_functions.name} to manage instance-family in compartment id ${var.compartment_ocid}",
    "Allow dynamic-group ${oci_identity_dynamic_group.scaler_functions.name} to use volume-family in compartment id ${var.compartment_ocid}",
    "Allow dynamic-group ${oci_identity_dynamic_group.scaler_functions.name} to use virtual-network-family in compartment id ${var.compartment_ocid}",
    "Allow dynamic-group ${oci_identity_dynamic_group.scaler_functions.name} to read app-catalog-listing in compartment id ${var.compartment_ocid}",
    "Allow service notification to use functions-family in compartment id ${var.compartment_ocid}"
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
    SCALE_OUT_ALARM_OCID      = oci_monitoring_alarm.workload_cpu.id
    SCALE_OUT_STEP_SIZE       = tostring(var.scale_out_step_size)
    SCALE_IN_ALARM_OCID       = oci_monitoring_alarm.workload_cpu_low.id
    SCALE_IN_TARGET_POOL_SIZE = tostring(var.scale_in_target_pool_size)
    TARGET_INSTANCE_POOL_OCID = oci_core_instance_pool.test_pool.id
  }
}

resource "oci_ons_subscription" "invoke_scaler" {
  compartment_id = var.compartment_ocid
  topic_id       = oci_ons_notification_topic.cpu_alarm.id
  protocol       = "ORACLE_FUNCTIONS"
  endpoint       = oci_functions_function.scaler.id
}
