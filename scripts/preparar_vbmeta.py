#!/usr/bin/env python3
"""Copia um vbmeta AVB e define as flags de verity/verification como 3."""

from __future__ import annotations

import argparse
import hashlib
import shutil
from pathlib import Path

FLAGS_OFFSET = 0x78
DISABLE_VERITY_AND_VERIFICATION = 3


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path, help="imagem vbmeta original compatível")
    parser.add_argument("output", type=Path, help="nova imagem modificada")
    args = parser.parse_args()

    source = args.input.resolve()
    destination = args.output.resolve()
    if source == destination:
        raise SystemExit("recusando alterar a imagem de origem diretamente")

    with source.open("rb") as image:
        if image.read(4) != b"AVB0":
            raise SystemExit("a entrada não é uma imagem vbmeta AVB")
        image.seek(FLAGS_OFFSET)
        old_flags = int.from_bytes(image.read(4), "big")

    if old_flags not in (0, DISABLE_VERITY_AND_VERIFICATION):
        raise SystemExit(f"flags AVB existentes inesperadas: {old_flags}")

    shutil.copyfile(source, destination)
    with destination.open("r+b") as image:
        image.seek(FLAGS_OFFSET)
        image.write(DISABLE_VERITY_AND_VERIFICATION.to_bytes(4, "big"))

    print(f"sha256_origem={sha256(source)}")
    print(f"sha256_saida={sha256(destination)}")
    print("flags_avb=3")


if __name__ == "__main__":
    main()
