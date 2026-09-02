# OCI IPA Scaler POC

This package implements an isolated sandbox POC:

`workload VM (stress-ng) -> OCI Monitoring alarm -> Notifications topic -> OCI Function -> UpdateInstancePool`

The test pool starts at `0`. When the approved CPU alarm transitions from `OK` to `FIRING`, the Function sets it to the configured POC target (`5` by default). It does not touch the customer pool or scheduled autoscaling policy.

## Deploy to OCI

[![Deploy to Oracle Cloud](https://oci-resourcemanager-plugin.plugins.oci.oraclecloud.com/latest/deploy-to-oracle-cloud.svg)](https://cloud.oracle.com/resourcemanager/stacks/create?zipUrl=https://github.com/user-attachments/files/31760534/oci-ipa-scaler-rm.zip)

The button opens Resource Manager with the versioned Terraform package already selected. Select the target compartment, provide the function image URI and digest from that tenancy's private OCIR repository, then run Plan and Apply.

## Package contents

- `function/`: OCI Function source and container definition.
- `terraform/`: Resource Manager Terraform configuration.
- `scripts/run-stress.sh`: workload-generator test command.

## Build and registry configuration

The public source contains no internal registry location or sandbox image reference. Build it with the FDK base images approved for the deploying organization, then push the resulting image to that organization's private OCIR repository:

```bash
docker build \
  --build-arg FDK_BUILD_IMAGE='<approved-build-image>' \
  --build-arg FDK_RUN_IMAGE='<approved-run-image>' \
  -t '<region>.ocir.io/<namespace>/oci-ipa-scaler/oci-ipa-scaler:0.1.0' \
  function
```

Set the resulting image URI and digest in the Resource Manager variables. `function/func.yaml` is an Fn CLI template; replace its two example image values only if using `fn deploy`.

## POC validation

1. Apply the stack in the selected POC compartment and region. It creates its own private VCN, three private subnets, and outbound-only NAT gateway; it does not reuse an existing network.
2. Run `scripts/run-stress.sh` on the separate workload-generator VM.
3. Verify alarm firing, Function log entry, Compute work request, and target-pool size `0 -> 5`.

For production, IPA must invoke the Function when its desired pool size changes, passing the approved pool key and desired size. The CPU alarm is POC-only.
