from __future__ import annotations

import csv
import hashlib
import io
from pathlib import Path
from zipfile import BadZipFile, ZipFile


class FeedSource:
    """Read GTFS CSV files from either a ZIP archive or a directory."""

    def __init__(self, path: str | Path) -> None:
        self.path = Path(path).resolve()
        if not self.path.exists():
            raise FileNotFoundError(f"GTFS input does not exist: {self.path}")
        if not self.path.is_dir() and not self.path.is_file():
            raise ValueError(f"GTFS input must be a ZIP file or directory: {self.path}")

        self._members = self._discover_members()

    @property
    def file_names(self) -> list[str]:
        return sorted(self._members)

    def has_file(self, file_name: str) -> bool:
        return file_name.lower() in self._members

    def read_rows(self, file_name: str) -> list[dict[str, str]]:
        key = file_name.lower()
        if key not in self._members:
            raise FileNotFoundError(f"{file_name} is not present in {self.path}")

        if self.path.is_dir():
            member = self._members[key]
            assert isinstance(member, Path)
            with member.open("r", encoding="utf-8-sig", newline="") as stream:
                return self._parse_csv(stream, file_name)

        try:
            with ZipFile(self.path) as archive:
                with archive.open(str(self._members[key]), "r") as raw_stream:
                    with io.TextIOWrapper(
                        raw_stream,
                        encoding="utf-8-sig",
                        newline="",
                    ) as stream:
                        return self._parse_csv(stream, file_name)
        except BadZipFile as error:
            raise ValueError(f"Invalid GTFS ZIP archive: {self.path}") from error

    def sha256(self) -> str:
        digest = hashlib.sha256()
        if self.path.is_file():
            with self.path.open("rb") as stream:
                for block in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(block)
            return digest.hexdigest()

        for file_name in self.file_names:
            digest.update(file_name.encode("utf-8"))
            member = self._members[file_name]
            assert isinstance(member, Path)
            with member.open("rb") as stream:
                for block in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(block)
        return digest.hexdigest()

    def _discover_members(self) -> dict[str, Path | str]:
        if self.path.is_dir():
            return {
                child.name.lower(): child
                for child in self.path.iterdir()
                if child.is_file()
                and child.suffix.lower() == ".txt"
                and not child.name.startswith("._")
            }

        try:
            with ZipFile(self.path) as archive:
                members: dict[str, str] = {}
                for member in archive.namelist():
                    if member.endswith("/"):
                        continue
                    name = Path(member).name.lower()
                    is_metadata = name.startswith("._") or "__macosx" in member.lower().split("/")
                    if name.endswith(".txt") and not is_metadata and name not in members:
                        members[name] = member
                return members
        except BadZipFile as error:
            raise ValueError(f"Invalid GTFS ZIP archive: {self.path}") from error

    @staticmethod
    def _parse_csv(stream: io.TextIOBase, file_name: str) -> list[dict[str, str]]:
        reader = csv.DictReader(stream)
        if reader.fieldnames is None:
            raise ValueError(f"{file_name} has no CSV header")
        return [
            {
                str(key).strip(): (value or "").strip()
                for key, value in row.items()
                if key is not None
            }
            for row in reader
        ]
