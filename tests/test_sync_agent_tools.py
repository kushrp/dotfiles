"""Exercise config changes in temporary homes, without reading real credentials."""

import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "bin/sync-agent-tools.py"
SPEC = importlib.util.spec_from_file_location("sync_agent_tools", SCRIPT)
sync = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(sync)


class SyncAgentToolsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.manifest = self.home / "agent-tools.json"
        self.environment = patch.dict(os.environ, {"PATH": "/usr/bin:/bin"}, clear=True)
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def write(self, relative, text):
        path = self.home / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def configure(self, servers):
        self.manifest.write_text(json.dumps({"version": 1, "servers": servers}))

    def run_sync(self, *flags):
        output, errors = io.StringIO(), io.StringIO()
        argv = [str(SCRIPT), "--home", str(self.home), "--manifest", str(self.manifest), *flags]
        with patch("sys.argv", argv), contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
            result = sync.main()
        return result, output.getvalue() + errors.getvalue()

    def http(self, **extra):
        return {"transport": "http", "url": "https://example.com/mcp", **extra}

    def test_default_preview_writes_nothing(self):
        self.configure({"docs": self.http()})
        result, output = self.run_sync()
        self.assertEqual(result, 0, output)
        self.assertIn("CHANGE codex/docs", output)
        self.assertEqual(list(self.home.iterdir()), [self.manifest])

    def test_apply_is_idempotent_and_preserves_unrelated_config(self):
        codex_text = (
            '# Keep this comment.\nmodel = "test-model"\n'
            '[mcp_servers.other]\ncommand = "other-tool"\n'
            '[projects."/work"]\ntrust_level = "trusted"\n'
            '[[skills.config]]\npath = "/local/skill"\nenabled = false\n'
        )
        codex = self.write(".codex/config.toml", codex_text)
        original_claude = {"theme": "dark", "oauth": "synthetic-private-value", "mcpServers": {"other": {"type": "stdio", "command": "other"}}}
        claude = self.write(".claude.json", json.dumps(original_claude))
        self.configure({"docs": self.http()})
        result, output = self.run_sync("--apply")
        self.assertEqual(result, 0, output)
        self.assertIn(codex_text.rstrip(), codex.read_text())
        parsed = json.loads(claude.read_text())
        self.assertEqual(parsed["oauth"], original_claude["oauth"])
        self.assertEqual(parsed["mcpServers"]["other"], original_claude["mcpServers"]["other"])
        self.assertNotIn("synthetic-private-value", output)
        files = {str(path): path.read_bytes() for path in self.home.rglob("*") if path.is_file()}
        result, output = self.run_sync("--apply")
        self.assertEqual(result, 0, output)
        self.assertIn("Applied 0 file changes", output)
        self.assertEqual(files, {str(path): path.read_bytes() for path in self.home.rglob("*") if path.is_file()})

    def test_conflict_requires_explicit_adoption_and_retains_local_controls(self):
        original = (
            '[mcp_servers.docs]\nurl = "https://old.example.com/mcp"\n'
            'enabled = false\ndisabled_tools = ["delete"]\n'
            '[mcp_servers.docs.env_http_headers]\nAuthorization = "OLD_TOKEN"\n'
            '[[skills.config]]\npath = "/local/skill"\nenabled = false\n'
        )
        path = self.write(".codex/config.toml", original)
        self.configure({"docs": self.http()})
        result, output = self.run_sync("--apply")
        self.assertEqual(result, 2)
        self.assertIn("CONFLICT codex/docs", output)
        self.assertEqual(path.read_text(), original)
        self.assertFalse((self.home / ".claude.json").exists())
        result, output = self.run_sync("--apply", "--replace-existing")
        self.assertEqual(result, 0, output)
        parsed = sync.tomllib.loads(path.read_text())
        self.assertFalse(parsed["mcp_servers"]["docs"]["enabled"])
        self.assertEqual(parsed["mcp_servers"]["docs"]["disabled_tools"], ["delete"])
        self.assertEqual(parsed["skills"], sync.tomllib.loads(original)["skills"])
        backups = list(path.parent.glob("config.toml.agent-sync-backup-*"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), original)
        self.assertEqual(stat.S_IMODE(backups[0].stat().st_mode), 0o600)

    def test_owned_server_updates_without_replacement_flag(self):
        self.configure({"docs": self.http()})
        self.assertEqual(self.run_sync("--apply")[0], 0)
        self.configure({"docs": self.http(url="https://updated.example.com/mcp")})
        result, output = self.run_sync("--apply")
        self.assertEqual(result, 0, output)
        parsed = sync.tomllib.loads((self.home / ".codex/config.toml").read_text())
        self.assertEqual(parsed["mcp_servers"]["docs"]["url"], "https://updated.example.com/mcp")

    def test_user_edit_to_owned_connection_stops_update(self):
        self.configure({"docs": self.http()})
        self.assertEqual(self.run_sync("--apply")[0], 0)
        path = self.home / ".codex/config.toml"
        path.write_text(path.read_text().replace("example.com", "local.example.com"))
        original = path.read_bytes()
        result, output = self.run_sync("--apply")
        self.assertEqual(result, 2)
        self.assertIn("CONFLICT", output)
        self.assertEqual(path.read_bytes(), original)

    def test_environment_references_are_translated_without_values(self):
        os.environ["PRIVATE_MCP_TOKEN"] = "synthetic-token-do-not-persist"
        self.configure({
            "docs": self.http(headers={"Authorization": "Bearer ${PRIVATE_MCP_TOKEN}", "X-Key": "${MISSING_KEY}"}),
            "local": {"transport": "stdio", "command": "true", "env_vars": ["PRIVATE_MCP_TOKEN"]},
        })
        result, output = self.run_sync("--apply")
        self.assertEqual(result, 0, output)
        self.assertIn("MISSING ENV MISSING_KEY", output)
        self.assertNotIn("synthetic-token-do-not-persist", output)
        for path in self.home.rglob("*"):
            if path.is_file():
                self.assertNotIn("synthetic-token-do-not-persist", path.read_text())
        codex = sync.tomllib.loads((self.home / ".codex/config.toml").read_text())["mcp_servers"]
        self.assertEqual(codex["docs"]["bearer_token_env_var"], "PRIVATE_MCP_TOKEN")
        self.assertEqual(codex["docs"]["env_http_headers"], {"X-Key": "MISSING_KEY"})
        self.assertEqual(codex["local"]["env_vars"], ["PRIVATE_MCP_TOKEN"])
        claude = json.loads((self.home / ".claude.json").read_text())["mcpServers"]
        self.assertEqual(claude["local"]["env"], {"PRIVATE_MCP_TOKEN": "${PRIVATE_MCP_TOKEN}"})
        self.assertEqual(self.run_sync("--check")[0], 1)

    def test_datadog_toolsets_query_is_preserved_in_every_app(self):
        for scope in ("logs,metrics,apm", "logs%2Cmetrics%2Capm"):
            with self.subTest(scope=scope):
                url = "https://mcp.datadoghq.com/api/unstable/mcp?toolsets=" + scope
                self.configure({"datadog": self.http(url=url), "docs": self.http()})
                result, output = self.run_sync("--apply")
                self.assertEqual(result, 0, output)
                for relative in (".codex/config.toml", ".grok/config.toml"):
                    config = sync.tomllib.loads((self.home / relative).read_text())
                    self.assertEqual(config["mcp_servers"]["datadog"]["url"], url)
                claude = json.loads((self.home / ".claude.json").read_text())
                self.assertEqual(claude["mcpServers"]["datadog"]["url"], url)
                before = {str(path): path.read_bytes() for path in self.home.rglob("*") if path.is_file()}
                self.assertEqual(self.run_sync("--check")[0], 0)
                self.assertEqual(before, {str(path): path.read_bytes() for path in self.home.rglob("*") if path.is_file()})

    def test_query_allowlist_rejects_credentials_and_changed_origins(self):
        for url in (
            "https://mcp.datadoghq.com/mcp?token=synthetic-private-value",
            "https://mcp.datadoghq.com/mcp?toolsets=logs&token=synthetic-private-value",
            "https://mcp.datadoghq.com/mcp?toolsets=logs&toolsets=metrics",
            "https://mcp.datadoghq.com/mcp?toolsets=",
            "https://mcp.datadoghq.com/mcp?toolsets=logs,,metrics",
            "https://mcp.datadoghq.com/mcp?toolsets=logs%3Btoken%3Dvalue",
            "https://mcp.datadoghq.com:444/mcp?toolsets=logs",
            "http://mcp.datadoghq.com/mcp?toolsets=logs",
            "https://mcp.datadoghq.com.example.com/mcp?toolsets=logs",
            "https://example.com/mcp?toolsets=logs",
        ):
            with self.subTest(url=url):
                self.configure({"datadog": self.http(url=url)})
                result, output = self.run_sync("--apply")
                self.assertEqual(result, 2)
                self.assertIn("only the Datadog toolsets query", output)
                self.assertNotIn("synthetic-private-value", output)
                self.assertFalse((self.home / ".codex").exists())

    def test_malformed_later_config_prevents_all_writes(self):
        for relative, malformed in ((".claude.json", '{"secret":"synthetic-private-value",'), (".grok/config.toml", 'url = "synthetic-private-value')):
            with self.subTest(relative=relative):
                path = self.write(relative, malformed)
                self.configure({"docs": self.http()})
                result, output = self.run_sync("--apply")
                self.assertEqual(result, 2)
                self.assertIn("malformed", output)
                self.assertNotIn("synthetic-private-value", output)
                self.assertEqual(path.read_text(), malformed)
                self.assertFalse((self.home / ".codex/config.toml").exists())
                self.assertFalse(list(self.home.rglob("*.agent-sync-backup-*")))
                path.unlink()

    def test_duplicate_json_keys_fail_unchanged(self):
        path = self.write(".claude.json", '{"mcpServers":{},"mcpServers":{}}')
        self.configure({"docs": self.http()})
        original = path.read_text()
        result, output = self.run_sync("--apply")
        self.assertEqual(result, 2)
        self.assertIn("duplicate JSON key", output)
        self.assertEqual(path.read_text(), original)

    def test_host_exclusion_and_missing_paths_report_skips(self):
        self.configure({
            "remote-only": self.http(hosts=["another-mac"], skip_reason="Requires the other Mac."),
            "local-only": {"transport": "stdio", "command": "true", "requires_paths": ["~/absent"]},
        })
        result, output = self.run_sync("--apply", "--hostname", "this-mac")
        self.assertEqual(result, 0, output)
        self.assertIn("SKIP remote-only", output)
        self.assertIn("SKIP local-only", output)
        self.assertFalse((self.home / ".codex").exists())
        self.assertEqual(self.run_sync("--check", "--hostname", "this-mac")[0], 1)

    def test_missing_command_has_a_specific_skip_reason(self):
        self.configure({"local": {"transport": "stdio", "command": "uninstalled-example-mcp-command"}})
        result, output = self.run_sync("--check")
        self.assertEqual(result, 1)
        self.assertIn("command is unavailable", output)
        self.assertFalse((self.home / ".codex").exists())

    def test_raw_header_secrets_and_unscoped_absolute_paths_are_rejected(self):
        for definition in (self.http(headers={"Authorization": "Bearer synthetic-secret"}), {"transport": "stdio", "command": "/other/mac/server"}):
            with self.subTest(definition=definition):
                self.configure({"docs": definition})
                result, output = self.run_sync("--apply")
                self.assertEqual(result, 2)
                self.assertNotIn("synthetic-secret", output)
                self.assertFalse((self.home / ".codex").exists())

    def test_inline_owned_toml_fails_unchanged(self):
        original = '[mcp_servers]\ndocs = { url = "https://old.example.com/mcp" }\n'
        path = self.write(".codex/config.toml", original)
        self.configure({"docs": self.http()})
        result, output = self.run_sync("--apply", "--replace-existing")
        self.assertEqual(result, 2)
        self.assertIn("inline TOML", output)
        self.assertEqual(path.read_text(), original)

    def test_symlink_config_fails_before_writes(self):
        target = self.write("actual-config.toml", 'model = "local"\n')
        (self.home / ".grok").mkdir()
        (self.home / ".grok/config.toml").symlink_to(target)
        self.configure({"docs": self.http()})
        result, output = self.run_sync("--apply")
        self.assertEqual(result, 2)
        self.assertIn("symlink", output)
        self.assertFalse((self.home / ".codex").exists())
        self.assertEqual(target.read_text(), 'model = "local"\n')

    def test_toml_header_inside_multiline_string_cannot_corrupt_config(self):
        original = (
            'notes = """\n[mcp_servers.docs]\nThis is a string.\n"""\n'
            '[mcp_servers.docs]\nurl = "https://old.example.com/mcp"\n'
        )
        path = self.write(".codex/config.toml", original)
        self.configure({"docs": self.http()})
        result, output = self.run_sync("--apply", "--replace-existing")
        self.assertEqual(result, 2)
        self.assertEqual(path.read_text(), original)
        self.assertFalse((self.home / ".claude.json").exists())

    def test_stale_preview_is_rejected_before_any_writes(self):
        first = self.write("first.json", "first")
        second = self.write("second.json", "new user edit")
        updates = [(first, "first", "changed first"), (second, "old second", "changed second")]
        with self.assertRaises(sync.ConfigError):
            sync.apply_updates(updates)
        self.assertEqual(first.read_text(), "first")
        self.assertEqual(second.read_text(), "new user edit")


if __name__ == "__main__":
    unittest.main()
