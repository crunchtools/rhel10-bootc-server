#!/usr/bin/env python3
"""A throwaway OCI registry on loopback, for digest-gate.sh's self-test.

    oci-registry.py PORTFILE   serves the distribution API in memory on
                               127.0.0.1, writes the port it bound to
                               PORTFILE, and seeds rhel10-bootc-server with
                               two images, :signed and :unsigned, that
                               differ in one file. Nothing is signed here:
                               the test signs :signed itself.

Just enough of the API for skopeo inspect, cosign sign and cosign verify. It
reads and writes nothing off the host, so the gate is tested with no network.
"""
import hashlib
import io
import json
import re
import sys
import tarfile
import uuid
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

OCI_MANIFEST = "application/vnd.oci.image.manifest.v1+json"
REPO = "rhel10-bootc-server"

blobs = {}  # digest -> bytes
manifests = {}  # (repo, digest) -> (media type, bytes)
tags = {}  # (repo, tag) -> digest
uploads = {}  # upload id -> bytearray


def digest(data):
    return "sha256:" + hashlib.sha256(data).hexdigest()


def put_blob(data):
    blobs[digest(data)] = data
    return {"digest": digest(data), "size": len(data)}


def put_manifest(repo, ref, media_type, data):
    d = digest(data)
    manifests[(repo, d)] = (media_type, data)
    if not ref.startswith("sha256:"):
        tags[(repo, ref)] = d
    return d


def seed(tag):
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w") as tar:
        body = f"digest-gate fixture: {tag}\n".encode()
        info = tarfile.TarInfo("etc/fixture")
        info.size = len(body)
        tar.addfile(info, io.BytesIO(body))
    layer = put_blob(buf.getvalue())
    config = put_blob(json.dumps({
        "architecture": "amd64", "os": "linux",
        "rootfs": {"type": "layers", "diff_ids": [layer["digest"]]},
    }).encode())
    manifest = {
        "schemaVersion": 2, "mediaType": OCI_MANIFEST,
        "config": {"mediaType": "application/vnd.oci.image.config.v1+json", **config},
        "layers": [{"mediaType": "application/vnd.oci.image.layer.v1.tar", **layer}],
    }
    put_manifest(REPO, tag, OCI_MANIFEST, json.dumps(manifest).encode())


ROUTE = re.compile(r"^/v2/(?P<repo>.+)/(?P<kind>blobs|manifests|tags)/(?P<ref>.*)$")


class Registry(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def reply(self, code, body=b"", headers=None):
        self.send_response(code)
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def body(self):
        return self.rfile.read(int(self.headers.get("Content-Length") or 0))

    def route(self):
        url = urlsplit(self.path)
        if url.path in ("/v2", "/v2/"):
            return "base", None, None, {}
        m = ROUTE.match(url.path)
        if not m:
            return None, None, None, {}
        return m["kind"], m["repo"], m["ref"], parse_qs(url.query)

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        kind, repo, ref, _ = self.route()
        if kind == "base":
            return self.reply(HTTPStatus.OK, b"{}")
        if kind == "blobs" and ref in blobs:
            return self.reply(HTTPStatus.OK, blobs[ref], {
                "Content-Type": "application/octet-stream",
                "Docker-Content-Digest": ref})
        if kind == "manifests":
            d = ref if ref.startswith("sha256:") else tags.get((repo, ref))
            if (repo, d) in manifests:
                media_type, data = manifests[(repo, d)]
                return self.reply(HTTPStatus.OK, data, {
                    "Content-Type": media_type, "Docker-Content-Digest": d})
        if kind == "tags" and ref == "list":
            names = sorted(t for r, t in tags if r == repo)
            return self.reply(HTTPStatus.OK, json.dumps({"name": repo, "tags": names}).encode(),
                              {"Content-Type": "application/json"})
        return self.reply(HTTPStatus.NOT_FOUND, b'{"errors":[{"code":"NOT_FOUND"}]}',
                          {"Content-Type": "application/json"})

    def do_POST(self):
        kind, repo, ref, query = self.route()
        if kind != "blobs" or not ref.startswith("uploads"):
            return self.reply(HTTPStatus.NOT_FOUND)
        data = self.body()
        if "digest" in query:  # monolithic upload
            d = put_blob(data)["digest"]
            return self.reply(HTTPStatus.CREATED, headers={
                "Location": f"/v2/{repo}/blobs/{d}", "Docker-Content-Digest": d})
        upload = uuid.uuid4().hex
        uploads[upload] = bytearray(data)
        return self.reply(HTTPStatus.ACCEPTED, headers={
            "Location": f"/v2/{repo}/blobs/uploads/{upload}", "Range": "0-0"})

    def do_PATCH(self):
        kind, repo, ref, _ = self.route()
        upload = ref.removeprefix("uploads/")
        if kind != "blobs" or upload not in uploads:
            return self.reply(HTTPStatus.NOT_FOUND)
        uploads[upload] += self.body()
        return self.reply(HTTPStatus.ACCEPTED, headers={
            "Location": f"/v2/{repo}/blobs/uploads/{upload}",
            "Range": f"0-{max(len(uploads[upload]) - 1, 0)}"})

    def do_PUT(self):
        kind, repo, ref, query = self.route()
        if kind == "manifests":
            media_type = self.headers.get("Content-Type", OCI_MANIFEST)
            d = put_manifest(repo, ref, media_type, self.body())
            return self.reply(HTTPStatus.CREATED, headers={
                "Location": f"/v2/{repo}/manifests/{d}", "Docker-Content-Digest": d})
        upload = ref.removeprefix("uploads/")
        if kind != "blobs" or upload not in uploads:
            return self.reply(HTTPStatus.NOT_FOUND)
        data = bytes(uploads.pop(upload) + self.body())
        want = query.get("digest", [""])[0]
        if digest(data) != want:
            return self.reply(HTTPStatus.BAD_REQUEST, b'{"errors":[{"code":"DIGEST_INVALID"}]}',
                              {"Content-Type": "application/json"})
        put_blob(data)
        return self.reply(HTTPStatus.CREATED, headers={
            "Location": f"/v2/{repo}/blobs/{want}", "Docker-Content-Digest": want})


def main():
    seed("signed")
    seed("unsigned")
    server = ThreadingHTTPServer(("127.0.0.1", 0), Registry)
    with open(sys.argv[1], "w") as f:
        f.write(str(server.server_address[1]))
    server.serve_forever()


if __name__ == "__main__":
    main()
