"""Synthetic intake handler for the demo.

Accepts a JSON intake request and returns an acknowledgment.
It never logs the request body, since in a real system that body
could contain patient information.
"""

import json
import logging
import uuid

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def lambda_handler(event, context):
    request_id = str(uuid.uuid4())

    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        logger.info("Rejected intake request %s: body is not valid JSON", request_id)
        return _response(400, {"error": "Request body must be valid JSON."})

    if not isinstance(body, dict):
        logger.info("Rejected intake request %s: body is not a JSON object", request_id)
        return _response(400, {"error": "Request body must be a JSON object."})

    # Log only which fields were sent, never their values.
    logger.info("Received intake request %s with fields: %s", request_id, sorted(body.keys()))

    return _response(202, {"status": "received", "request_id": request_id})


def _response(status_code, payload):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(payload),
    }