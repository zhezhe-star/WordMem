#!/usr/bin/env python3
"""Build WordMem's compact, read-only ECDICT SQLite resource."""

from __future__ import annotations

import argparse
import csv
import hashlib
import os
import re
import sqlite3
import subprocess
import sys
import unicodedata
from dataclasses import dataclass
from pathlib import Path


LEARNER_TAGS = {"zk", "gk", "cet4", "cet6", "ky", "toefl", "ielts", "gre"}
SELECTION = "learner tags or frequency <= 50000"
SIZE_BUDGET = 25 * 1024 * 1024


@dataclass(frozen=True)
class Entry:
    normalized_word: str
    word: str
    phonetic: str
    translation: str
    definition: str
    pos: str
    exchange: str
    tags: str
    bnc: int
    frq: int
    collins: int
    oxford: int
    rank: int


def normalized_key(value: str) -> str:
    value = value.strip().replace("\u2019", "'").replace("\u2018", "'")
    decomposed = unicodedata.normalize("NFKD", value)
    without_marks = "".join(char for char in decomposed if not unicodedata.combining(char))
    folded = unicodedata.normalize("NFKC", without_marks).casefold()
    return folded.strip(" \"'!.,;:?!()[]{}")


def source_revision(source: Path) -> str:
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=source, text=True
        ).strip()
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def parse_lemma_groups(path: Path) -> list[tuple[str, list[str]]]:
    groups: list[tuple[str, list[str]]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith(";") or " -> " not in stripped:
            continue

        left, right = stripped.split(" -> ", 1)
        lemma = normalized_key(left.split("/")[0])
        forms = [form.strip() for form in right.split(",") if form.strip()]
        if lemma and forms:
            groups.append((lemma, forms))
    return groups


def load_entries(csv_path: Path) -> tuple[list[Entry], dict[str, Entry]]:
    best_by_key: dict[str, Entry] = {}

    with csv_path.open(newline="", encoding="utf-8") as source:
        for row in csv.DictReader(source):
            word = (row["word"] or "").strip()
            translation = (row["translation"] or "").strip()
            if not word or not translation or len(word) > 40:
                continue

            bnc = _integer(row["bnc"])
            frq = _integer(row["frq"])
            rank = min((value for value in (bnc, frq) if value > 0), default=999_999)
            tags = " ".join(sorted(filter(None, (row["tag"] or "").split())))
            if not ((set(tags.split()) & LEARNER_TAGS) or rank <= 50_000):
                continue

            entry = Entry(
                normalized_word=normalized_key(word),
                word=word,
                phonetic=(row["phonetic"] or "").strip(),
                translation=translation,
                definition=(row["definition"] or "").strip(),
                pos=(row["pos"] or "").strip(),
                exchange=(row["exchange"] or "").strip(),
                tags=tags,
                bnc=bnc,
                frq=frq,
                collins=_integer(row["collins"]),
                oxford=_integer(row["oxford"]),
                rank=rank,
            )
            previous = best_by_key.get(entry.normalized_word)
            if previous is None or entry.rank < previous.rank:
                best_by_key[entry.normalized_word] = entry

    entries = sorted(best_by_key.values(), key=lambda entry: entry.normalized_word)
    return entries, best_by_key


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _integer(value: str | None) -> int:
    try:
        return int(value or "0")
    except (TypeError, ValueError):
        return 0


def lemma_mappings(
    groups: list[tuple[str, list[str]]], entries: dict[str, Entry]
) -> tuple[dict[str, str], list[tuple[str, str, str, str]]]:
    form_ranks: dict[str, int] = {}
    lookups: dict[str, str] = {}
    forms: list[tuple[str, str, str, str]] = []
    seen_forms: set[tuple[str, str, str]] = set()

    for lemma, raw_forms in groups:
        lemma_key = normalized_key(lemma)
        entry = entries.get(lemma_key)
        if entry is None:
            continue

        for raw_form in raw_forms:
            form_key = normalized_key(raw_form)
            if not form_key or form_key == lemma_key:
                continue

            previous_rank = form_ranks.get(form_key)
            if previous_rank is None or entry.rank < previous_rank:
                lookups[form_key] = lemma_key
                form_ranks[form_key] = entry.rank

            identity = (lemma_key, form_key, "inflection")
            if identity not in seen_forms:
                seen_forms.add(identity)
                forms.append((lemma_key, form_key, "inflection", raw_form.strip()))

    return lookups, forms


def create_database(output: Path, entries: list[Entry], source: Path, source_profile: dict[str, str]) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(output.suffix + ".tmp")
    temporary.unlink(missing_ok=True)

    database = sqlite3.connect(temporary)
    try:
        database.execute("pragma journal_mode=off")
        database.execute("pragma synchronous=off")
        database.execute("pragma temp_store=memory")
        database.execute("pragma cache_size=-32000")
        database.executescript(
            """
            pragma user_version=1;
            create table entries (
                normalized_word text primary key,
                word text not null,
                phonetic text,
                translation text not null,
                definition text,
                pos text,
                exchange text,
                tags text,
                bnc integer,
                frq integer,
                collins integer,
                oxford integer,
                rank integer not null
            ) without rowid;

            create table lemma_lookup (
                input_key text primary key,
                normalized_lemma text not null
            ) without rowid;

            create table forms (
                normalized_lemma text not null,
                normalized_form text not null,
                kind text not null,
                value text not null,
                primary key (normalized_lemma, normalized_form, kind)
            ) without rowid;

            create index idx_entries_rank on entries(rank);
            create index idx_forms_lemma on forms(normalized_lemma);
            create table dictionary_meta (
                key text primary key,
                value text not null
            ) without rowid;
            """
        )

        database.executemany(
            "insert into entries values (?,?,?,?,?,?,?,?,?,?,?,?,?)",
            [
                (
                    entry.normalized_word,
                    entry.word,
                    entry.phonetic,
                    entry.translation,
                    entry.definition,
                    entry.pos,
                    entry.exchange,
                    entry.tags,
                    entry.bnc,
                    entry.frq,
                    entry.collins,
                    entry.oxford,
                    entry.rank,
                )
                for entry in entries
            ],
        )

        lookups, forms = lemma_mappings(
            parse_lemma_groups(source / "lemma.en.txt"),
            {entry.normalized_word: entry for entry in entries},
        )
        database.executemany(
            "insert into lemma_lookup values (?,?)", sorted(lookups.items())
        )
        database.executemany(
            "insert into forms values (?,?,?,?)", sorted(forms)
        )
        database.executemany(
            "insert into dictionary_meta values (?,?)",
            [
                ("pipelineVersion", "3"),
                ("schemaVersion", "1"),
                ("source", "ECDICT"),
                ("sourceRevision", source_revision(source)),
                ("sourceLicense", "MIT"),
                ("selection", SELECTION),
                ("entryCount", str(len(entries))),
                ("lemmaCount", str(len(lookups))),
                ("wordFormCount", str(len(forms))),
                ("curatedLemmaPriorityKeys", "running"),
                *sorted(source_profile.items()),
            ],
        )

        database.commit()
        database.execute("vacuum")
        database.execute("analyze")
    finally:
        database.close()

    size = temporary.stat().st_size
    if size > SIZE_BUDGET:
        temporary.unlink(missing_ok=True)
        raise RuntimeError(f"Dictionary size {size} exceeds {SIZE_BUDGET} bytes")

    os.replace(temporary, output)
    license_source = source / "LICENSE"
    license_output = output.with_name("ECDICT-LICENSE.txt")
    license_output.write_bytes(license_source.read_bytes())
    print(
        f"Wrote {output}: {len(entries)} entries, "
        f"{size / 1024 / 1024:.2f} MiB"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="Checked-out ECDICT repository")
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("WordMem/Resources/Dictionary.sqlite"),
    )
    arguments = parser.parse_args()

    csv_path = arguments.source / "ecdict.csv"
    lemma_path = arguments.source / "lemma.en.txt"
    license_path = arguments.source / "LICENSE"
    if not csv_path.is_file() or not lemma_path.is_file() or not license_path.is_file():
        raise FileNotFoundError("ECDICT source must contain ecdict.csv, lemma.en.txt, and LICENSE")

    entries, best_by_key = load_entries(csv_path)
    with csv_path.open(newline="", encoding="utf-8") as source_csv:
        source_row_count = max(0, sum(1 for _ in csv.DictReader(source_csv)))

    source_profile = {
        "sourceCsvSHA256": sha256(csv_path),
        "sourceCsvRowCount": str(source_row_count),
        "sourceLemmaSHA256": sha256(lemma_path),
        "sourceLicenseSHA256": sha256(license_path),
        "selectedEntryCount": str(len(entries)),
        "filteredRowCount": str(source_row_count - len(entries)),
    }
    create_database(arguments.output, entries, arguments.source, source_profile)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
