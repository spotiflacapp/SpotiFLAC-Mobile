#!/usr/bin/env python3
"""Check that a release APK contains the selected native backend."""

import argparse
import hashlib
import struct
import sys
import zipfile
import zlib
from pathlib import Path
from typing import Iterable, Sequence, Tuple


ABI_LAYOUT = {
    "arm64-v8a": (2, 183),
    "armeabi-v7a": (1, 40),
}
CORE_LIBRARIES = ("libapp.so", "libflutter.so")
DISCORD_LIBRARIES = ("libspotiflac_discord.so", "libdiscord_partner_sdk.so")


class AuditError(Exception):
    pass


def parse_abis(raw: str) -> Tuple[str, ...]:
    abis = tuple(part.strip() for part in raw.split(",") if part.strip())
    if not abis:
        raise AuditError("--abis must contain at least one ABI")
    unknown = sorted(set(abis) - set(ABI_LAYOUT))
    if unknown:
        raise AuditError("unsupported ABI(s): " + ", ".join(unknown))
    if len(set(abis)) != len(abis):
        raise AuditError("--abis contains a duplicate ABI")
    return abis


def artifact_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while True:
            chunk = stream.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def required_entry(infos: Sequence[zipfile.ZipInfo], path: str) -> zipfile.ZipInfo:
    matches = [info for info in infos if info.filename == path and not info.is_dir()]
    if not matches:
        raise AuditError("missing APK entry: " + path)
    if len(matches) > 1:
        raise AuditError("duplicate APK entry: " + path)
    return matches[0]


def check_abi_directories(names: Iterable[str], expected: Sequence[str]) -> None:
    actual = set()
    for name in names:
        parts = name.split("/")
        if len(parts) >= 3 and parts[0] == "lib" and parts[1]:
            actual.add(parts[1])
    unexpected = sorted(actual - set(expected))
    if unexpected:
        raise AuditError("unexpected lib ABI directory(s): " + ", ".join(unexpected))


def check_archive_integrity(
    zf: zipfile.ZipFile, infos: Sequence[zipfile.ZipInfo]
) -> None:
    # Reading to EOF checks both decompression and CRC, including resources and
    # bytes beyond the ELF headers inspected by the native payload audit.
    for info in infos:
        if info.is_dir():
            continue
        try:
            with zf.open(info, "r") as stream:
                while stream.read(1024 * 1024):
                    pass
        except (zipfile.BadZipFile, zlib.error, EOFError) as exc:
            raise AuditError(f"corrupt APK entry {info.filename}: {exc}") from exc


def check_elf(data: bytes, path: str, abi: str) -> None:
    expected_class, expected_machine = ABI_LAYOUT[abi]
    if len(data) < 20 or data[:4] != b"\x7fELF":
        raise AuditError(path + ": invalid ELF header")
    if data[4] != expected_class:
        raise AuditError(f"{path}: ELF class {data[4]} does not match {abi}")
    if data[5] != 1:
        raise AuditError(path + ": Android ARM libraries must be little-endian")
    machine = struct.unpack_from("<H", data, 18)[0]
    if machine != expected_machine:
        raise AuditError(f"{path}: e_machine {machine} does not match {abi}")


def check_backend_markers(
    zf: zipfile.ZipFile,
    infos: Sequence[zipfile.ZipInfo],
    backend: str,
) -> None:
    names = [info.filename for info in infos]
    if backend == "rust":
        if any(name.rsplit("/", 1)[-1] == "libgojni.so" for name in names):
            raise AuditError("Rust APK contains forbidden libgojni.so")
        go_resource = next(
            (name for name in names if name.startswith(("gobackend/", "go/"))), None
        )
        if go_resource is not None:
            raise AuditError(f"Rust APK contains forbidden Go resource: {go_resource}")
        for info in infos:
            if info.is_dir() or not info.filename.endswith(".dex"):
                continue
            data = zf.read(info)
            marker = next(
                (marker for marker in (b"Lgobackend/", b"Lgo/") if marker in data), None
            )
            if marker is not None:
                raise AuditError(f"Rust APK DEX {info.filename} contains {marker.decode()}")
    elif any(
        name.rsplit("/", 1)[-1] == "libspotiflac_mobile.so" for name in names
    ):
        raise AuditError("Go APK contains forbidden libspotiflac_mobile.so")


def audit(path: Path, backend: str, abis: Sequence[str], discord_sdk: bool = False) -> str:
    if not path.is_file():
        raise AuditError("APK is not a regular file: " + str(path))
    digest = artifact_sha256(path)
    try:
        with zipfile.ZipFile(path, "r") as zf:
            infos = zf.infolist()
            check_archive_integrity(zf, infos)
            names = [info.filename for info in infos]
            for name in names:
                if not discord_sdk and name.rsplit("/", 1)[-1] == "libdiscord_partner_sdk.so":
                    raise AuditError("APK unexpectedly contains Discord SDK library: " + name)
            if "assets/flutter_assets/kernel_blob.bin" in names:
                raise AuditError("debug APK contains assets/flutter_assets/kernel_blob.bin")
            check_abi_directories(names, abis)
            check_backend_markers(zf, infos, backend)
            backend_library = (
                "libspotiflac_mobile.so" if backend == "rust" else "libgojni.so"
            )
            libraries = CORE_LIBRARIES + (backend_library,)
            if backend == "rust":
                libraries += ("libjnidispatch.so",)
            if discord_sdk:
                libraries += DISCORD_LIBRARIES
            for abi in abis:
                for library in libraries:
                    entry_path = f"lib/{abi}/{library}"
                    entry = required_entry(infos, entry_path)
                    with zf.open(entry, "r") as stream:
                        check_elf(stream.read(20), entry_path, abi)
    except zipfile.BadZipFile as exc:
        raise AuditError("invalid APK/ZIP: " + str(exc)) from exc
    return digest


def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path, help="release APK to audit")
    parser.add_argument("--backend", choices=("rust", "go"), required=True)
    parser.add_argument("--abis", required=True, metavar="ABI[,ABI...]", help="expected APK ABIs")
    parser.add_argument("--discord-sdk", action="store_true", help="require Discord SDK and bridge in every ABI")
    return parser


def main(argv: Sequence[str] = None) -> int:
    args = make_parser().parse_args(argv)
    try:
        abis = parse_abis(args.abis)
        digest = audit(args.apk, args.backend, abis, args.discord_sdk)
    except (AuditError, OSError) as exc:
        print("error: " + str(exc), file=sys.stderr)
        return 1
    print(f"OK sha256={digest} backend={args.backend} abis={','.join(abis)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
