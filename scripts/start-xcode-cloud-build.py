#!/usr/bin/env python3
"""Starts a build of an Xcode Cloud workflow for a branch, with the App Store Connect API.

    scripts/start-xcode-cloud-build.py <branch> [--dry-run]
    scripts/start-xcode-cloud-build.py --show-build-run <build ID>

The API key comes from the environment: ASC_ISSUER_ID, ASC_KEY_ID and ASC_PRIVATE_KEY, the contents of the .p8
file. XCODE_CLOUD_WORKFLOW_ID is the ID of the workflow. The workflow is given by its ID, because the list of
products of the API doesn't have a product that is only for Xcode Cloud, such as SVGUIViewCI.

The build is for a branch, so the workflow needs a start condition that lets a build of the branch be started by
hand. A check of the build shows on a pull request of the branch.

With --dry-run, the script prints the workflow, its start conditions and the branch, without starting a build.
With --show-build-run and the ID of a build, which the link of a check of Xcode Cloud has, the script prints the
workflow and the product of the build.

The script uses only the standard library and openssl, so that a runner needs nothing installed.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com"


class APIError(Exception):
    pass


def base64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_signature_to_jws(der: bytes) -> bytes:
    """The ECDSA signature that openssl writes in DER, as JWS wants it: r and s in 32 bytes each."""

    def read_integer(data: bytes, offset: int) -> tuple[bytes, int]:
        if data[offset] != 0x02:
            raise ValueError("not a DER integer")
        length = data[offset + 1]
        start = offset + 2
        return data[start : start + length], start + length

    if der[0] != 0x30:
        raise ValueError("not a DER sequence")
    # The sequence of two 32-byte integers is shorter than 128 bytes, so its length takes one byte.
    r, offset = read_integer(der, 2)
    s, _ = read_integer(der, offset)
    return r.lstrip(b"\0").rjust(32, b"\0") + s.lstrip(b"\0").rjust(32, b"\0")


def make_token(issuer_id: str, key_id: str, private_key: str) -> str:
    """A token for the App Store Connect API, valid for 15 minutes."""
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    now = int(time.time())
    payload = {"iss": issuer_id, "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"}
    signing_input = f"{base64url(json.dumps(header).encode())}.{base64url(json.dumps(payload).encode())}"
    with tempfile.NamedTemporaryFile("w", suffix=".p8") as key_file:
        key_file.write(private_key)
        key_file.flush()
        der = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", key_file.name],
            input=signing_input.encode(),
            capture_output=True,
            check=True,
        ).stdout
    return f"{signing_input}.{base64url(der_signature_to_jws(der))}"


class Client:
    def __init__(self, token: str):
        self.token = token

    def request(self, method: str, path_or_url: str, body: dict | None = None) -> dict:
        url = path_or_url if path_or_url.startswith("https://") else API + path_or_url
        request = urllib.request.Request(
            url,
            method=method,
            data=json.dumps(body).encode() if body is not None else None,
            headers={"Authorization": f"Bearer {self.token}", "Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(request) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            try:
                errors = json.load(error).get("errors", [])
                details = "; ".join(f"{e.get('title')}: {e.get('detail')}" for e in errors)
            except (ValueError, AttributeError):
                details = ""
            raise APIError(f"{method} {urllib.parse.urlsplit(url).path} failed with {error.code}. {details}") from None

    def all(self, path: str) -> list[dict]:
        """Every resource of a collection, following the pages."""
        resources = []
        url = path + ("&" if "?" in path else "?") + "limit=200"
        while url:
            page = self.request("GET", url)
            resources.extend(page["data"])
            url = page.get("links", {}).get("next")
        return resources


def find(resources: list[dict], description: str, predicate, name=lambda r: r["attributes"]["name"]) -> dict:
    matches = [resource for resource in resources if predicate(resource)]
    if len(matches) != 1:
        found = ", ".join(str(name(resource)) for resource in resources) or "none"
        raise APIError(f"Found {len(matches)} {description}, not one. There are: {found}.")
    return matches[0]


def main() -> int:
    parser = argparse.ArgumentParser(description="Start a build of an Xcode Cloud workflow for a branch.")
    parser.add_argument("branch", nargs="?", help="the branch to build")
    parser.add_argument("--dry-run", action="store_true", help="find the workflow and the branch only")
    parser.add_argument("--show-build-run", metavar="ID", help="print the workflow and the product of a build")
    arguments = parser.parse_args()
    if arguments.branch is None and arguments.show_build_run is None:
        parser.error("give a branch")

    try:
        environment = {name: os.environ[name] for name in ("ASC_ISSUER_ID", "ASC_KEY_ID", "ASC_PRIVATE_KEY")}
        if not arguments.show_build_run:
            environment["XCODE_CLOUD_WORKFLOW_ID"] = os.environ["XCODE_CLOUD_WORKFLOW_ID"]
    except KeyError as error:
        print(f"Set {error.args[0]}.", file=sys.stderr)
        return 1

    try:
        client = Client(
            make_token(environment["ASC_ISSUER_ID"], environment["ASC_KEY_ID"], environment["ASC_PRIVATE_KEY"]))
        if arguments.show_build_run:
            build_run = client.request("GET", f"/v1/ciBuildRuns/{arguments.show_build_run}?include=workflow,product")
            for resource in build_run.get("included", []):
                print(f"{resource['type']}: {resource['attributes'].get('name')} ({resource['id']})")
            return 0

        workflow = client.request("GET", f"/v1/ciWorkflows/{environment['XCODE_CLOUD_WORKFLOW_ID']}?include=product")
        product_name = workflow["included"][0]["attributes"]["name"]
        workflow = workflow["data"]
        print(f"Workflow: {product_name} / {workflow['attributes']['name']}")
        if arguments.dry_run:
            for name in ("isEnabled", "manualBranchStartCondition", "branchStartCondition",
                         "manualPullRequestStartCondition", "pullRequestStartCondition"):
                print(f"  {name}: {json.dumps(workflow['attributes'].get(name))}")

        repository = client.request("GET", f"/v1/ciWorkflows/{workflow['id']}/repository")["data"]
        reference = find(
            client.all(f"/v1/scmRepositories/{repository['id']}/gitReferences"),
            f"branches named {arguments.branch}",
            lambda r: r["attributes"]["canonicalName"] == f"refs/heads/{arguments.branch}",
            name=lambda r: r["attributes"]["name"])
        print(f"Branch: {reference['attributes']['name']}")
        if arguments.dry_run:
            return 0

        build_run = client.request("POST", "/v1/ciBuildRuns", {
            "data": {
                "type": "ciBuildRuns",
                "relationships": {
                    "workflow": {"data": {"type": "ciWorkflows", "id": workflow["id"]}},
                    "sourceBranchOrTag": {"data": {"type": "scmGitReferences", "id": reference["id"]}},
                },
            },
        })["data"]
    except (APIError, subprocess.CalledProcessError, ValueError) as error:
        print(error, file=sys.stderr)
        return 1

    print(f"Started build {build_run['attributes']['number']} ({build_run['id']}).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
