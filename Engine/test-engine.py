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


def package(path, *images):
    payload = io.BytesIO()
    with tarfile.open(fileobj=payload, mode="w", format=tarfile.USTAR_FORMAT) as archive:
        for image in images:
            entry = tarfile.TarInfo(image)
            entry.size = 1024
            archive.addfile(entry, io.BytesIO(b"F" * entry.size))
    data = payload.getvalue()
    digest = hashlib.md5(data).hexdigest().encode()
    path.write_bytes(data + digest + b"  firmware.tar\n")
    return path


with tempfile.TemporaryDirectory(prefix="firmdrop-engine-tests-") as temp:
    root = pathlib.Path(temp)
    files = [package(root / f"{slot}_S931BXXU1AYB4_test.tar.md5", image, "meta-data/fota.zip")
             for slot, image in [("BL", "sboot.bin"), ("AP", "boot.img"), ("CP", "modem.bin"), ("HOME_CSC", "cache.img")]]
    args = [part for path in files for part in ("--file", str(path))]
    metadata = [package(root / f"{slot}_S931BXXU1AYB4_meta.tar.md5", "meta-data/fota.zip", "meta-data/super_used_size.txt")
                for slot in ["BL", "AP", "CP", "CSC"]]
    assert "no flashable images" in run("--verify", *[part for path in metadata for part in ("--file", str(path))],
                                         success=False).lower()
    assert "firmdrop-flash/1" in run("--version", success=True)
    run("--verify", "--preserve", *args, success=True)
    # Samsung's HOME_CSC allowlist names vbmeta.img once per package that ships it.
    allowlist = root / "download-list.txt"
    allowlist.write_text("boot.img\nvbmeta.img\nsboot.bin\nvbmeta.img\nmodem.bin\ncache.img\n")
    home = root / "HOME_CSC_S931BXXU1AYB4_list.tar.md5"
    payload = io.BytesIO()
    with tarfile.open(fileobj=payload, mode="w", format=tarfile.USTAR_FORMAT) as archive:
        archive.add(allowlist, arcname="meta-data/download-list.txt")
        entry = tarfile.TarInfo("cache.img")
        entry.size = 1024
        archive.addfile(entry, io.BytesIO(b"F" * entry.size))
    data = payload.getvalue()
    home.write_bytes(data + hashlib.md5(data).hexdigest().encode() + b"  firmware.tar\n")
    listed = [part for path in [*files[:3], home] for part in ("--file", str(path))]
    run("--verify", "--preserve", *listed, success=True)
    assert "--resume" in run("--verify", "--resume", *args, success=False)
    run("--list", "--resume", success=False)
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
print("Engine offline checks passed: valid MD5, corrupt/missing digest, invalid TAR, package metadata, explicit target and prohibited PIT.")
