from __future__ import annotations

from collections.abc import Mapping
import hashlib
import hmac
import json
import os
import textwrap
from typing import Any

import requests


def create_response(status_code: int, message: str | dict[str, Any]) -> dict[str, Any]:
    print(f"Status code: {status_code}")
    print(f"Message: {message}")
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
        },
        "body": json.dumps({
            "message": message
        }),
    }


def validate_signatures(*, key: str, body: str, sig: str) -> bool:
    mac = hmac.HMAC(key.encode(), body.encode(), digestmod=hashlib.sha256)
    return hmac.compare_digest(f"sha256={mac.hexdigest()}", sig)


def send_mail(*, source: str, recipient: str, subject: str, message: str) -> None:
    import boto3

    ses_client = boto3.client("ses", region_name="eu-west-1")
    CHARSET = "utf8"

    try:
        ses_client.send_email(
            Source=source,
            Destination={
                "ToAddresses": [recipient],
            },
            Message={
                "Subject": {
                    "Charset": CHARSET,
                    "Data": subject,
                },
                "Body": {
                    "Text": {
                        "Charset": CHARSET,
                        "Data": message,
                    },
                }
            }
        )
    except Exception as ex:
        print(f"Exception occurred while sending email: {ex!r}")
    else:
        print("Sent message")


def trigger_gh_action(
    *, repo: str, github_pat: str, event_type: str, payload: dict[str, Any]
) -> requests.Response:
    return requests.post(
        f"https://api.github.com/repos/{repo}/dispatches",
        json={
            "event_type": event_type,
            "client_payload": payload,
        },
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {github_pat}",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )


def lambda_handler(event: Mapping[str, Any], context: Mapping[str, Any]) -> dict[str, Any]:
    key = os.environ["sig_key"]
    body: str = event["body"]
    sig: str = event["headers"]["X-Hub-Signature-256"]

    if not validate_signatures(key=key, body=body, sig=sig):
        return create_response(400, "Invalid signature")

    data = json.loads(body)
    commit: str | None = data.get("after")
    if commit is None and data.get("zen"):
        print("Ping event")
        return create_response(200, "success")
    if data.get("deleted"):
        print("Deleted branch")
        return create_response(200, "success")
    assert commit is not None

    resp = trigger_gh_action(
        repo=os.environ["repo"],
        github_pat=os.environ["github_pat"],
        event_type="create-tag",
        payload={
            "commit": commit,
            "ref": data["ref"],
        }
    )
    if not resp.ok:
        print("An error occurred while doing the POST request")
        send_mail(
            source=os.environ["mail_source"],
            recipient=os.environ["mail_recipient"],
            subject="[mypy-wheels] Error occurred",
            message=textwrap.dedent(f"""\
                An error occurred while trying to process the webhook push event.
                Commit: {commit}

                Code:   {resp.status_code}
                Error:  {resp.json()}
            """),
        )
        return create_response(
            resp.status_code,
            resp.json(),
        )

    return create_response(
        resp.status_code,
        "success",
    )
