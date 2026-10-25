#!/usr/bin/env python3
"""Stream the AP TAR from a SamFW ZIP using HTTP range requests."""

from __future__ import annotations

import email.message
import re
import struct
import sys
import urllib.error
import urllib.request
import zipfile
import zlib

CHUNK_SIZE = 1024 * 1024
TAIL_SIZE = 65_557
USER_AGENT = "SamFWDumper/1.0"


def request(url: str, method: str, start: int | None = None, end: int | None = None):
    headers = {"User-Agent": USER_AGENT}
    if start is not None and end is not None:
        headers["Range"] = f"bytes={start}-{end}"
    req = urllib.request.Request(url, headers=headers, method=method)
    try:
        response = urllib.request.urlopen(req, timeout=60)
    except (urllib.error.URLError, TimeoutError) as exc:
        raise RuntimeError(f"Firmware server request failed: {exc}") from exc
    return response


def content_length(url: str) -> int:
    try:
        with request(url, "HEAD") as response:
            value = response.headers.get("Content-Length")
            if value is not None:
                return int(value)
    except (RuntimeError, ValueError):
        pass
    with request(url, "GET", 0, 0) as response:
        content_range = response.headers.get("Content-Range", "")
        match = re.fullmatch(r"bytes 0-0/(\d+)", content_range)
        if response.status != 206 or not match:
            raise RuntimeError("Firmware server does not provide a ranged ZIP download")
        return int(match.group(1))


def fetch_range(url: str, start: int, end: int) -> bytes:
    with request(url, "GET", start, end) as response:
        content_range = response.headers.get("Content-Range", "")
        expected = f"bytes {start}-{end}/"
        if response.status != 206 or not content_range.startswith(expected):
            raise RuntimeError("Firmware server did not honor an HTTP range request")
        data = response.read(end - start + 1)
    if len(data) != end - start + 1:
        raise RuntimeError("Firmware server returned an incomplete byte range")
    return data


def download_name(url: str) -> str:
    with request(url, "HEAD") as response:
        disposition = response.headers.get("Content-Disposition", "")
    message = email.message.Message()
    message["content-disposition"] = disposition
    return message.get_filename() or "firmware.zip"


def stream_entry(url: str, info: zipfile.ZipInfo, total_size: int, out) -> None:
    local_header = fetch_range(url, info.header_offset, info.header_offset + 29)
    fields = struct.unpack("<IHHHHHIIIHH", local_header)
    if fields[0] != 0x04034B50:
        raise RuntimeError("Invalid AP ZIP entry header")
    filename_length, extra_length = fields[-2:]
    data_start = info.header_offset + 30 + filename_length + extra_length
    data_end = data_start + info.compress_size - 1
    if data_start < 0 or data_end >= total_size:
        raise RuntimeError("AP ZIP entry range is outside the firmware archive")

    crc = 0
    output_size = 0
    decompressor = zlib.decompressobj(-15) if info.compress_type == zipfile.ZIP_DEFLATED else None
    if info.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED):
        raise RuntimeError(f"Unsupported AP ZIP compression method: {info.compress_type}")

    with request(url, "GET", data_start, data_end) as response:
        content_range = response.headers.get("Content-Range", "")
        expected = f"bytes {data_start}-{data_end}/"
        if response.status != 206 or not content_range.startswith(expected):
            raise RuntimeError("Firmware server did not honor the AP data range request")
        remaining = info.compress_size
        while remaining:
            chunk = response.read(min(CHUNK_SIZE, remaining))
            if not chunk:
                raise RuntimeError("Firmware server ended the AP download early")
            remaining -= len(chunk)
            decoded = decompressor.decompress(chunk) if decompressor else chunk
            if decoded:
                out.write(decoded)
                output_size += len(decoded)
                crc = zlib.crc32(decoded, crc)
        if decompressor:
            decoded = decompressor.flush()
            if decoded:
                out.write(decoded)
                output_size += len(decoded)
                crc = zlib.crc32(decoded, crc)
            if not decompressor.eof:
                raise RuntimeError("AP ZIP entry ended before the DEFLATE stream completed")

    if output_size != info.file_size or crc & 0xFFFFFFFF != info.CRC:
        raise RuntimeError("AP ZIP entry failed its size or CRC check")


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: stream_ap_archive.py HTTPS_URL", file=sys.stderr)
        return 2
    url = sys.argv[1]
    if not url.startswith("https://") and not re.match(r"^http://127\.0\.0\.1:\d+/", url):
        print("[ERROR] Firmware URL must use HTTPS.", file=sys.stderr)
        return 2

    try:
        size = content_length(url)
        if size < 22:
            raise RuntimeError("Firmware ZIP is too small")
        tail_start = max(0, size - TAIL_SIZE)
        tail = fetch_range(url, tail_start, size - 1)
        with open_zip_index(tail, tail_start, size) as archive:
            candidates = [
                item
                for item in archive.infolist()
                if re.fullmatch(r"AP_.+\.tar(?:\.md5)?", item.filename)
            ]
            if not candidates:
                raise RuntimeError("No AP TAR entry was found in the SamFW ZIP")
            ap_info = max(candidates, key=lambda item: item.file_size)
            source_name = download_name(url)
            stem = source_name.removesuffix(".zip")
            parts = stem.split("_")
            csc = next(
                (part for part in parts if re.fullmatch(r"[A-Z]{3}", part) and part not in {"COM", "SAM", "FAC"}),
                "Unknown",
            )
            ap_code = next((part for part in parts if re.fullmatch(r"[A-Z][A-Z0-9]{11,}", part)), "Unknown")
            with open("csc_code.txt", "w", encoding="utf-8") as output:
                output.write(csc + "\n")
            with open("ap_code.txt", "w", encoding="utf-8") as output:
                output.write(ap_code + "\n")
            print(
                f"[OK] Streaming {ap_info.filename} ({ap_info.file_size} uncompressed bytes) from firmware ZIP.",
                file=sys.stderr,
            )
            stream_entry(url, ap_info, size, sys.stdout.buffer)
    except (OSError, RuntimeError, zipfile.BadZipFile, zipfile.LargeZipFile, struct.error, zlib.error) as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1
    return 0


def open_zip_index(tail: bytes, tail_start: int, total_size: int):
    import tempfile

    indexed_file = tempfile.TemporaryFile()
    indexed_file.truncate(total_size)
    indexed_file.seek(tail_start)
    indexed_file.write(tail)
    indexed_file.seek(0)
    return _ZipIndex(zipfile.ZipFile(indexed_file), indexed_file)


class _ZipIndex:
    def __init__(self, archive: zipfile.ZipFile, file_obj):
        self.archive = archive
        self.file_obj = file_obj

    def __enter__(self):
        return self.archive

    def __exit__(self, *_exc):
        self.archive.close()
        self.file_obj.close()


if __name__ == "__main__":
    raise SystemExit(main())
