#!/usr/bin/env python3
"""Install pinned native plugins while preserving other plugins and credentials."""

from __future__ import annotations

import argparse
import datetime
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys


NAME = re.compile(r"[a-z0-9][a-z0-9-]*\Z")
SHA = re.compile(r"[0-9a-f]{40}\Z")
URL = re.compile(r"https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\.git\Z")


class PluginError(Exception):
    """A plugin cannot be reconciled without losing local state."""


def read_json(path: Path):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError) as exc:
        raise PluginError(f"Cannot read JSON: {path}") from exc


def load_manifest(path: Path) -> dict:
    data = read_json(path)
    if not isinstance(data, dict) or set(data) != {"version", "marketplaces", "plugins"} or data["version"] != 1:
        raise PluginError("Manifest must contain version 1, marketplaces, and plugins")
    for field in ("marketplaces", "plugins"):
        if not isinstance(data[field], dict) or not data[field]:
            raise PluginError(f"Manifest {field} must be a nonempty object")
        for name, entry in data[field].items():
            if not NAME.fullmatch(name) or not isinstance(entry, dict):
                raise PluginError(f"Invalid {field} entry")
            fields = {"url", "sha"} if field == "marketplaces" else {"url", "sha", "version", "marketplace"}
            optional = {"registration_name"} if field == "marketplaces" else set()
            if not fields <= set(entry) or set(entry) - fields - optional or not URL.fullmatch(str(entry.get("url", ""))) or not SHA.fullmatch(str(entry.get("sha", ""))):
                raise PluginError(f"{name}: use a public GitHub URL and a full commit SHA")
            if "registration_name" in entry and not NAME.fullmatch(str(entry["registration_name"])):
                raise PluginError(f"{name}: invalid registration_name")
            if field == "plugins" and (
                entry["marketplace"] not in data["marketplaces"]
                or not isinstance(entry["version"], str) or not entry["version"]
            ):
                raise PluginError(f"{name}: invalid marketplace or version")
    return data


class Native:
    def __init__(self, home: Path):
        self.home = home
        self.env = dict(os.environ, CLAUDE_CONFIG_DIR=str(home / ".claude"), GROK_HOME=str(home / ".grok"))

    def run(self, *args: str) -> str:
        try:
            result = subprocess.run(args, cwd=self.home, env=self.env, text=True,
                                    capture_output=True, timeout=180)
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise PluginError(f"Command failed or timed out: {' '.join(args)}") from exc
        if result.returncode:
            # Native output can include local MCP configuration. Report only the command.
            raise PluginError(f"Command exited {result.returncode}: {' '.join(args)}")
        return result.stdout

    def json(self, *args: str):
        try:
            return json.loads(self.run(*args))
        except ValueError as exc:
            raise PluginError(f"Command returned invalid JSON: {' '.join(args)}") from exc


def plugin_version(path: Path, name: str) -> str | None:
    for relative in (".claude-plugin/plugin.json", ".grok-plugin/plugin.json", "plugin.json"):
        manifest = path / relative
        if manifest.is_file():
            data = read_json(manifest)
            if isinstance(data, dict) and data.get("name") == name:
                return data.get("version")
    return None


def source_selector(plugin: dict) -> str:
    return plugin["url"] + "@" + plugin["sha"]


def marketplace_path(home: Path, name: str, entry: dict) -> Path:
    return home / ".local/share/mac-config/plugin-marketplaces" / name / entry["sha"]


def registration_name(name: str, entry: dict) -> str:
    return entry.get("registration_name", name)


def registration_path(home: Path, name: str, entry: dict) -> Path:
    if registration_name(name, entry) == name:
        return marketplace_path(home, name, entry)
    return home / ".local/share/mac-config/plugin-catalogs" / registration_name(name, entry) / entry["sha"]


def claude_selector(manifest: dict, name: str) -> str:
    marketplace = manifest["plugins"][name]["marketplace"]
    return name + "@" + registration_name(marketplace, manifest["marketplaces"][marketplace])


def inventory(native: Native) -> tuple[list, list, list]:
    claude = native.json("claude", "plugin", "list", "--json")
    grok = native.json("grok", "plugin", "list", "--json")
    loaded = native.json("grok", "inspect", "--json")
    if not isinstance(claude, list) or not isinstance(grok, list) or not isinstance(loaded, dict) or not isinstance(loaded.get("plugins"), list):
        raise PluginError("Unexpected plugin inventory format; update the installer for this CLI")
    return claude, grok, loaded["plugins"]


def is_pinned(native: Native, item: dict, plugin: dict) -> bool:
    if item.get("source") != plugin["url"] or not item.get("path") or not Path(item["path"]).is_dir():
        return False
    try:
        return native.run("git", "-C", item["path"], "rev-parse", "HEAD").strip() == plugin["sha"]
    except PluginError:
        return False


def stale_grok_paths(native: Native, plugins: dict, installed: list, loaded: list) -> list[Path]:
    result = []
    names = {item.get("name") for item in installed
             if item.get("name") in plugins and not is_pinned(native, item, plugins[item["name"]])}
    for item in installed:
        name = item.get("name")
        if name not in names:
            continue
        path = Path(item.get("path", ""))
        root = native.home / ".grok/installed-plugins"
        if path.is_symlink() or path.parent != root or root.resolve() != root:
            raise PluginError(f"CONFLICT grok/{name}: unmanaged source at {path}; reconcile it manually")
        shared = [row for row in installed if row.get("repo_key") == item.get("repo_key") and row.get("name") != name]
        if shared:
            raise PluginError(f"CONFLICT grok/{name}: its repository also contains other plugins; reconcile it manually")
        if not path.exists() and not existing_backup(native.home, path, name, item.get("version")):
            raise PluginError(f"CONFLICT grok/{name}: its registered directory is missing without a verified backup: {path}")
        if path.exists() and plugin_version(path, name) is None:
            raise PluginError(f"CONFLICT grok/{name}: cannot verify the old plugin at {path}")
        if path not in result:
            result.append(path)
    for item in loaded:
        name = item.get("name")
        if name not in plugins:
            continue
        path = Path(item.get("path", ""))
        expected = native.home / ".claude/plugins/marketplaces" / plugins[name]["marketplace"] / "plugins" / name
        if path == expected and plugin_version(path, name) != plugins[name]["version"]:
            if path.is_symlink() or path.resolve() != path or not path.is_dir() or plugin_version(path, name) is None:
                raise PluginError(f"CONFLICT grok/{name}: cannot adopt the marketplace plugin at {path}")
            if path not in result:
                result.append(path)
    return result


def existing_backup(home: Path, original: Path, name: str, version: str) -> bool:
    root = home / ".local/state/mac-config/plugin-backups"
    for path in root.glob("*/*"):
        if path.is_dir() and path.name.endswith("-" + original.name) and plugin_version(path, name) == version:
            return True
    return False


def registration_changes(home: Path, manifest: dict) -> list[str]:
    path = home / ".claude/plugins/known_marketplaces.json"
    known = read_json(path) if path.exists() else {}
    if not isinstance(known, dict):
        raise PluginError(f"Invalid marketplace registry: {path}")
    changes = []
    for name, entry in manifest["marketplaces"].items():
        expected = registration_path(home, name, entry)
        registered = known.get(registration_name(name, entry), {})
        source = registered.get("source", {})
        if source.get("source") != "directory" or source.get("path") != str(expected) or not expected.is_dir():
            changes.append(name)
    return changes


def problems(native: Native, manifest: dict, snapshot: tuple[list, list, list]) -> list[str]:
    claude, installed, loaded = snapshot
    issues = []
    for name, plugin in manifest["plugins"].items():
        selector = claude_selector(manifest, name)
        rows = [item for item in claude if item.get("id") == selector and item.get("scope") == "user"]
        if len(rows) != 1 or not rows[0].get("enabled") or plugin_version(Path(rows[0].get("installPath", "")), name) != plugin["version"]:
            issues.append(f"claude/{name}: expected enabled version {plugin['version']} in the user installation")
        legacy = name + "@" + plugin["marketplace"]
        if legacy != selector and any(item.get("id") == legacy and item.get("scope") == "user" and item.get("enabled") for item in claude):
            issues.append(f"claude/{name}: the previous official installation also remains enabled")
        rows = [item for item in loaded if item.get("name") == name]
        if len(rows) != 1 or not rows[0].get("enabled") or plugin_version(Path(rows[0].get("path", "")), name) != plugin["version"]:
            issues.append(f"grok/{name}: expected loaded version {plugin['version']}; inspect the selected plugin path")
        pinned = [item for item in installed if item.get("name") == name and is_pinned(native, item, plugin)]
        if not pinned:
            issues.append(f"grok/{name}: pinned native installation is missing")
        if len(rows) == 1 and rows[0].get("path"):
            selected = Path(rows[0]["path"]).resolve()
            paths = {Path(item["path"]).resolve() for item in pinned}
            catalog = manifest["marketplaces"][plugin["marketplace"]]
            if plugin["url"] == catalog["url"] and plugin["sha"] == catalog["sha"]:
                paths.add(marketplace_path(native.home, plugin["marketplace"], catalog).resolve())
            if selected not in paths:
                issues.append(f"grok/{name}: the loaded path is not a verified pinned source: {selected}")
    return issues


def validate_marketplace(native: Native, target: Path, name: str, entry: dict, plugins: dict):
    if target.is_symlink() or target.resolve() != target:
        raise PluginError(f"Refusing a symlink for a managed checkout: {target}")
    if native.run("git", "-C", str(target), "rev-parse", "HEAD").strip() != entry["sha"]:
        raise PluginError(f"Managed checkout has a different commit: {target}")
    native.run("git", "-C", str(target), "diff", "--exit-code", "HEAD", "--")
    catalog = read_json(target / ".claude-plugin/marketplace.json")
    if not isinstance(catalog, dict) or catalog.get("name") != name:
        raise PluginError(f"Marketplace name does not match the pinned catalog: {name}")
    for plugin_name, plugin in plugins.items():
        if plugin["marketplace"] != name:
            continue
        matches = [item for item in catalog.get("plugins", []) if item.get("name") == plugin_name]
        if len(matches) != 1:
            raise PluginError(f"{name}: expected exactly one catalog entry for {plugin_name}")
        source = matches[0].get("source")
        if isinstance(source, dict):
            correct = source == {"source": "url", "url": plugin["url"], "sha": plugin["sha"]}
        else:
            correct = (source == "./" and plugin["url"] == entry["url"] and plugin["sha"] == entry["sha"]
                       and plugin_version(target, plugin_name) == plugin["version"])
        if not correct:
            raise PluginError(f"{name}/{plugin_name}: catalog source does not match the immutable plugin pin")


def prepare_marketplace(native: Native, name: str, entry: dict, plugins: dict) -> Path:
    target = marketplace_path(native.home, name, entry)
    if target.is_symlink():
        raise PluginError(f"Refusing a symlink for a managed checkout: {target}")
    if not target.exists():
        target.parent.mkdir(parents=True, exist_ok=True)
        # A failed fetch leaves an incomplete sibling, never a valid-looking target.
        stamp = datetime.datetime.now().strftime("%Y%m%d%H%M%S%f")
        staging = target.with_name(target.name + ".pending-" + stamp)
        native.run("git", "init", "--quiet", str(staging))
        native.run("git", "-C", str(staging), "fetch", "--quiet", "--depth=1", entry["url"], entry["sha"])
        native.run("git", "-C", str(staging), "checkout", "--quiet", "--detach", "FETCH_HEAD")
        if native.run("git", "-C", str(staging), "rev-parse", "HEAD").strip() != entry["sha"]:
            raise PluginError(f"Fetched commit does not match {name}")
        staging.rename(target)
    validate_marketplace(native, target, name, entry, plugins)
    return target


def derived_catalog(source: Path, name: str, entry: dict, plugins: dict) -> dict:
    original = read_json(source / ".claude-plugin/marketplace.json")
    selected = {plugin_name for plugin_name, plugin in plugins.items() if plugin["marketplace"] == name}
    return {
        "name": registration_name(name, entry),
        "owner": {"name": "Kush"},
        "plugins": [item for item in original["plugins"] if item["name"] in selected],
    }


def prepare_registration(native: Native, source: Path, name: str, entry: dict, plugins: dict) -> Path:
    target = registration_path(native.home, name, entry)
    if target == source:
        return target
    if target.resolve() != target:
        raise PluginError(f"Refusing a symlink for a managed catalog: {target}")
    expected = derived_catalog(source, name, entry, plugins)
    path = target / ".claude-plugin/marketplace.json"
    if path.exists():
        if read_json(path) != expected:
            raise PluginError(f"Managed catalog has local changes: {path}")
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(expected, indent=2) + "\n")
    return target


def apply(native: Native, manifest: dict, snapshot: tuple[list, list, list], stale: list[Path]):
    for name, entry in manifest["marketplaces"].items():
        target = prepare_marketplace(native, name, entry, manifest["plugins"])
        target = prepare_registration(native, target, name, entry, manifest["plugins"])
        if name in registration_changes(native.home, manifest):
            native.run("claude", "plugin", "marketplace", "add", str(target), "--scope", "user")
    claude, grok, _ = snapshot
    for name, plugin in manifest["plugins"].items():
        selector = claude_selector(manifest, name)
        rows = [item for item in claude if item.get("id") == selector and item.get("scope") == "user"]
        current = rows[0] if rows else None
        if current is None:
            native.run("claude", "plugin", "install", selector, "--scope", "user")
        elif plugin_version(Path(current.get("installPath", "")), name) != plugin["version"]:
            native.run("claude", "plugin", "update", selector, "--scope", "user")
        if current is not None and not current.get("enabled"):
            native.run("claude", "plugin", "enable", selector, "--scope", "user")
        legacy = name + "@" + plugin["marketplace"]
        if legacy != selector and any(item.get("id") == legacy and item.get("scope") == "user" and item.get("enabled") for item in claude):
            native.run("claude", "plugin", "disable", legacy, "--scope", "user")
    if stale:
        stamp = datetime.datetime.now().strftime("%Y%m%dT%H%M%S%f")
        backup = native.home / ".local/state/mac-config/plugin-backups" / stamp
        backup.mkdir(parents=True, mode=0o700)
        for index, path in enumerate(stale):
            if not path.exists():
                continue
            destination = backup / (str(index) + "-" + path.name)
            path.rename(destination)
            print(f"BACKUP {path} -> {destination}")
        names = {item["name"] for item in grok if Path(item["path"]) in stale}
        for name in sorted(names):
            # Grok unregisters by name, so every copy of that name must be backed up first.
            count = len([item for item in grok if item["name"] == name])
            for _ in range(count):
                current = [item for item in native.json("grok", "plugin", "list", "--json") if item.get("name") == name]
                if not current:
                    break
                if any(Path(item["path"]).exists() or Path(item["path"]) not in stale for item in current):
                    raise PluginError(f"grok/{name}: registration changed after backup; stopped before unregistering")
                native.run("grok", "plugin", "uninstall", name, "--confirm", "--keep-data")
            if any(item.get("name") == name for item in native.json("grok", "plugin", "list", "--json")):
                raise PluginError(f"grok/{name}: old native registrations remain")
    for name, plugin in manifest["plugins"].items():
        pinned = [item for item in grok if item.get("name") == name and is_pinned(native, item, plugin)]
        if not pinned:
            native.run("grok", "plugin", "install", source_selector(plugin), "--trust")
        rows = [item for item in snapshot[2] if item.get("name") == name and item.get("enabled")]
        if stale or not pinned or not rows:
            native.run("grok", "plugin", "enable", name)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--home", type=Path, default=Path.home())
    parser.add_argument("--manifest", type=Path, default=Path(__file__).resolve().parents[1] / "agent-plugins.json")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--apply", action="store_true")
    mode.add_argument("--check", action="store_true")
    parser.add_argument("--adopt", action="store_true", help="Move conflicting Grok plugin sources to backups before installing the pins")
    args = parser.parse_args()
    lock = None
    try:
        manifest = load_manifest(args.manifest)
        home = args.home.expanduser().resolve()
        if not home.is_dir():
            raise PluginError(f"Home directory does not exist: {home}")
        missing = [name for name in ("claude", "grok", "git") if shutil.which(name) is None]
        if missing:
            for name in missing:
                print(f"MISSING CLI {name}")
            return 2 if args.apply else (1 if args.check else 0)
        if args.apply:
            path = home / ".local/state/mac-config/plugins.lock"
            path.parent.mkdir(parents=True, exist_ok=True)
            lock = path.open("a")
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as exc:
                raise PluginError("Another plugin synchronization holds the lock") from exc
        native = Native(home)
        snapshot = inventory(native)
        stale = stale_grok_paths(native, manifest["plugins"], snapshot[1], snapshot[2])
        for name, entry in manifest["marketplaces"].items():
            target = marketplace_path(home, name, entry)
            if target.exists():
                validate_marketplace(native, target, name, entry, manifest["plugins"])
                registered = registration_path(home, name, entry)
                if registered != target and registered.exists():
                    if read_json(registered / ".claude-plugin/marketplace.json") != derived_catalog(target, name, entry, manifest["plugins"]):
                        raise PluginError(f"Managed catalog has local changes: {registered}")
        registrations = registration_changes(home, manifest)
        issues = problems(native, manifest, snapshot)
        for name in registrations:
            print(f"CHANGE claude marketplace {name}: register the pinned local checkout")
        for path in stale:
            print(f"CONFLICT grok source {path}: --apply --adopt moves this copy to a backup")
        for issue in issues:
            print(f"CHANGE {issue}")
        if args.check:
            return int(bool(registrations or stale or issues))
        if not args.apply:
            print("Preview only. Use --apply; conflicting Grok copies also require --adopt.")
            return 0
        if stale and not args.adopt:
            raise PluginError("Conflicting Grok copies remain; inspect the paths, then use --apply --adopt")
        apply(native, manifest, snapshot, stale)
        remaining = problems(native, manifest, inventory(native))
        if remaining:
            raise PluginError("Native discovery did not match the manifest: " + "; ".join(remaining))
        print(f"Verified {len(manifest['plugins'])} pinned plugins in Claude Code and Grok. Start new sessions to load them.")
        return 0
    except (PluginError, OSError) as exc:
        print(f"ERROR {exc}", file=sys.stderr)
        return 2
    finally:
        if lock is not None:
            lock.close()


if __name__ == "__main__":
    sys.exit(main())
