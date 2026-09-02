output "workload_generator_instance_ocid" {
  value = oci_core_instance.workload_generator.id
}

output "function_application_ocid" {
  value = oci_functions_application.scaler.id
}

output "poc_vcn_ocid" {
  value = oci_core_vcn.poc.id
}

output "test_instance_pool_ocid" {
  value = oci_core_instance_pool.test_pool.id
}

output "cpu_alarm_ocid" {
  value = oci_monitoring_alarm.workload_cpu.id
}

output "function_ocid" {
  value = oci_functions_function.scaler.id
}

output "notification_topic_ocid" {
  value = oci_ons_notification_topic.cpu_alarm.id
}
