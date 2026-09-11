import importlib.machinery
import importlib.util
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "bin" / "mac-config"


def load_module():
    loader = importlib.machinery.SourceFileLoader("mac_config", str(SCRIPT))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class ConfigTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.module = load_module()

    def test_preview_does_not_replace_user_file(self):
        source = self.home / "source"
        source.write_text("shared")
        target = self.home / "target"
        target.write_text("local")
        self.module.link(source, target, self.home / "backup", False)
        self.assertEqual(target.read_text(), "local")
        self.assertFalse((self.home / "backup").exists())

    def test_shell_override_cannot_source_itself(self):
        dotfiles = self.home / "dotfiles"
        dotfiles.mkdir()
        (dotfiles / ".zshrc").write_text("shared")
        (self.home / ".zshrc").write_text('source "$HOME/.zshrc.local"\n')
        with self.assertRaises(self.module.ConfigFailure):
            self.module.preserve_local_shell(self.home, dotfiles, True)
        self.assertFalse((self.home / ".zshrc.local").exists())

    def test_backup_preserves_conflicting_files_and_repeats_without_changes(self):
        source = self.home / "source"
        source.write_text("shared")
        target = self.home / "target"
        target.write_text("local")
        backup = self.home / "backup"
        self.module.link(source, target, backup, True)
        self.assertEqual(target.resolve(), source.resolve())
        self.assertEqual([p.read_text() for p in backup.rglob("target")], ["local"])
        before = target.lstat().st_mtime_ns
        self.module.link(source, target, backup, True)
        self.assertEqual(target.lstat().st_mtime_ns, before)

    def test_repository_migration_repairs_existing_worktree(self):
        repo = self.home / ".agents"
        repo.mkdir()
        subprocess.run(["git", "init", "-q", str(repo)], check=True)
        subprocess.run(["git", "-C", str(repo), "-c", "user.name=Test", "-c",
                        "user.email=test@example.com", "commit", "--allow-empty", "-qm", "initial"], check=True)
        worktree = self.home / "worktree"
        subprocess.run(["git", "-C", str(repo), "worktree", "add", "-qb", "test", str(worktree)], check=True)
        source = self.home / "runtime"
        source.mkdir()
        (repo / "uncommitted").write_text("preserved")
        self.module.link(source, repo, self.home / "backup", True)
        self.assertEqual(repo.resolve(), source.resolve())
        result = subprocess.run(["git", "-C", str(worktree), "status", "--porcelain"], capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(list((self.home / "backup").rglob("uncommitted"))), 1)

    def test_dirty_repository_blocks_sync_before_fetch(self):
        repo = self.home / "repo"
        subprocess.run(["git", "init", "-q", str(repo)], check=True)
        (repo / "untracked").write_text("local")
        with self.assertRaises(self.module.ConfigFailure):
            self.module.require_clean(repo)

    def test_path_escape_cannot_be_published(self):
        with self.assertRaises(self.module.ConfigFailure):
            self.module.validate_publish_paths(self.home, ["../secret"])
        with self.assertRaises(self.module.ConfigFailure):
            self.module.validate_publish_paths(self.home, [".extra"])

    def test_directory_cannot_include_local_credentials(self):
        skill = self.home / "skills/example"
        skill.mkdir(parents=True)
        (skill / "credentials.json").write_text("local")
        with self.assertRaises(self.module.ConfigFailure):
            self.module.validate_publish_paths(self.home, ["skills/example"])

    def test_git_pathspec_cannot_expand_publish_scope(self):
        with self.assertRaises(self.module.ConfigFailure):
            self.module.validate_publish_paths(self.home, [":(glob)**"])

    def test_background_path_resolves_mise_and_client_binaries(self):
        shim = self.home / ".local/share/mise/shims/npx"
        client = self.home / ".grok/bin/grok"
        for executable in (shim, client):
            executable.parent.mkdir(parents=True)
            executable.write_text("#!/bin/sh\nexit 0\n")
            executable.chmod(0o755)
        config = {"repos": {"dotfiles": {"path": str(self.home / "dotfiles")}}}
        with patch.object(self.module.Path, "home", return_value=self.home), \
                patch.object(self.module.sys, "platform", "darwin"), \
                patch.object(self.module.subprocess, "run", return_value=SimpleNamespace(returncode=1)), \
                patch.object(self.module, "run"):
            self.module.auto_sync(self.home, config)
        plist = self.home / "Library/LaunchAgents" / f"{self.module.LABEL}.plist"
        environment = plistlib.loads(plist.read_bytes())["EnvironmentVariables"]
        self.assertEqual(shutil.which("npx", path=environment["PATH"]), str(shim))
        self.assertEqual(shutil.which("grok", path=environment["PATH"]), str(client))

    def git(self, path, *args):
        return subprocess.run(["git", "-C", str(path), "-c", "user.name=Test",
                               "-c", "user.email=test@example.com", *args],
                              check=True, capture_output=True, text=True).stdout.strip()

    def repositories(self):
        config = {"version": 1, "repos": {}}
        for name in ("dotfiles", "agents"):
            source = self.home / (name + "-origin")
            source.mkdir()
            self.git(source, "init", "-q", "-b", "test-sync")
            (source / "value").write_text("first")
            self.git(source, "add", "value")
            self.git(source, "commit", "-qm", "first")
            target = self.home / name
            self.git(self.home, "clone", "-q", str(source), str(target))
            config["repos"][name] = {"path": str(target), "branch": "test-sync"}
        return config

    def advance(self, name, value):
        source = self.home / name
        (source / "value").write_text(value)
        self.git(source, "commit", "-qam", value)

    def test_sync_fast_forwards_both_repositories_before_installation(self):
        config = self.repositories()
        for name in ("dotfiles-origin", "agents-origin"):
            self.advance(name, "second")
        with patch.object(self.module, "install") as install:
            self.module.sync(self.home, config)
        install.assert_called_once_with(self.home, config, True, quiet=True)
        for name in ("dotfiles", "agents"):
            self.assertEqual((self.home / name / "value").read_text(), "second")

    def test_dirty_second_repository_leaves_first_unchanged(self):
        config = self.repositories()
        self.advance("dotfiles-origin", "second")
        (self.home / "agents/untracked").write_text("preserved")
        with self.assertRaises(self.module.ConfigFailure):
            self.module.sync(self.home, config)
        self.assertEqual((self.home / "dotfiles/value").read_text(), "first")

    def test_diverged_second_repository_leaves_first_unchanged(self):
        config = self.repositories()
        self.advance("dotfiles-origin", "second")
        self.advance("agents-origin", "remote")
        self.advance("agents", "local")
        with self.assertRaises(self.module.ConfigFailure):
            self.module.sync(self.home, config)
        self.assertEqual((self.home / "dotfiles/value").read_text(), "first")
        self.assertEqual((self.home / "agents/value").read_text(), "local")

    def test_publish_refuses_preexisting_unpublished_commits(self):
        config = self.repositories()
        self.advance("agents", "unpublished")
        (self.home / "agents/value").write_text("selected update")
        args = SimpleNamespace(repo="agents", paths=["value"], message="selected update")
        with self.assertRaises(self.module.ConfigFailure):
            self.module.publish(config, args)
        self.assertEqual((self.home / "agents-origin/value").read_text(), "first")
        self.assertEqual(self.git(self.home / "agents", "diff", "--cached", "--name-only"), "")


if __name__ == "__main__":
    unittest.main()
