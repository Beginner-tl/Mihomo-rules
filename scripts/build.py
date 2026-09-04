#!/usr/bin/env python3
"""Build a downstream Mihomo rule source and publish readable TXT companions."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import Request, urlopen

import yaml


ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = ROOT / "scripts" / "sources.yaml"
DIST = ROOT / "dist" / "mihomo"
WORK = ROOT / ".mihomo" / "work"


def log(message: str) -> None:
    print(f"[rules] {message}", flush=True)


def run(command: list[str], capture: bool = False) -> str:
    log("$ " + " ".join(command))
    completed = subprocess.run(
        command,
        cwd=ROOT,
        check=True,
        text=True,
        capture_output=capture,
    )
    return completed.stdout.strip() if capture else ""


def resolve_mihomo() -> str:
    configured = os.environ.get("MIHOMO_BIN", "mihomo")
    candidate = Path(configured)
    if candidate.is_absolute() or "/" in configured or "\\" in configured:
        return str(candidate.resolve())
    return shutil.which(configured) or configured


def fetch_bytes(url: str) -> bytes:
    request = Request(
        url,
        headers={
            "User-Agent": "Beginner-tl/clash-rules",
            "Accept": "*/*",
        },
    )
    with urlopen(request, timeout=180) as response:
        return response.read()


def fetch_text(url: str) -> str:
    return fetch_bytes(url).decode("utf-8")


def write_binary(url: str, destination: Path) -> None:
    data = fetch_bytes(url)
    if len(data) < 32:
        raise RuntimeError(f"downloaded file is unexpectedly small: {url}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(data)
    log(f"downloaded {destination.relative_to(ROOT)} ({len(data)} bytes)")


def read_entries(text: str) -> list[str]:
    entries: set[str] = set()
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or line.startswith("//"):
            continue
        entries.add(line)
    return sorted(entries)


def read_local_entries(files: list[str]) -> list[str]:
    entries: set[str] = set()
    for relative in files:
        path = ROOT / relative
        if not path.is_file():
            raise FileNotFoundError(f"custom rule file not found: {relative}")
        entries.update(read_entries(path.read_text(encoding="utf-8")))
    return sorted(entries)


def write_readable_txt(
    destination: Path,
    name: str,
    entries: list[str],
    note: str,
) -> None:
    lines = [
        f"# NAME: {name}",
        f"# TOTAL: {len(entries)}",
        f"# NOTE: {note}",
        "",
        *entries,
        "",
    ]
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text("\n".join(lines), encoding="utf-8")


def compile_mrs(
    name: str,
    behavior: str,
    entries: list[str],
    mihomo: str,
    note: str,
) -> int:
    output_dir = DIST / ("domain" if behavior == "domain" else "ip")
    output_dir.mkdir(parents=True, exist_ok=True)
    write_readable_txt(output_dir / f"{name}.txt", name, entries, note)

    if not entries:
        log(f"skip {name}.mrs: no entries; kept readable TXT")
        return 0

    payload = WORK / f"{name}.yaml"
    output = output_dir / f"{name}.mrs"
    payload.write_text(
        yaml.safe_dump(
            {"payload": entries},
            allow_unicode=True,
            sort_keys=False,
        ),
        encoding="utf-8",
    )
    run([mihomo, "convert-ruleset", behavior, "yaml", str(payload), str(output)])
    if not output.is_file() or output.stat().st_size < 32:
        raise RuntimeError(f"mihomo produced an invalid MRS: {output}")
    log(f"compiled {output.relative_to(ROOT)} ({len(entries)} entries)")
    return len(entries)


def copy_base_rules(upstream_dir: Path, artifact_root: str) -> tuple[int, int]:
    copied_mrs = 0
    copied_txt = 0
    source_root = upstream_dir / artifact_root

    for behavior in ("domain", "ip"):
        source_dir = source_root / behavior
        target_dir = DIST / behavior
        target_dir.mkdir(parents=True, exist_ok=True)

        for source in sorted(source_dir.glob("*.mrs")):
            shutil.copy2(source, target_dir / source.name)
            copied_mrs += 1

        # Rebuild readable TXT files so published metadata does not carry
        # upstream author fields; the rule entries themselves are preserved.
        for source in sorted(source_dir.glob("*.txt")):
            entries = read_entries(source.read_text(encoding="utf-8"))
            write_readable_txt(
                target_dir / source.name,
                source.stem,
                entries,
                "base rule entries",
            )
            copied_txt += 1

    return copied_mrs, copied_txt


def main() -> None:
    config = yaml.safe_load(CONFIG_PATH.read_text(encoding="utf-8"))
    upstream = config["upstream"]
    mihomo = resolve_mihomo()

    if DIST.exists():
        shutil.rmtree(DIST)
    if WORK.exists():
        shutil.rmtree(WORK)
    WORK.mkdir(parents=True, exist_ok=True)

    upstream_dir = WORK / "base-rules"
    run(
        [
            "git",
            "clone",
            "--depth",
            "1",
            "--single-branch",
            "--branch",
            upstream["branch"],
            upstream["repo"],
            str(upstream_dir),
        ]
    )
    upstream_commit = run(
        ["git", "-C", str(upstream_dir), "rev-parse", "HEAD"],
        capture=True,
    )
    mirrored_mrs, mirrored_txt = copy_base_rules(
        upstream_dir,
        upstream.get("artifact_root", "mihomo"),
    )
    log(
        f"mirrored base rules: {mirrored_mrs} MRS, "
        f"{mirrored_txt} TXT @ {upstream_commit[:12]}"
    )

    domain_dir = DIST / "domain"
    domain_dir.mkdir(parents=True, exist_ok=True)

    # This prebuilt binary remains available for complete game-download matching.
    write_binary(
        upstream["game_download_binary"],
        domain_dir / "GameDownload.mrs",
    )
    write_readable_txt(
        domain_dir / "GameDownload.txt",
        "GameDownload",
        [],
        "prebuilt binary rule; see GameDownloadCustom.txt for local readable additions",
    )

    derived_count = 0
    for item in config.get("derived", []):
        entries = set(read_entries(fetch_text(item["source_url"])))
        entries.update(read_local_entries(item.get("files", [])))
        derived_count += compile_mrs(
            item["name"],
            item["behavior"],
            sorted(entries),
            mihomo,
            "derived rule entries",
        )

    custom_counts: dict[str, int] = {}
    for item in config.get("custom", []):
        entries = read_local_entries(item.get("files", []))
        custom_counts[item["name"]] = compile_mrs(
            item["name"],
            item["behavior"],
            entries,
            mihomo,
            "local custom rule entries",
        )

    mrs_artifacts = [
        {
            "path": path.relative_to(DIST).as_posix(),
            "bytes": path.stat().st_size,
        }
        for path in sorted(DIST.rglob("*.mrs"))
    ]
    txt_artifacts = [
        {
            "path": path.relative_to(DIST).as_posix(),
            "bytes": path.stat().st_size,
        }
        for path in sorted(DIST.rglob("*.txt"))
    ]

    manifest = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "base_rules": {
            "branch": upstream["branch"],
            "commit": upstream_commit,
        },
        "mirrored_mrs": mirrored_mrs,
        "mirrored_txt": mirrored_txt,
        "derived_entries": derived_count,
        "custom_entries": custom_counts,
        "mrs_artifacts": mrs_artifacts,
        "txt_artifacts": txt_artifacts,
    }
    (DIST / "MANIFEST.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    log(f"done: {len(mrs_artifacts)} MRS and {len(txt_artifacts)} TXT files")


if __name__ == "__main__":
    main()
