#!/usr/bin/env python3
"""Offline integration checks: never open a USB session or write a partition."""
import hashlib
import io
import pathlib
import subprocess
import sys
import tarfile
import tempfile

engine = pathlib.Path(sys.argv[1]).resolve()


def run(*args, success):
    result = subprocess.run([str(engine), *args], capture_output=True, text=True, timeout=30)
    if (result.returncode == 0) != success:
        raise AssertionError(f"Unexpected exit {result.returncode}: {result.stdout}\n{result.stderr}")
    return result.stdout + result.stderr


with tempfile.TemporaryDirectory(prefix="firmdrop-engine-tests-") as temp:
    root = pathlib.Path(temp)
    files = []
    for slot, image in [("BL", "sboot.bin"), ("AP", "boot.img"), ("CP", "modem.bin"), ("HOME_CSC", "cache.img")]:
        path = root / f"{slot}_S931BXXU1AYB4_test.tar.md5"
        payload = io.BytesIO()
        with tarfile.open(fileobj=payload, mode="w", format=tarfile.USTAR_FORMAT) as archive:
            entry = tarfile.TarInfo(image)
            entry.size = 1024
            archive.addfile(entry, io.BytesIO(b"F" * entry.size))
        data = payload.getvalue()
        digest = hashlib.md5(data).hexdigest().encode()
        path.write_bytes(data + digest + b"  firmware.tar\n")
        files.append(path)
    args = [part for path in files for part in ("--file", str(path))]
    assert "firmdrop-flash/1" in run("--version", success=True)
    run("--verify", "--preserve", *args, success=True)
    contents = files[1].read_bytes()
    files[1].write_bytes(contents[:512] + b"X" + contents[513:])
    assert "mismatch" in run("--verify", *args, success=False).lower()
    files[1].write_bytes(contents[:-50])
    run("--verify", *args, success=False)
    files[1].write_bytes(b"invalid tar" * 100)
    run("--verify", *args, success=False)
    run("--flash", success=False)
    run("--probe", success=False)
    run("--flash", "--use-pit", "unused.pit", success=False)
print("Engine offline checks passed: valid MD5, corrupt/missing digest, invalid TAR, explicit target and prohibited PIT.")
