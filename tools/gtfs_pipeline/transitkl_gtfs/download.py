from __future__ import annotations

import os
import urllib.request
from pathlib import Path
from zipfile import ZipFile


def download_feed(
    url: str,
    output_path: str | Path,
    *,
    overwrite: bool = False,
) -> Path:
    output = Path(output_path).resolve()
    if output.exists() and not overwrite:
        raise FileExistsError(f"Output already exists: {output}. Use --overwrite to replace it.")

    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(output.suffix + ".part")
    if temporary.exists():
        temporary.unlink()

    request = urllib.request.Request(
        url,
        headers={"User-Agent": "TransitKL-Capstone-GTFS-Pipeline/0.1"},
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            with temporary.open("wb") as stream:
                while block := response.read(1024 * 1024):
                    stream.write(block)

        with ZipFile(temporary) as archive:
            bad_member = archive.testzip()
            if bad_member:
                raise ValueError(f"Downloaded ZIP contains a corrupt file: {bad_member}")
            if not any(name.lower().endswith("stops.txt") for name in archive.namelist()):
                raise ValueError("Downloaded ZIP does not contain stops.txt")

        os.replace(temporary, output)
        return output
    except Exception:
        if temporary.exists():
            temporary.unlink()
        raise
