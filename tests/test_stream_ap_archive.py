#!/usr/bin/env python3
"""Exercise range-based AP archive streaming against a local ZIP fixture."""

import http.server
import io
import pathlib
import subprocess
import sys
import tarfile
import tempfile
import threading
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
STREAMER = ROOT / "scripts" / "stream_ap_archive.py"


def make_fixture() -> tuple[bytes, bytes]:
    tar_buffer = io.BytesIO()
    with tarfile.open(fileobj=tar_buffer, mode="w") as archive:
        payload = b"super image fixture\n"
        member = tarfile.TarInfo("super.img.lz4")
        member.size = len(payload)
        archive.addfile(member, io.BytesIO(payload))
    ap_tar = tar_buffer.getvalue()

    zip_buffer = io.BytesIO()
    with zipfile.ZipFile(zip_buffer, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("BL_test.tar.md5", b"bootloader")
        archive.writestr("AP_A346MUBSGFZG4.tar.md5", ap_tar)
        archive.writestr("CSC_MXO.tar.md5", b"carrier")
    return zip_buffer.getvalue(), ap_tar


class RangeHandler(http.server.BaseHTTPRequestHandler):
    archive: bytes

    def do_HEAD(self):
        self.send_response(200)
        self.send_header("Content-Length", str(len(self.archive)))
        self.send_header(
            "Content-Disposition",
            "attachment; filename=SAMFW.COM_SM-A346M_MXO_A346MUBSGFZG4_fac.zip",
        )
        self.end_headers()

    def do_GET(self):
        value = self.headers.get("Range", "")
        if not value.startswith("bytes="):
            self.send_error(416)
            return
        start_text, end_text = value[6:].split("-", 1)
        start = int(start_text)
        end = int(end_text)
        if start < 0 or end < start or end >= len(self.archive):
            self.send_error(416)
            return
        payload = self.archive[start : end + 1]
        self.send_response(206)
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Content-Range", f"bytes {start}-{end}/{len(self.archive)}")
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, *_args):
        pass


def main() -> int:
    archive_bytes, expected_tar = make_fixture()
    RangeHandler.archive = archive_bytes
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), RangeHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(
                [sys.executable, str(STREAMER), f"http://127.0.0.1:{server.server_port}/firmware.zip"],
                cwd=directory,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            if result.returncode != 0:
                sys.stderr.write(result.stderr.decode(errors="replace"))
                return 1
            if result.stdout != expected_tar:
                raise AssertionError("Streamed AP TAR does not match the ZIP entry")
            if pathlib.Path(directory, "ap_code.txt").read_text().strip() != "A346MUBSGFZG4":
                raise AssertionError("AP build code was not parsed from Content-Disposition")
            if pathlib.Path(directory, "csc_code.txt").read_text().strip() != "MXO":
                raise AssertionError("CSC code was not parsed from Content-Disposition")
    finally:
        server.shutdown()
        server.server_close()
        thread.join()
    print("[OK] Ranged AP archive streaming checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
