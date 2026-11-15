#!/usr/bin/env python3

"""
Convert the saved voyages of a player to the current format of the save files.

The game converts an old save itself when it loads it (see Session.upgrade in
scenes/session/session.gd). This script does the same without the game, e.g.,
for the saves of another account on the machine which only root can read:

    sudo venv/bin/python dev/saves/convert_saves.py /home/aljosha

Every argument is a home directory (the saves are then in
``.local/share/godot/app_userdata/Bird Dog/saves``) or a directory of saves.
Before a save is converted, it is copied as it was to
``backups/<id>.format<N>.json`` next to it (once: an existing backup is never
overwritten). The converted files and the backups keep the owner of the saves.

Format 2 carried the possessions of the crew (the ducats, what was bought, and
the ship and the decorations of every captain) over the chapters; format 3
keeps them by chapter. They stay with the chapter which the crew plays (that
of the mission in progress, else that of the newest open mission), and every
other chapter starts anew when the crew enters it.

Keep this script in sync with Session.upgrade.
"""

import argparse
import json
import os
import pathlib
import re
import shutil
import sys
from typing import Any, Dict, List, Optional

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent

#: The format of the save files which the game writes now (Session.FORMAT).
FORMAT = 3

#: A new voyage, and a chapter entered anew, start with this many ducats
#: (Session.STARTING_DUCATS).
STARTING_DUCATS = 40

#: Where Godot keeps the saves of the game on Linux, relative to the home.
SAVES_IN_HOME = pathlib.Path(".local/share/godot/app_userdata/Bird Dog/saves")

BACKUPS = "backups"


class Mission:
    """The id, the number and the chapter of a mission (see Mission)."""

    def __init__(self, identifier: str, number: int, chapter: int) -> None:
        self.identifier = identifier
        self.number = number
        self.chapter = chapter


def read_missions() -> List[Mission]:
    """Read the missions of the game from data/missions, in their order."""
    missions = []
    for path in sorted((REPO_ROOT / "data" / "missions").glob("*/mission.tres")):
        text = path.read_text(encoding="utf-8")
        resource = text[text.index("[resource]") :]

        def value(key: str, default: str) -> str:
            match = re.search(r"^%s = (.*)$" % key, resource, re.MULTILINE)
            return match.group(1).strip().strip('"') if match is not None else default

        missions.append(
            Mission(value("id", ""), int(value("number", "1")), int(value("chapter", "1")))
        )
    missions.sort(key=lambda mission: mission.number)
    return missions


def newest_chapter(missions: List[Mission], states: Dict[str, Any]) -> int:
    """Return the chapter of the newest open mission (Session.newest_chapter)."""
    by_number = {mission.number: mission for mission in missions}
    newest = 1
    for mission in missions:
        before = by_number.get(mission.number - 1)
        is_open = mission.number <= 1 or (
            before is not None and bool(states.get(before.identifier, {}).get("completed", False))
        )
        if is_open:
            newest = max(newest, mission.chapter)
    return newest


def upgrade(data: Dict[str, Any], missions: List[Mission]) -> Dict[str, Any]:
    """Convert the save of an older format to the current one (Session.upgrade)."""
    if int(data.get("format", 1)) < 2:
        chest = int(data.get("ducats", 0))
        run = data.get("mission_in_progress", {}).get("run", {})
        holds = run.get("holds", [])
        if holds:
            total = chest
            for hold in holds:
                total += int(hold.get("ducats", 0)) - int(hold.get("spent", 0))
            total = max(0, total)
            each = total // len(holds)
            for i, hold in enumerate(holds):
                hold["ducats"] = each + (total - each * len(holds) if i == 0 else 0)
                hold["spent"] = 0
            run["brought"] = chest
        data["format"] = 2

    if int(data.get("format", 2)) < 3:
        played = newest_chapter(missions, data.get("missions", {}))
        progress_id = str(data.get("mission_in_progress", {}).get("run", {}).get("mission", ""))
        for mission in missions:
            if mission.identifier == progress_id:
                played = mission.chapter
        boats = []
        for captain in data.get("crew", {}).get("captains", []):
            boats.append({key: captain[key] for key in ("ship", "boat") if key in captain})
        data["chapter"] = played
        data["chapters"] = {
            str(played): {
                "ducats": int(data.get("ducats", STARTING_DUCATS)),
                "owned": data.get("owned", []),
                "boats": boats,
            }
        }
        data.pop("ducats", None)
        data.pop("owned", None)
        data["format"] = 3
    return data


def _keep_owner(path: pathlib.Path, like: pathlib.Path) -> None:
    """Give the file the owner and the group of another one (as root)."""
    stat = like.stat()
    if hasattr(os, "chown") and (path.stat().st_uid, path.stat().st_gid) != (
        stat.st_uid,
        stat.st_gid,
    ):
        os.chown(path, stat.st_uid, stat.st_gid)


def convert(saves: pathlib.Path, missions: List[Mission], dry_run: bool) -> int:
    """Convert the saves in the directory; return how many were converted."""
    converted = 0
    for path in sorted(saves.glob("*.json")):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as error:
            print(f"  {path.name}: skipped, it can not be read: {error}", file=sys.stderr)
            continue
        if not isinstance(data, dict):
            print(f"  {path.name}: skipped, it is no save", file=sys.stderr)
            continue
        old = int(data.get("format", 1))
        if old >= FORMAT:
            print(f"  {path.name}: format {old}, nothing to do")
            continue

        upgraded = upgrade(data, missions)
        chapter = upgraded["chapter"]
        record = upgraded["chapters"][str(chapter)]
        print(
            f"  {path.name} ({upgraded.get('name', '')}): format {old} -> {FORMAT}, "
            f"chapter {chapter} keeps {record['ducats']} ducats and {len(record['owned'])} "
            "bought item(s)"
        )
        converted += 1
        if dry_run:
            continue

        backups = saves / BACKUPS
        if not backups.exists():
            backups.mkdir()
            _keep_owner(backups, saves)
        backup = backups / f"{path.stem}.format{old}.json"
        if not backup.exists():
            shutil.copy2(path, backup)
            _keep_owner(backup, path)

        # NOTE (mristin):
        # As the game does: a temporary file first, then renamed, so that a
        # crash never destroys the last good save.
        temporary = path.with_name(path.name + ".tmp")
        temporary.write_text(json.dumps(upgraded, indent="  ", sort_keys=True), encoding="utf-8")
        shutil.copymode(path, temporary)
        _keep_owner(temporary, path)
        os.replace(temporary, path)
    return converted


def _saves_of(argument: str) -> Optional[pathlib.Path]:
    """Resolve a home directory or a directory of saves."""
    path = pathlib.Path(argument).expanduser()
    if (path / SAVES_IN_HOME).is_dir():
        return path / SAVES_IN_HOME
    if path.is_dir():
        return path
    return None


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("directories", nargs="+", help="home directories or directories of saves")
    parser.add_argument("--dry-run", action="store_true", help="only tell what would be converted")
    args = parser.parse_args()

    missions = read_missions()
    if not missions:
        print(f"No missions found in {REPO_ROOT / 'data' / 'missions'}", file=sys.stderr)
        return 1

    failed = False
    for argument in args.directories:
        saves = _saves_of(argument)
        if saves is None:
            print(f"{argument}: no saves of Bird Dog found", file=sys.stderr)
            failed = True
            continue
        print(f"{saves}:")
        try:
            converted = convert(saves, missions, args.dry_run)
        except PermissionError as error:
            print(f"  {error}; run the script with sudo", file=sys.stderr)
            failed = True
            continue
        what = "would be converted" if args.dry_run else "converted"
        print(f"  {converted} save(s) {what}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
