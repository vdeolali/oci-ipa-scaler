"""OCI Notifications-triggered instance-pool scaler POC."""
import io
import json
import logging
import os
from typing import Any, Mapping

import oci
from fdk import response

LOG = logging.getLogger(__name__)
LOG.setLevel(logging.INFO)


def _json(data: io.BytesIO) -> Mapping[str, Any]:
    value: Any = json.loads(data.getvalue().decode("utf-8") if data else "{}")
    for key in ("body", "message"):
        if isinstance(value, dict) and isinstance(value.get(key), str):
            try:
                value = json.loads(value[key])
            except json.JSONDecodeError:
                pass
    if not isinstance(value, dict):
        raise ValueError("notification must be a JSON object")
    return value


def _alarm_id(payload: Mapping[str, Any]) -> str | None:
    metadata = payload.get("alarmMetaData", [])
    if isinstance(metadata, list) and metadata and isinstance(metadata[0], dict):
        return metadata[0].get("id")
    return payload.get("alarmId")


def _reply(ctx, status: int, body: Mapping[str, Any]):
    return response.Response(ctx, status=status, response_data=json.dumps(body), headers={"Content-Type": "application/json"})


def handler(ctx, data: io.BytesIO = None):
    try:
        payload = _json(data)
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError) as error:
        LOG.warning("Rejecting malformed notification: %s", error)
        return _reply(ctx, 400, {"result": "rejected", "reason": "invalid_notification"})

    if payload.get("type") != "OK_TO_FIRING":
        return _reply(ctx, 200, {"result": "ignored", "reason": "not_ok_to_firing"})
    if _alarm_id(payload) != os.environ["CPU_ALARM_OCID"]:
        return _reply(ctx, 200, {"result": "ignored", "reason": "unapproved_alarm"})

    pool_id = os.environ["TARGET_INSTANCE_POOL_OCID"]
    target = int(os.environ.get("TARGET_POOL_SIZE", "5"))
    if target < 1:
        return _reply(ctx, 500, {"result": "error", "reason": "invalid_target_size"})

    signer = oci.auth.signers.get_resource_principals_signer()
    client = oci.core.ComputeManagementClient({}, signer=signer)
    pool_response = client.get_instance_pool(pool_id)
    pool = pool_response.data
    if pool.lifecycle_state != "RUNNING":
        return _reply(ctx, 409, {"result": "rejected", "reason": "pool_not_running"})
    if pool.size >= target:
        return _reply(ctx, 200, {"result": "no_op", "currentSize": pool.size, "targetSize": target})

    update = client.update_instance_pool(
        pool_id,
        oci.core.models.UpdateInstancePoolDetails(size=target),
        if_match=pool_response.headers.get("etag"),
        opc_retry_token=payload.get("dedupeKey") or payload.get("dedupekey"),
    )
    work_request_id = update.headers.get("opc-work-request-id")
    LOG.info("Submitted resize to %s; work request %s", target, work_request_id)
    return _reply(ctx, 202, {"result": "submitted", "targetSize": target, "workRequestId": work_request_id})
