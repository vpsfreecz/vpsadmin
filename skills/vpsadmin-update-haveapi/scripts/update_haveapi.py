#!/usr/bin/env python3
import argparse
import re
import subprocess
import sys
from pathlib import Path


VERSION_RE = r"\d+\.\d+\.\d+"

DEPENDENCY_UPDATES = [
    (
        Path("api/Gemfile"),
        r"(gem ['\"]haveapi['\"], ['\"]~> )" + VERSION_RE + r"(['\"])",
        "haveapi",
    ),
    (
        Path("download_mounter/Gemfile"),
        r"(gem ['\"]haveapi-client['\"], ['\"]~> )" + VERSION_RE + r"(['\"])",
        "haveapi-client",
    ),
    (
        Path("plugins/outage_reports/utils/Gemfile"),
        r"(gem ['\"]haveapi-client['\"], ['\"]~> )" + VERSION_RE + r"(['\"])",
        "haveapi-client",
    ),
    (
        Path("client/vpsadmin-client.gemspec"),
        r"(spec\.add_dependency ['\"]haveapi-client['\"], ['\"]~> )"
        + VERSION_RE
        + r"(['\"])",
        "haveapi-client",
    ),
    (
        Path("notification_templates/vpsadmin-notification-templates.gemspec"),
        r"(s\.add_dependency ['\"]haveapi-client['\"], ['\"]~> )"
        + VERSION_RE
        + r"(['\"])",
        "haveapi-client",
    ),
]


def find_repo_root(start: Path) -> Path:
    for path in [start, *start.parents]:
        if (path / "tools" / "bundix_all.sh").is_file() and (path / "api" / "Gemfile").is_file():
            return path

    raise RuntimeError("could not find vpsAdmin repository root")


def update_file(root: Path, relative_path: Path, pattern: str, version: str) -> bool:
    path = root / relative_path
    original = path.read_text()
    updated, count = re.subn(pattern, r"\g<1>" + version + r"\2", original)

    if count != 1:
        raise RuntimeError(f"{relative_path}: expected one dependency match, found {count}")

    if updated == original:
        return False

    path.write_text(updated)
    return True


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Update vpsAdmin Ruby HaveAPI dependencies and regenerate bundix outputs."
    )
    parser.add_argument("version", help="released HaveAPI version, e.g. 0.28.4")
    parser.add_argument(
        "--skip-bundix",
        action="store_true",
        help="update source dependency files without running tools/bundix_all.sh",
    )
    args = parser.parse_args()

    if not re.fullmatch(VERSION_RE, args.version):
        parser.error("version must have the form MAJOR.MINOR.PATCH")

    root = find_repo_root(Path.cwd().resolve())
    changed = []

    for relative_path, pattern, _name in DEPENDENCY_UPDATES:
        if update_file(root, relative_path, pattern, args.version):
            changed.append(str(relative_path))

    if changed:
        print("updated dependency files:")
        for path in changed:
            print(f"  {path}")
    else:
        print("source dependency files already requested this version")

    if not args.skip_bundix:
        subprocess.run(["./tools/bundix_all.sh"], cwd=root, check=True)

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as e:
        raise SystemExit(e.returncode)
    except RuntimeError as e:
        print(f"error: {e}", file=sys.stderr)
        raise SystemExit(1)
