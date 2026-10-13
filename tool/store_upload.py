#!/usr/bin/env python3
"""Push iBuild's store listing (text, screenshots, icon, feature graphic) to
App Store Connect and Google Play from the files in store/.

    python3 tool/store_upload.py            # dry run: show the plan
    python3 tool/store_upload.py --apply    # upload

Environment:
    ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY_PATH   App Store Connect API key
    PLAY_KEY_PATH                                     Play service account JSON

Only en-US gets images; every other locale falls back to it. The App Store
side writes to the version in PREPARE_FOR_SUBMISSION, so a live version's
listing is never touched.
"""
import hashlib
import json
import os
import sys
import time

import jwt
import requests

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
STORE = os.path.join(ROOT, "store")
BUNDLE = "com.adventhub.ibuild"
APPLY = "--apply" in sys.argv
ASC = "https://api.appstoreconnect.apple.com"
PLAY = f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{BUNDLE}"
PLAY_UPLOAD = f"https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/{BUNDLE}"

ASC_SETS = {"APP_IPHONE_67": "apple_69", "APP_IPAD_PRO_3GEN_129": "apple_13"}
PLAY_IMAGES = {
    "phoneScreenshots": "screenshots/play_phone",
    "sevenInchScreenshots": "screenshots/play_tablet",
    "tenInchScreenshots": "screenshots/play_tablet",
    "featureGraphic": "feature_graphic.png",
    "icon": "icon_512.png",
}


def text(name):
    with open(os.path.join(STORE, name), encoding="utf-8") as f:
        return f.read().strip()


def files(rel):
    path = os.path.join(STORE, rel)
    if os.path.isfile(path):
        return [path]
    return sorted(os.path.join(path, f) for f in os.listdir(path) if f.endswith(".png"))


def _retrying(method):
    """requests.<method> that retries Google's and Apple's transient 5xx/429s."""
    def call(*args, **kwargs):
        for attempt in range(5):
            r = method(*args, **kwargs)
            if r.status_code < 500 and r.status_code != 429:
                return r
            time.sleep(4 * (attempt + 1))
        return r
    return call


requests.get, requests.post, requests.put, requests.delete, requests.request = (
    _retrying(requests.get), _retrying(requests.post), _retrying(requests.put),
    _retrying(requests.delete), _retrying(requests.request))


def ok(r):
    if not r.ok:
        raise SystemExit(f"{r.request.method} {r.url} -> {r.status_code}\n{r.text[:800]}")
    return r.json() if r.text else {}


# --------------------------------------------------------------- App Store

def asc_headers():
    now = int(time.time())
    token = jwt.encode(
        {"iss": os.environ.get("ASC_ISSUER_ID", "ca1877f5-6e2b-4ef7-acd7-cef8ab4b8807"),
         "iat": now, "exp": now + 1000, "aud": "appstoreconnect-v1"},
        open(os.environ["ASC_PRIVATE_KEY_PATH"]).read(),
        algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"]})
    return {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}


def asc(method, path, **kw):
    return ok(requests.request(method, ASC + path, headers=asc_headers(), timeout=120, **kw))


def app_store():
    app = asc("GET", "/v1/apps", params={"filter[bundleId]": BUNDLE})["data"][0]
    version = asc("GET", f"/v1/apps/{app['id']}/appStoreVersions",
                  params={"filter[appStoreState]": "PREPARE_FOR_SUBMISSION"})["data"][0]
    loc = next(l for l in asc("GET", f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations")["data"]
               if l["attributes"]["locale"] == "en-US")
    info = next(i for i in asc("GET", f"/v1/apps/{app['id']}/appInfos")["data"]
                if i["attributes"].get("state") != "READY_FOR_DISTRIBUTION")
    info_loc = next(l for l in asc("GET", f"/v1/appInfos/{info['id']}/appInfoLocalizations")["data"]
                    if l["attributes"]["locale"] == "en-US")
    print(f"App Store {app['attributes']['name']} {version['attributes']['versionString']}")
    attrs = {"description": text("full_description.txt"), "keywords": text("keywords.txt"),
             "promotionalText": text("promotional_text.txt")}
    print(f"  text: description {len(attrs['description'])} chars, subtitle, keywords, promo")
    if APPLY:
        asc("PATCH", f"/v1/appStoreVersionLocalizations/{loc['id']}",
            json={"data": {"type": "appStoreVersionLocalizations", "id": loc["id"], "attributes": attrs}})
        asc("PATCH", f"/v1/appInfoLocalizations/{info_loc['id']}",
            json={"data": {"type": "appInfoLocalizations", "id": info_loc["id"],
                           "attributes": {"subtitle": text("subtitle.txt")}}})

    sets = {s["attributes"]["screenshotDisplayType"]: s for s in asc(
        "GET", f"/v1/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets",
        params={"include": "appScreenshots"})["data"]}
    for kind, folder in ASC_SETS.items():
        shots = files(f"screenshots/{folder}")
        existing = sets.get(kind)
        old = [s["id"] for s in existing["relationships"]["appScreenshots"]["data"]] if existing else []
        print(f"  {kind}: replace {len(old)} with {len(shots)}")
        if not APPLY:
            continue
        for sid in old:
            asc("DELETE", f"/v1/appScreenshots/{sid}")
        set_id = existing["id"] if existing else asc("POST", "/v1/appScreenshotSets", json={"data": {
            "type": "appScreenshotSets", "attributes": {"screenshotDisplayType": kind},
            "relationships": {"appStoreVersionLocalization": {
                "data": {"type": "appStoreVersionLocalizations", "id": loc["id"]}}}}})["data"]["id"]
        for path in shots:
            data = open(path, "rb").read()
            shot = asc("POST", "/v1/appScreenshots", json={"data": {
                "type": "appScreenshots",
                "attributes": {"fileName": os.path.basename(path), "fileSize": len(data)},
                "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}}}})["data"]
            for op in shot["attributes"]["uploadOperations"]:
                r = requests.request(op["method"], op["url"], data=data[op["offset"]:op["offset"] + op["length"]],
                                     headers={h["name"]: h["value"] for h in op.get("requestHeaders", [])}, timeout=180)
                if not r.ok:
                    raise SystemExit(f"upload failed for {path}: {r.status_code}")
            asc("PATCH", f"/v1/appScreenshots/{shot['id']}", json={"data": {
                "type": "appScreenshots", "id": shot["id"],
                "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})


# ------------------------------------------------------------- Google Play

def play_headers():
    account = json.load(open(os.environ["PLAY_KEY_PATH"]))
    now = int(time.time())
    assertion = jwt.encode({"iss": account["client_email"], "scope": "https://www.googleapis.com/auth/androidpublisher",
                            "aud": "https://oauth2.googleapis.com/token", "iat": now, "exp": now + 3600},
                           account["private_key"], algorithm="RS256")
    token = ok(requests.post("https://oauth2.googleapis.com/token", timeout=60, data={
        "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer", "assertion": assertion}))["access_token"]
    return {"Authorization": f"Bearer {token}"}


def google_play():
    h = play_headers()
    edit = ok(requests.post(f"{PLAY}/edits", headers=h, timeout=60))["id"]
    listing = ok(requests.get(f"{PLAY}/edits/{edit}/listings/en-US", headers=h, timeout=60))
    print("Google Play en-US")
    print(f"  text: short {len(text('short_description.txt'))} chars, full {len(text('full_description.txt'))} chars")
    if APPLY:
        ok(requests.put(f"{PLAY}/edits/{edit}/listings/en-US", headers=h, timeout=60, json={
            "language": "en-US", "title": listing.get("title") or "iBuild: Mobile CI/CD",
            "shortDescription": text("short_description.txt"),
            "fullDescription": text("full_description.txt")}))
    for kind, rel in PLAY_IMAGES.items():
        imgs = files(rel)
        print(f"  {kind}: {len(imgs)}")
        if not APPLY:
            continue
        ok(requests.delete(f"{PLAY}/edits/{edit}/listings/en-US/{kind}", headers=h, timeout=60))
        for path in imgs:
            ok(requests.post(f"{PLAY_UPLOAD}/edits/{edit}/listings/en-US/{kind}", params={"uploadType": "media"},
                             headers={**h, "Content-Type": "image/png"}, data=open(path, "rb").read(), timeout=180))
    if APPLY:
        ok(requests.post(f"{PLAY}/edits/{edit}:validate", headers=h, timeout=60))
        ok(requests.post(f"{PLAY}/edits/{edit}:commit", headers=h, timeout=120))
        print("  committed")
    else:
        requests.delete(f"{PLAY}/edits/{edit}", headers=h, timeout=60)


if __name__ == "__main__":
    if not APPLY:
        print("DRY RUN — nothing is changed. Re-run with --apply.\n")
    app_store()
    google_play()
