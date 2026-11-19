#!/usr/bin/env python3
"""What Apple needs to hold for an app, made where it is missing.

Run from the app's directory, the one holding tauri.conf.json. The app is
signed by the team's distribution certificate, the one in IOS_CERTIFICATE.
Apple signs nothing without the app's App IDs, their capabilities, and an App
Store profile made against that certificate; each is asked for with the key CI
holds, and made when Apple has none:

    apple.py APPLE_JSON OUT

APPLE_JSON names the profile and, per App ID, its capabilities. An App ID is
the app's identifier (tauri.conf.json) followed by its key, so "" is the app
itself and ".island" its extension. A capability is its capabilityType, or
{"type": ..., "settings": [...]} as App Store Connect takes it:

    {"profile": "laye",
     "ids": {"": ["PUSH_NOTIFICATIONS", "APP_ATTEST"], ".island": []}}

The profile is written to OUT, as Apple wrote it. It is no secret: it ships
inside every build.

Reads APPLE_API_KEY, APPLE_API_ISSUER, APPLE_API_KEY_CONTENT, IOS_CERTIFICATE
and IOS_CERTIFICATE_PASSWORD from the environment.
"""

import base64
import json
import os
import subprocess
import sys
import tempfile
import time

import jwt
import requests

ASC = "https://api.appstoreconnect.apple.com/v1"


def bearer():
    key = base64.b64decode(os.environ["APPLE_API_KEY_CONTENT"]).decode()
    now = int(time.time())
    token = jwt.encode(
        {"iss": os.environ["APPLE_API_ISSUER"], "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
        key, algorithm="ES256", headers={"kid": os.environ["APPLE_API_KEY"], "typ": "JWT"})
    return {"Authorization": f"Bearer {token}"}


def get(path, **params):
    r = requests.get(ASC + path, headers=bearer(), params=params, timeout=30)
    if r.status_code != 200:
        sys.exit(f"GET {path} answered {r.status_code}: {r.text}")
    return r.json()


def post(path, body):
    r = requests.post(ASC + path, headers={**bearer(), "Content-Type": "application/json"}, json=body, timeout=30)
    if r.status_code != 201:
        sys.exit(f"POST {path} answered {r.status_code}: {r.text}")
    return r.json()


def delete(path):
    r = requests.delete(ASC + path, headers=bearer(), timeout=30)
    if r.status_code != 204:
        sys.exit(f"DELETE {path} answered {r.status_code}: {r.text}")


def the_app_id(identifier, name):
    """The App ID, registered when Apple has none. The filter matches what
    begins with the identifier too, so the exact one is picked."""
    for held in get("/bundleIds", **{"filter[identifier]": identifier, "limit": 200})["data"]:
        if held["attributes"]["identifier"] == identifier:
            print("App ID:", identifier, "is registered,", held["id"])
            return held["id"]
    made = post("/bundleIds", {"data": {"type": "bundleIds",
                                        "attributes": {"identifier": identifier, "name": name, "platform": "IOS"}}})
    print("App ID:", identifier, "registered now,", made["data"]["id"])
    return made["data"]["id"]


def its_capabilities(bundle, identifier, wanted):
    """Every capability wanted is on, and every one Apple holds is printed,
    named as Apple names it."""
    held = {c["attributes"]["capabilityType"]
            for c in get(f"/bundleIds/{bundle}/bundleIdCapabilities", limit=200)["data"]}
    print(" ", identifier, "holds:", " ".join(sorted(held)) or "nothing")
    for capability in wanted:
        if isinstance(capability, str):
            capability = {"type": capability}
        if capability["type"] in held:
            continue
        attributes = {"capabilityType": capability["type"]}
        if "settings" in capability:
            attributes["settings"] = capability["settings"]
        post("/bundleIdCapabilities", {"data": {
            "type": "bundleIdCapabilities", "attributes": attributes,
            "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bundle}}}}})
        print(" ", identifier, "turned on now:", capability["type"])


def the_certificate():
    """The distribution certificate the app is signed with: the one in
    IOS_CERTIFICATE, found at Apple by its serial number."""
    with tempfile.NamedTemporaryFile(suffix=".p12") as p12:
        p12.write(base64.b64decode(os.environ["IOS_CERTIFICATE"]))
        p12.flush()
        pem = subprocess.run(
            ["openssl", "pkcs12", "-in", p12.name, "-nokeys", "-passin", "env:IOS_CERTIFICATE_PASSWORD", "-legacy"],
            capture_output=True, check=False)
        if pem.returncode != 0:
            pem = subprocess.run(
                ["openssl", "pkcs12", "-in", p12.name, "-nokeys", "-passin", "env:IOS_CERTIFICATE_PASSWORD"],
                capture_output=True, check=True)
    serial = subprocess.run(["openssl", "x509", "-noout", "-serial"], input=pem.stdout,
                            capture_output=True, check=True).stdout.decode().strip().split("=", 1)[1]
    for held in get("/certificates", limit=200)["data"]:
        if held["attributes"]["serialNumber"].upper().lstrip("0") == serial.upper().lstrip("0"):
            print("certificate:", held["attributes"]["name"], held["id"], "expires", held["attributes"]["expirationDate"])
            return held["id"]
    sys.exit(f"Apple holds no certificate with the serial {serial} that IOS_CERTIFICATE carries")


def the_profile(name, app_id, certificate):
    """The profile as Apple wrote it, made when Apple has none that is active.
    One Apple made invalid, as it does when an App ID's capabilities change,
    is deleted and made again."""
    for held in get("/profiles", **{"filter[name]": name, "limit": 200})["data"]:
        a = held["attributes"]
        if a["name"] != name or a["profileType"] != "IOS_APP_STORE":
            continue
        if a["profileState"] != "ACTIVE":
            delete(f"/profiles/{held['id']}")
            print("profile:", repr(name), held["id"], "was", a["profileState"], "and is deleted")
            continue
        of = get(f"/profiles/{held['id']}/bundleId")["data"]["id"]
        against = [c["id"] for c in get(f"/profiles/{held['id']}/certificates", limit=200)["data"]]
        if of == app_id and certificate in against:
            print("profile:", repr(name), "is held,", held["id"], "expires", a["expirationDate"])
            return a["profileContent"]
        sys.exit(
            f"Apple holds the profile {name!r} ({held['id']}) of {of} against {against}, and the app is "
            f"{app_id} against {certificate}: it signs nothing here. Revoke it at Apple, and run this again")
    made = post("/profiles", {"data": {
        "type": "profiles",
        "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
        "relationships": {
            "bundleId": {"data": {"type": "bundleIds", "id": app_id}},
            "certificates": {"data": [{"type": "certificates", "id": certificate}]},
        }}})["data"]
    print("profile:", repr(name), "made now,", made["id"], "expires", made["attributes"]["expirationDate"])
    return made["attributes"]["profileContent"]


def main(config_path, out):
    conf = json.load(open("tauri.conf.json"))
    config = json.load(open(config_path))
    if "" not in config["ids"]:
        sys.exit(f'{config_path} names no "" App ID, the app itself')
    bundles = {}
    for key, wanted in config["ids"].items():
        identifier = conf["identifier"] + key
        bundles[key] = the_app_id(identifier, (conf["productName"] + " " + key.lstrip(".")).strip())
        its_capabilities(bundles[key], identifier, wanted)
    content = the_profile(config["profile"], bundles[""], the_certificate())
    with open(out, "wb") as f:
        f.write(base64.b64decode(content))
    print("written:", out)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
