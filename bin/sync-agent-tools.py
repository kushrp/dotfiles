#!/usr/bin/env python3
"""Preview or apply portable MCP definitions without copying local credentials."""

from __future__ import annotations

import argparse
import copy
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import socket
import stat
import sys
import tempfile
from urllib.parse import parse_qsl, urlsplit

try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        sys.exit("Use Python 3.11 or newer, or install tomli for Python 3.9/3.10.")


CLIENT_PATHS = {
    "codex": ".codex/config.toml",
    "claude": ".claude.json",
    "grok": ".grok/config.toml",
}
CONNECTION_KEYS = {
    "type", "command", "args", "env", "env_vars", "cwd", "url", "headers",
    "http_headers", "env_http_headers", "bearer_token_env_var",
}
NAME = re.compile(r"[A-Za-z0-9_-]+\Z")
VARIABLE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*\Z")
REFERENCE = re.compile(r"(Bearer )?\$\{([A-Za-z_][A-Za-z0-9_]*)\}\Z")
HEADER = re.compile(r"(?m)^[ \t]*(\[[^\n]+\])[ \t]*(?:#[^\n]*)?$")


class ConfigError(Exception):
    """A config cannot be changed without losing data or local choices."""


def json_object(text: str, label: str) -> dict:
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ConfigError(f"{label}: duplicate JSON key; no files changed")
            result[key] = value
        return result

    try:
        result = json.loads(text, object_pairs_hook=unique)
    except (ValueError, TypeError) as exc:
        raise ConfigError(f"{label}: malformed JSON; no files changed") from exc
    if not isinstance(result, dict):
        raise ConfigError(f"{label}: expected a JSON object; no files changed")
    return result


def parse_toml(text: str, label: str) -> dict:
    try:
        return tomllib.loads(text)
    except ValueError as exc:
        raise ConfigError(f"{label}: malformed TOML; no files changed") from exc


def string_list(value, label: str) -> list[str]:
    if not isinstance(value, list) or any(not isinstance(item, str) for item in value):
        raise ConfigError(f"{label}: expected a list of strings")
    return value


def load_manifest(path: Path) -> dict:
    manifest = json_object(path.read_text(), "manifest")
    if set(manifest) != {"version", "servers"} or manifest["version"] != 1:
        raise ConfigError("manifest: expected version 1 and servers")
    if not isinstance(manifest["servers"], dict):
        raise ConfigError("manifest: servers must be an object")
    allowed = {
        "transport", "command", "args", "env_vars", "url", "headers", "hosts",
        "skip_reason", "clients", "requires_paths",
    }
    for name, server in manifest["servers"].items():
        if not NAME.fullmatch(name) or not isinstance(server, dict):
            raise ConfigError("manifest: invalid server name or definition")
        if set(server) - allowed:
            raise ConfigError(f"{name}: unsupported manifest fields")
        if "skip_reason" in server and (
            not isinstance(server["skip_reason"], str) or not server["skip_reason"].strip()
        ):
            raise ConfigError(f"{name}: skip_reason must be a nonempty string")
        for field in ("args", "env_vars", "hosts", "clients", "requires_paths"):
            string_list(server.get(field, []), f"{name}.{field}")
        if "hosts" in server and (not server["hosts"] or not server.get("skip_reason")):
            raise ConfigError(f"{name}: hosts requires names and skip_reason")
        if "clients" in server and (
            not server["clients"] or set(server["clients"]) - set(CLIENT_PATHS)
        ):
            raise ConfigError(f"{name}: clients contains an unsupported app")
        if server.get("skip_reason") and "hosts" not in server:
            continue
        transport = server.get("transport")
        if transport == "stdio":
            if not isinstance(server.get("command"), str) or not server["command"]:
                raise ConfigError(f"{name}: stdio requires command")
            if "url" in server or "headers" in server:
                raise ConfigError(f"{name}: HTTP fields cannot be used with stdio")
            if any(not VARIABLE.fullmatch(var) for var in server.get("env_vars", [])):
                raise ConfigError(f"{name}: env_vars must contain variable names")
            paths = [server["command"], *server.get("args", []), *server.get("requires_paths", [])]
            if any("${" in value for value in paths):
                raise ConfigError(f"{name}: use ~/ for paths and env_vars for secrets")
            if any(value.startswith("/") for value in paths) and not server.get("hosts"):
                raise ConfigError(f"{name}: absolute paths require hosts and skip_reason; prefer ~/")
        elif transport == "http":
            if set(server) & {"command", "args", "env_vars"}:
                raise ConfigError(f"{name}: stdio fields cannot be used with HTTP")
            if not isinstance(server.get("url"), str):
                raise ConfigError(f"{name}: HTTP requires url")
            try:
                url = urlsplit(server["url"])
            except ValueError as exc:
                raise ConfigError(f"{name}: invalid HTTP URL") from exc
            if (
                url.scheme not in {"https", "http"} or not url.hostname
                or url.username or url.password or url.fragment
                or "${" in server["url"]
            ):
                raise ConfigError(f"{name}: URL must have no credentials, fragment, or variables")
            if url.query:
                try:
                    query = parse_qsl(url.query, keep_blank_values=True, strict_parsing=True)
                    allowed_query = (
                        url.scheme == "https" and url.hostname == "mcp.datadoghq.com"
                        and url.port in (None, 443) and len(query) == 1
                        and query[0][0] == "toolsets"
                        and re.fullmatch(r"[A-Za-z0-9_-]+(?:,[A-Za-z0-9_-]+)*", query[0][1])
                    )
                except ValueError:
                    allowed_query = False
                if not allowed_query:
                    raise ConfigError(f"{name}: only the Datadog toolsets query is supported")
            headers = server.get("headers", {})
            if not isinstance(headers, dict):
                raise ConfigError(f"{name}: headers must be an object")
            if len({header.lower() for header in headers}) != len(headers):
                raise ConfigError(f"{name}: duplicate header names")
            for header, value in headers.items():
                match = REFERENCE.fullmatch(value) if isinstance(value, str) else None
                if not re.fullmatch(r"[A-Za-z0-9-]+", header) or not match:
                    raise ConfigError(f"{name}: headers must reference environment variables")
                if match[1] and header.lower() != "authorization":
                    raise ConfigError(f"{name}: Bearer prefix is supported only for Authorization")
        else:
            raise ConfigError(f"{name}: transport must be stdio or http")
    return manifest["servers"]


def local_path(value: str, home: Path) -> str:
    return str(home / value[2:]) if value.startswith("~/") else value


def render_servers(servers: dict, home: Path, hostname: str) -> tuple[dict, list[str]]:
    desired = {client: {} for client in CLIENT_PATHS}
    missing = set()
    unavailable = []
    for name, server in servers.items():
        hosts = server.get("hosts", [])
        if server.get("skip_reason") and (not hosts or hostname not in hosts):
            print(f"SKIP {name}: {server['skip_reason']}")
            continue
        required_paths = [Path(local_path(p, home)) for p in server.get("requires_paths", [])]
        if any(not path.exists() for path in required_paths):
            print(f"SKIP {name}: a required local path is missing")
            unavailable.append(name)
            continue
        transport = server["transport"]
        if transport == "stdio":
            command = shutil.which(local_path(server["command"], home))
            if not command:
                print(f"SKIP {name}: command is unavailable: {server['command']}")
                unavailable.append(name)
                continue
            variables = server.get("env_vars", [])
            for variable in variables:
                if not os.environ.get(variable):
                    missing.add(variable)
        else:
            variables = []
            for value in server.get("headers", {}).values():
                variable = REFERENCE.fullmatch(value)[2]
                if not os.environ.get(variable):
                    missing.add(variable)
        for client in server.get("clients", CLIENT_PATHS):
            entry = {}
            if client == "claude":
                entry["type"] = transport
            if transport == "stdio":
                entry.update(command=command, args=[local_path(arg, home) for arg in server.get("args", [])])
                if variables:
                    if client == "codex":
                        entry["env_vars"] = sorted(set(variables))
                    else:
                        entry["env"] = {var: "${" + var + "}" for var in sorted(set(variables))}
            else:
                entry["url"] = server["url"]
                headers = server.get("headers", {})
                if client != "codex" and headers:
                    entry["headers"] = headers
                elif headers:
                    for header, value in headers.items():
                        match = REFERENCE.fullmatch(value)
                        if match[1]:
                            entry["bearer_token_env_var"] = match[2]
                        else:
                            entry.setdefault("env_http_headers", {})[header] = match[2]
            desired[client][name] = entry
    for variable in sorted(missing):
        print(f"MISSING ENV {variable}: set it in each app's local environment")
    return desired, sorted(missing) + unavailable


def fingerprint(entry: dict) -> str:
    connection = {key: value for key, value in entry.items() if key in CONNECTION_KEYS}
    return hashlib.sha256(json.dumps(connection, sort_keys=True).encode()).hexdigest()


def toml_value(value) -> str:
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, bool):
        return str(value).lower()
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, list):
        return "[" + ", ".join(toml_value(item) for item in value) + "]"
    if isinstance(value, dict):
        return "{ " + ", ".join(f"{json.dumps(key)} = {toml_value(item)}" for key, item in value.items()) + " }"
    if isinstance(value, (datetime.datetime, datetime.date, datetime.time)):
        return value.isoformat()
    raise ConfigError("owned TOML server contains an unsupported value; no files changed")


def update_toml(text: str, original: dict, replacements: dict) -> str:
    matches = list(HEADER.finditer(text))
    removed = set()
    chunks = []
    offset = 0
    for index, match in enumerate(matches):
        try:
            header = tomllib.loads(match[1])
        except ValueError:
            continue
        names = header.get("mcp_servers", {})
        owned = set(names) & set(replacements) if isinstance(names, dict) else set()
        if not owned:
            continue
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        chunks.append(text[offset:match.start()])
        offset = end
        removed.update(owned)
    existing = original.get("mcp_servers", {})
    if set(replacements) & set(existing) - removed:
        raise ConfigError("owned MCP entry uses inline TOML; convert it to [mcp_servers.name] before applying")
    chunks.append(text[offset:])
    result = "".join(chunks).rstrip() + "\n"
    for name, entry in replacements.items():
        result += f"\n[mcp_servers.{json.dumps(name)}]\n"
        result += "".join(f"{json.dumps(key)} = {toml_value(value)}\n" for key, value in entry.items())
    expected = copy.deepcopy(original)
    expected.setdefault("mcp_servers", {}).update(replacements)
    if parse_toml(result, "generated config") != expected:
        raise ConfigError("TOML layout cannot be edited without changing unrelated values; no files changed")
    return result


def plan_updates(home: Path, desired: dict, replace_existing: bool) -> list[tuple[Path, str, str]]:
    state_path = home / ".config/agent-sync/mcp-owned.json"
    state_text = state_path.read_text() if state_path.exists() else ""
    state = json_object(state_text, "ownership state") if state_text else {}
    if any(not isinstance(value, dict) for value in state.values()):
        raise ConfigError("ownership state: invalid app record; no files changed")
    updates = []
    for client, relative in CLIENT_PATHS.items():
        path = home / relative
        text = path.read_text() if path.exists() else ""
        config = json_object(text, client) if client == "claude" and text else parse_toml(text, client)
        key = "mcpServers" if client == "claude" else "mcp_servers"
        current = config.get(key, {})
        if not isinstance(current, dict):
            raise ConfigError(f"{client}: invalid MCP server table; no files changed")
        replacements = {}
        for name, entry in desired[client].items():
            previous = current.get(name, {})
            if not isinstance(previous, dict):
                raise ConfigError(f"{client}/{name}: invalid server definition; no files changed")
            combined = {k: v for k, v in previous.items() if k not in CONNECTION_KEYS}
            combined.update(entry)
            if previous != combined:
                owned = state.get(client, {}).get(name) == fingerprint(previous)
                if previous and not owned and not replace_existing:
                    raise ConfigError(f"CONFLICT {client}/{name}: review the definition, then use --replace-existing to back up and adopt it")
                replacements[name] = combined
                print(f"CHANGE {client}/{name}")
            else:
                print(f"OK {client}/{name}")
            state.setdefault(client, {})[name] = fingerprint(combined)
        if replacements:
            if client == "claude":
                config.setdefault(key, {}).update(replacements)
                updated = json.dumps(config, indent=2, ensure_ascii=False) + "\n"
            else:
                updated = update_toml(text, config, replacements)
            updates.append((path, text, updated))
    updated_state = json.dumps(state, indent=2, sort_keys=True) + "\n"
    if state and state_text != updated_state:
        updates.append((state_path, state_text, updated_state))
    return updates


def apply_updates(updates: list[tuple[Path, str, str]]) -> None:
    # Apps can save preferences during preview. Reject stale plans before writing.
    for path, previous, _ in updates:
        if path.is_symlink():
            raise ConfigError(f"{path.name}: config is a symlink; update its source separately")
        if (path.read_text() if path.exists() else "") != previous:
            raise ConfigError(f"{path.name}: config changed during sync; retry")
    for path, previous, updated in updates:
        if (path.read_text() if path.exists() else "") != previous:
            raise ConfigError(f"{path.name}: config changed during sync; retry")
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.exists():
            descriptor, backup = tempfile.mkstemp(prefix=path.name + ".agent-sync-backup-", dir=path.parent)
            with os.fdopen(descriptor, "w") as handle:
                handle.write(previous)
            print(f"BACKUP {backup}")
        descriptor, temporary = tempfile.mkstemp(prefix=".agent-sync-", dir=path.parent)
        try:
            with os.fdopen(descriptor, "w") as handle:
                handle.write(updated)
                handle.flush()
                os.fsync(handle.fileno())
            mode = stat.S_IMODE(path.stat().st_mode) & 0o600 if path.exists() else 0o600
            os.chmod(temporary, mode)
            os.replace(temporary, path)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--apply", action="store_true", help="write changes with local protected backups")
    mode.add_argument("--check", action="store_true", help="exit 1 for config changes, missing variables, or unavailable local servers")
    parser.add_argument("--home", type=Path, default=Path.home())
    parser.add_argument("--manifest", type=Path, default=Path(__file__).resolve().parents[1] / "agent-tools.json")
    parser.add_argument("--hostname", default=socket.gethostname(), help="host name used for explicit server restrictions")
    parser.add_argument("--replace-existing", action="store_true", help="adopt conflicting named entries after backing them up")
    args = parser.parse_args()
    try:
        servers = load_manifest(args.manifest)
        desired, missing = render_servers(servers, args.home.expanduser().resolve(), args.hostname)
        updates = plan_updates(args.home.expanduser().resolve(), desired, args.replace_existing)
        if args.apply:
            apply_updates(updates)
            print(f"Applied {len(updates)} file changes.")
        else:
            print(f"Preview: {len(updates)} file changes. Use --apply to write them.")
        return int(args.check and bool(updates or missing))
    except (ConfigError, OSError, UnicodeError) as exc:
        # Parser exceptions can contain credential-bearing source lines.
        message = str(exc) if isinstance(exc, ConfigError) else f"{type(exc).__name__}: cannot read or write a configuration file"
        print(message, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
