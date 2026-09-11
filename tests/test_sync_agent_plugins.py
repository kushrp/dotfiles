"""Exercise native installation plans with temporary homes and mocked CLIs."""

import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "bin/sync-agent-plugins.py"
SPEC = importlib.util.spec_from_file_location("sync_agent_plugins", SCRIPT)
sync = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(sync)


class SyncAgentPluginsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name).resolve()
        self.manifest = self.home / "plugins.json"
        self.plugin = {
            "marketplace": "official", "version": "2.0.0",
            "url": "https://github.com/example/formatter.git", "sha": "b" * 40,
        }
        self.catalog = {"url": "https://github.com/example/catalog.git", "sha": "a" * 40}
        self.data = {"version": 1, "marketplaces": {"official": self.catalog}, "plugins": {"formatter": self.plugin}}
        self.manifest.write_text(json.dumps(self.data))
        self.claude = []
        self.grok = []
        self.loaded_extra = []
        self.calls = []
        self.gits = {}
        self.fail_install = False
        self.which = patch.object(sync.shutil, "which", side_effect=lambda name: "/mock/" + name)
        self.which.start()
        self.addCleanup(self.which.stop)
        self.runner = patch.object(sync.Native, "run", side_effect=self.native)
        self.runner.start()
        self.addCleanup(self.runner.stop)

    def write(self, path, data):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data))

    def plugin_files(self, path, name="formatter", version="2.0.0"):
        self.write(path / ".claude-plugin/plugin.json", {"name": name, "version": version})

    def native(self, *args):
        self.calls.append(args)
        if args == ("claude", "plugin", "list", "--json"):
            return json.dumps(self.claude)
        if args == ("grok", "plugin", "list", "--json"):
            return json.dumps(self.grok)
        if args == ("grok", "inspect", "--json"):
            selected = {}
            for row in self.loaded_extra + self.grok:
                if Path(row["path"]).is_dir():
                    selected.setdefault(row["name"], {"name": row["name"], "path": row["path"], "enabled": row.get("enabled", True)})
            return json.dumps({"plugins": list(selected.values())})
        if args[:2] == ("git", "init"):
            Path(args[-1]).mkdir(parents=True)
            return ""
        if args[:2] == ("git", "-C"):
            path = Path(args[2])
            if args[3] == "fetch":
                self.gits[str(path)] = args[-1]
            elif args[3] == "checkout":
                self.write(path / ".claude-plugin/marketplace.json", {
                    "name": "official", "plugins": [{"name": "formatter", "source": {
                        "source": "url", "url": self.plugin["url"], "sha": self.plugin["sha"],
                    }}],
                })
            elif args[3] == "rev-parse":
                if "plugin-marketplaces" in path.parts:
                    return self.catalog["sha"]
                if str(path) not in self.gits:
                    raise sync.PluginError("Git metadata is missing")
                return self.gits[str(path)]
            return ""
        if args[:4] == ("claude", "plugin", "marketplace", "add"):
            path = self.home / ".claude/plugins/known_marketplaces.json"
            existing = json.loads(path.read_text()) if path.exists() else {}
            catalog = json.loads((Path(args[4]) / ".claude-plugin/marketplace.json").read_text())
            existing[catalog["name"]] = {"source": {"source": "directory", "path": args[4]}}
            self.write(path, existing)
            return ""
        if args[:3] in [("claude", "plugin", "install"), ("claude", "plugin", "update")]:
            path = self.home / ".claude/plugins/cache/official/formatter/2.0.0"
            self.plugin_files(path)
            self.claude = [row for row in self.claude if row["id"] != args[3]]
            self.claude.append({"id": args[3], "version": "2.0.0", "scope": "user", "enabled": True, "installPath": str(path)})
            return ""
        if args[:3] == ("claude", "plugin", "enable"):
            next(row for row in self.claude if row["id"] == args[3])["enabled"] = True
            return ""
        if args[:3] == ("claude", "plugin", "disable"):
            next(row for row in self.claude if row["id"] == args[3])["enabled"] = False
            return ""
        if args[:3] == ("grok", "plugin", "install"):
            if self.fail_install:
                raise sync.PluginError("Synthetic native install failure")
            path = self.home / ".grok/installed-plugins/formatter-pinned"
            self.plugin_files(path)
            self.gits[str(path)] = self.plugin["sha"]
            self.grok = [row for row in self.grok if row["path"] != str(path)]
            self.grok.append({"name": "formatter", "repo_key": path.name, "path": str(path), "source": self.plugin["url"], "version": "2.0.0", "enabled": True})
            return ""
        if args[:3] == ("grok", "plugin", "uninstall"):
            row = next(row for row in self.grok if row["name"] == args[3])
            self.assertFalse(Path(row["path"]).exists(), "Source must be backed up before unregistering")
            self.assertEqual(args[-2:], ("--confirm", "--keep-data"))
            self.grok.remove(row)
            return ""
        if args[:3] == ("grok", "plugin", "enable"):
            for row in self.grok:
                if row["name"] == args[3]:
                    row["enabled"] = True
            return ""
        raise AssertionError(args)

    def run_sync(self, *flags):
        output = io.StringIO()
        argv = [str(SCRIPT), "--home", str(self.home), "--manifest", str(self.manifest), *flags]
        with patch("sys.argv", argv), contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
            result = sync.main()
        return result, output.getvalue()

    def test_preview_does_not_change_the_home(self):
        before = list(self.home.rglob("*"))
        result, output = self.run_sync()
        self.assertEqual(result, 0, output)
        self.assertIn("Preview only", output)
        self.assertIn("formatter", output)
        self.assertEqual(before, list(self.home.rglob("*")))
        self.assertTrue(all(args[2] in ("list", "--json") for args in self.calls))

    def test_apply_is_idempotent_and_preserves_other_plugins(self):
        self.claude.append({"id": "warp@warp", "enabled": True, "scope": "user"})
        path = self.home / ".claude/plugins/known_marketplaces.json"
        self.write(path, {"warp": {"source": {"source": "github", "repo": "example/warp"}}})
        result, output = self.run_sync("--apply")
        self.assertEqual(result, 0, output)
        self.assertTrue(any(row["id"] == "warp@warp" for row in self.claude))
        self.assertIn("warp", json.loads(path.read_text()))
        self.assertTrue(any(args[:3] == ("grok", "plugin", "install") and args[-1] == "--trust" for args in self.calls))
        self.assertEqual(self.run_sync("--check")[0], 0)
        self.calls.clear()
        result, output = self.run_sync("--apply")
        self.assertEqual(result, 0, output)
        mutations = [args for args in self.calls if args[0] != "git" and args[2] not in ("list", "--json")]
        self.assertEqual(mutations, [])

    def test_reserved_catalog_alias_preserves_the_official_registry_and_other_plugins(self):
        self.catalog["registration_name"] = "kush-pinned-plugins"
        self.manifest.write_text(json.dumps(self.data))
        registry = self.home / ".claude/plugins/known_marketplaces.json"
        official = {"source": {"source": "github", "repo": "example/catalog"}}
        self.write(registry, {"official": official})
        old_path = self.home / ".claude/plugins/cache/official/formatter/1.0.0"
        self.plugin_files(old_path, version="1.0.0")
        self.claude.extend([
            {"id": "formatter@official", "scope": "user", "enabled": True, "installPath": str(old_path)},
            {"id": "warp@official", "scope": "user", "enabled": True},
        ])
        result, output = self.run_sync("--apply")
        self.assertEqual(result, 0, output)
        self.assertEqual(json.loads(registry.read_text())["official"], official)
        self.assertFalse(next(row for row in self.claude if row["id"] == "formatter@official")["enabled"])
        self.assertTrue(next(row for row in self.claude if row["id"] == "formatter@kush-pinned-plugins")["enabled"])
        self.assertTrue(next(row for row in self.claude if row["id"] == "warp@official")["enabled"])
        self.assertTrue(old_path.exists())
        source_catalog = sync.marketplace_path(self.home, "official", self.catalog) / ".claude-plugin/marketplace.json"
        self.assertEqual(json.loads(source_catalog.read_text())["name"], "official")
        self.assertEqual(self.run_sync("--check")[0], 0)
        self.calls.clear()
        self.assertEqual(self.run_sync("--apply")[0], 0)
        self.assertFalse(any(args[2] in ("install", "disable", "update", "marketplace") for args in self.calls if args[0] == "claude"))

    def add_old_copy(self, path=None):
        path = path or self.home / ".grok/installed-plugins/old-copy"
        self.plugin_files(path, version="1.0.0")
        (path / "user-note.txt").write_text("Preserve my local edit")
        self.grok.append({"name": "formatter", "repo_key": path.name, "source": "/old/claude/cache", "path": str(path), "version": "1.0.0"})
        return path

    def test_duplicate_requires_adoption_before_native_mutations(self):
        path = self.add_old_copy()
        result, output = self.run_sync("--apply")
        self.assertEqual(result, 2, output)
        self.assertIn("--adopt", output)
        self.assertTrue(path.exists())
        self.assertFalse(any(args[:3] == ("claude", "plugin", "marketplace") for args in self.calls))

    def test_adoption_preserves_all_old_files_in_a_backup(self):
        path = self.add_old_copy()
        result, output = self.run_sync("--apply", "--adopt")
        self.assertEqual(result, 0, output)
        self.assertFalse(path.exists())
        backups = list((self.home / ".local/state/mac-config/plugin-backups").glob("*/*-old-copy/user-note.txt"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), "Preserve my local edit")
        self.assertEqual(self.run_sync("--check")[0], 0)

    def test_adoption_recovers_an_already_backed_up_native_registration(self):
        path = self.add_old_copy()
        backup = self.home / ".local/state/mac-config/plugin-backups/earlier/0-old-copy"
        backup.parent.mkdir(parents=True)
        path.rename(backup)
        result, output = self.run_sync("--apply", "--adopt")
        self.assertEqual(result, 0, output)
        self.assertEqual(len(self.grok), 1)
        self.assertEqual(self.grok[0]["source"], self.plugin["url"])
        self.assertEqual((backup / "user-note.txt").read_text(), "Preserve my local edit")

    def test_adoption_reinstalls_a_pin_when_an_older_duplicate_also_exists(self):
        self.assertEqual(self.run_sync("--apply")[0], 0)
        self.add_old_copy()
        result, output = self.run_sync("--apply", "--adopt")
        self.assertEqual(result, 0, output)
        self.assertEqual(len(self.grok), 1)
        self.assertEqual(self.run_sync("--check")[0], 0)

    def test_adoption_refuses_a_repository_shared_with_another_plugin(self):
        path = self.add_old_copy()
        self.grok.append({"name": "warp", "repo_key": path.name, "path": str(path)})
        result, output = self.run_sync("--apply", "--adopt")
        self.assertEqual(result, 2, output)
        self.assertIn("repository also contains other plugins", output)
        self.assertTrue(path.exists())

    def test_adoption_refuses_an_unmanaged_location(self):
        path = self.add_old_copy(self.home / "my-personal-plugin")
        result, output = self.run_sync("--apply", "--adopt")
        self.assertEqual(result, 2, output)
        self.assertIn("unmanaged source", output)
        self.assertTrue(path.exists())

    def test_failed_install_retains_the_backup(self):
        self.add_old_copy()
        self.fail_install = True
        result, output = self.run_sync("--apply", "--adopt")
        self.assertEqual(result, 2, output)
        self.assertIn("Synthetic native install failure", output)
        self.assertEqual(len(list(self.home.glob(".local/state/mac-config/plugin-backups/*/*-old-copy/user-note.txt"))), 1)

    def test_adoption_moves_only_the_obsolete_marketplace_plugin(self):
        path = self.home / ".claude/plugins/marketplaces/official/plugins/formatter"
        self.plugin_files(path, version="1.0.0")
        sibling = path.parent / "warp"
        self.plugin_files(sibling, name="warp", version="3.0.0")
        self.loaded_extra.append({"name": "formatter", "path": str(path), "enabled": True})
        self.assertEqual(self.run_sync("--apply")[0], 2)
        result, output = self.run_sync("--apply", "--adopt")
        self.assertEqual(result, 0, output)
        self.assertFalse(path.exists())
        self.assertTrue(sibling.exists())
        self.assertEqual(len(list(self.home.glob(".local/state/mac-config/plugin-backups/*/*-formatter/.claude-plugin/plugin.json"))), 1)

    def test_check_rejects_a_catalog_with_an_unpinned_plugin_source(self):
        self.assertEqual(self.run_sync("--apply")[0], 0)
        path = sync.marketplace_path(self.home, "official", self.catalog) / ".claude-plugin/marketplace.json"
        catalog = json.loads(path.read_text())
        del catalog["plugins"][0]["source"]["sha"]
        path.write_text(json.dumps(catalog))
        result, output = self.run_sync("--check")
        self.assertEqual(result, 2, output)
        self.assertIn("does not match the immutable plugin pin", output)

    def test_check_reads_the_loaded_manifest_instead_of_inventory_version(self):
        self.assertEqual(self.run_sync("--apply")[0], 0)
        self.plugin_files(Path(self.grok[0]["path"]), version="wrong")
        result, output = self.run_sync("--check")
        self.assertEqual(result, 1, output)
        self.assertIn("expected loaded version", output)

    def test_check_rejects_an_unrelated_loaded_copy_with_the_same_version(self):
        self.assertEqual(self.run_sync("--apply")[0], 0)
        unrelated = self.home / "custom-formatter"
        self.plugin_files(unrelated)
        self.loaded_extra.append({"name": "formatter", "path": str(unrelated), "enabled": True})
        result, output = self.run_sync("--check")
        self.assertEqual(result, 1, output)
        self.assertIn("loaded path is not a verified pinned source", output)

    def test_check_rejects_a_different_git_commit(self):
        self.assertEqual(self.run_sync("--apply")[0], 0)
        self.gits[self.grok[0]["path"]] = "c" * 40
        result, output = self.run_sync("--check")
        self.assertEqual(result, 1, output)
        self.assertIn("pinned native installation is missing", output)

    def test_missing_cli_reports_failure_without_inventory_calls(self):
        with patch.object(sync.shutil, "which", return_value=None):
            result, output = self.run_sync("--check")
        self.assertEqual(result, 1, output)
        self.assertIn("MISSING CLI grok", output)
        self.assertEqual(self.calls, [])

    def test_manifest_rejects_a_secret_or_unpinned_source(self):
        self.data["plugins"]["formatter"]["url"] = "https://token@github.com/example/formatter.git"
        self.manifest.write_text(json.dumps(self.data))
        result, output = self.run_sync("--apply")
        self.assertEqual(result, 2, output)
        self.assertNotIn("token@", output)
        self.assertEqual(self.calls, [])


if __name__ == "__main__":
    unittest.main()
