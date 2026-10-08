"""Verify native backend payloads and optional Discord SDKs in release APKs."""

import struct
import tempfile
import unittest
import zipfile
from pathlib import Path

import check_backend_apk as checker


class BackendApkAuditTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.apk = Path(directory.name) / "release.apk"
        self.entries = {"classes.dex": b"backend classes"}
        for abi, (elf_class, machine) in checker.ABI_LAYOUT.items():
            header = bytearray(20)
            header[:6] = b"\x7fELF" + bytes([elf_class, 1])
            struct.pack_into("<H", header, 18, machine)
            for library in checker.CORE_LIBRARIES + (
                "libspotiflac_mobile.so", "libjnidispatch.so",
            ):
                self.entries[f"lib/{abi}/{library}"] = bytes(header)

    def audit(self, abis=("arm64-v8a", "armeabi-v7a"), discord_sdk=False):
        with zipfile.ZipFile(self.apk, "w") as zf:
            for name, data in self.entries.items():
                zf.writestr(name, data)
        return checker.audit(self.apk, "rust", abis, discord_sdk)

    def test_universal_passes(self):
        self.assertEqual(len(self.audit()), 64)

    def test_split_apks_pass(self):
        original = self.entries.copy()
        for abi in checker.ABI_LAYOUT:
            self.entries = {name: data for name, data in original.items()
                            if not name.startswith("lib/") or name.startswith(f"lib/{abi}/")}
            self.assertEqual(len(self.audit((abi,))), 64)

    def test_compressed_assets_pass(self):
        self.entries["assets/flutter_assets/test.txt"] = b"resource contents" * 1024
        with zipfile.ZipFile(self.apk, "w", compression=zipfile.ZIP_DEFLATED) as zf:
            for name, data in self.entries.items():
                zf.writestr(name, data)
        self.assertEqual(
            len(checker.audit(self.apk, "rust", tuple(checker.ABI_LAYOUT))), 64
        )

    def entry_data_offset(self, name):
        with zipfile.ZipFile(self.apk) as zf:
            info = zf.getinfo(name)
        with self.apk.open("rb") as stream:
            stream.seek(info.header_offset + 26)
            name_length, extra_length = struct.unpack("<HH", stream.read(4))
        return info.header_offset + 30 + name_length + extra_length

    def test_corrupt_deflate_asset_fails_with_entry_name(self):
        self.audit()
        path = "assets/flutter_assets/test.txt"
        with zipfile.ZipFile(self.apk, "a", compression=zipfile.ZIP_DEFLATED) as zf:
            zf.writestr(path, b"resource contents" * 1024)
        offset = self.entry_data_offset(path)
        with self.apk.open("r+b") as stream:
            stream.seek(offset)
            stream.write(b"\x07")  # Reserved DEFLATE block type.
        with self.assertRaisesRegex(checker.AuditError, "corrupt APK entry " + path):
            checker.audit(self.apk, "rust", tuple(checker.ABI_LAYOUT))

    def test_corrupt_library_past_valid_elf_header_fails(self):
        path = "lib/arm64-v8a/libapp.so"
        self.entries[path] += b"native library contents" * 1024
        self.audit()
        offset = self.entry_data_offset(path)
        with self.apk.open("r+b") as stream:
            stream.seek(offset + 1024)
            stream.write(b"\xff")
        with self.assertRaisesRegex(checker.AuditError, "corrupt APK entry " + path):
            checker.audit(self.apk, "rust", tuple(checker.ABI_LAYOUT))

    def test_missing_backend_in_either_abi_fails(self):
        for abi in checker.ABI_LAYOUT:
            for library in ("libspotiflac_mobile.so", "libjnidispatch.so"):
                with self.subTest(abi=abi, library=library):
                    path = f"lib/{abi}/{library}"
                    data = self.entries.pop(path)
                    with self.assertRaisesRegex(checker.AuditError, "missing APK entry"):
                        self.audit()
                    self.entries[path] = data

    def test_wrong_architecture_fails(self):
        self.entries["lib/armeabi-v7a/libspotiflac_mobile.so"] = self.entries[
            "lib/arm64-v8a/libspotiflac_mobile.so"
        ]
        with self.assertRaisesRegex(checker.AuditError, "ELF class"):
            self.audit()

    def test_disabled_sdk_cannot_leak_from_build_cache(self):
        for abi in checker.ABI_LAYOUT:
            path = f"lib/{abi}/libdiscord_partner_sdk.so"
            self.entries[path] = self.entries[f"lib/{abi}/libapp.so"]
            with self.assertRaisesRegex(checker.AuditError, "unexpectedly contains Discord"):
                self.audit()
            del self.entries[path]

    def test_enabled_sdk_requires_both_libraries_for_each_abi(self):
        for abi in checker.ABI_LAYOUT:
            for library in checker.DISCORD_LIBRARIES:
                self.entries[f"lib/{abi}/{library}"] = self.entries[f"lib/{abi}/libapp.so"]
        self.assertEqual(len(self.audit(discord_sdk=True)), 64)
        del self.entries["lib/armeabi-v7a/libdiscord_partner_sdk.so"]
        with self.assertRaisesRegex(checker.AuditError, "missing APK entry"):
            self.audit(discord_sdk=True)


if __name__ == "__main__":
    unittest.main()
