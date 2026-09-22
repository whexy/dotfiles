import copy
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("settings", sys.argv.pop(1))
s = importlib.util.module_from_spec(spec)
spec.loader.exec_module(s)


class SettingsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.environment = patch.dict(os.environ, {"HOME": str(self.home)}, clear=True)
        self.environment.start()
        self.addCleanup(self.environment.stop)
        self.secret = self.home / "secret"
        self.secret.write_text("test-key\n")

    def manager(self, name):
        entry = {"label": "api/model", "secrets": {"OPENAI_API_KEY" if name == "codex" else "ANTHROPIC_API_KEY": str(self.secret)}}
        if name == "codex":
            entry["settings"] = {"model": "model", "model_provider": "dotfiles-test", "model_providers": {"dotfiles-test": {"name": "test", "env_key": "OPENAI_API_KEY", "requires_openai_auth": False}}}
        else:
            entry["env"] = {"ANTHROPIC_MODEL": "model", "ANTHROPIC_BASE_URL": "https://test.invalid"}
        return s.AgentSettings({"name": name, "real": "/fake/agent", "fzf": "/fake/fzf", "entries": [{"label": "default"}, entry], "mcpServers": {"owned": {"command": "/new/server"}}, "maintainedSettings": {}, "resetEnv": []})

    def launch(self, manager, args=None):
        with patch.object(os, "execve") as execute:
            manager.launch(args or [])
        return execute.call_args.args

    def test_agenix_credential_path_forms(self):
        getconf_commands = [
            "getconf",
            "/usr/bin/getconf",
            "/nix/store/bk9qiyaah5manlrb6hvqh0dyf1dk7wn8-getconf-system_cmds-1039/bin/getconf",
        ]
        for command in getconf_commands:
            with self.subTest(command=command), patch.object(s.subprocess, "check_output", return_value="/var/folders/fixture/T/\n") as getconf:
                path = s.secret_path(f"$({command} DARWIN_USER_TEMP_DIR)/agenix/key")
                self.assertEqual(path, Path("/var/folders/fixture/T/agenix/key"))
                getconf.assert_called_once_with(["/usr/bin/getconf", "DARWIN_USER_TEMP_DIR"], text=True)
        with patch.dict(os.environ, {"XDG_RUNTIME_DIR": "/run/user/1000"}):
            self.assertEqual(s.secret_path("${XDG_RUNTIME_DIR}/agenix/key"), Path("/run/user/1000/agenix/key"))
        self.assertEqual(s.secret_path("/run/agenix/key"), Path("/run/agenix/key"))

    def test_credential_paths_reject_arbitrary_commands(self):
        for fragment in [
            "$(touch /tmp/unsafe)/agenix/key",
            "$(getconf DARWIN_USER_TEMP_DIR; echo unsafe)/agenix/key",
            "$(/tmp/getconf DARWIN_USER_TEMP_DIR)/agenix/key",
            "$(getconf DARWIN_USER_TEMP_DIR)/$(echo unsafe)",
            "${UNDEFINED_CREDENTIAL_ROOT}/agenix/key",
            "relative/key",
        ]:
            with self.subTest(fragment=fragment), patch.object(s.subprocess, "check_output") as execute:
                with self.assertRaises(s.SettingsError):
                    s.secret_path(fragment)
                execute.assert_not_called()

    def test_persistence_and_no_picker(self):
        for name in ("claude", "codex"):
            manager = self.manager(name)
            manager.reconcile(manager.entries[1])
            path, argv, env = self.launch(manager, ["--help"])
            if name == "codex":
                self.assertEqual(argv, [path, "--help"])
            else:
                self.assertEqual(argv[-1], "--help")
                self.assertEqual(json.loads(argv[2])["env"]["ANTHROPIC_BASE_URL"], "https://test.invalid")
            self.assertIn("test-key", env.values())
            self.assertNotIn("test-key", manager.config.read_text())
            self.assertNotIn("test-key", manager.state.read_text())
            self.assertNotIn("test-key", env[manager.marker])
            self.assertEqual(manager.config.stat().st_mode & 0o777, 0o600)

    def test_comments_unrelated_settings_and_owned_retirement(self):
        manager = self.manager("codex")
        manager.root.mkdir()
        manager.config.write_text('# keep this\nmodel = "user-model"\n[features]\nuser_feature = true\n[mcp_servers.user]\ncommand = "mine"\n')
        manager.reconcile()
        self.assertIn("# keep this", manager.config.read_text())
        manager.manifest["mcpServers"] = {}
        manager.reconcile()
        doc = s.read_document(manager.config)
        self.assertEqual(doc["model"], "user-model")
        self.assertEqual(doc["mcp_servers"]["user"]["command"], "mine")
        self.assertNotIn("owned", doc["mcp_servers"])

    def test_default_login_removes_overrides_preserves_auth(self):
        for name in ("claude", "codex"):
            manager = self.manager(name)
            manager.reconcile(manager.entries[1])
            auth = manager.root / "auth.json"
            auth.write_text('{"login":"untouched"}')
            manager.reconcile(manager.entries[0])
            doc = s.read_document(manager.config)
            self.assertNotIn("model", doc)
            self.assertNotIn("model_provider", doc)
            if name == "claude":
                self.assertNotIn("ANTHROPIC_BASE_URL", doc["env"])
            _, _, env = self.launch(manager)
            self.assertNotIn("test-key", env.values())
            self.assertEqual(auth.read_text(), '{"login":"untouched"}')

    def test_child_snapshot_survives_other_selection(self):
        for name in ("claude", "codex"):
            manager = self.manager(name)
            manager.reconcile(manager.entries[1])
            _, _, parent = self.launch(manager)
            manager.reconcile(manager.entries[0])
            cmux = ["--settings", '{"hooks":{}}'] if name == "claude" else ["-c", "hooks.example=true", "exec", "-m", "child-model", "hello"]
            with patch.dict(os.environ, parent, clear=True):
                _, argv, env = self.launch(manager, cmux)
            if name == "codex":
                self.assertEqual(argv[-len(cmux):], cmux)
            else:
                injected = json.loads(argv[argv.index("--settings") + 1])
                self.assertEqual(injected["hooks"], {})
                self.assertEqual(injected["env"]["ANTHROPIC_BASE_URL"], "https://test.invalid")
                self.assertEqual(argv.count("--settings"), 1)
            self.assertIn("test-key", env.values())
            if name == "codex":
                self.assertIn('model="model"', argv)
                import tomlkit
                for index, value in enumerate(argv):
                    if value == "-c":
                        tomlkit.parse(argv[index + 1])
            else:
                self.assertEqual(env["ANTHROPIC_MODEL"], "model")

    def test_malformed_config_is_not_overwritten(self):
        manager = self.manager("claude")
        manager.root.mkdir()
        manager.config.write_text("not json")
        with self.assertRaises(ValueError):
            manager.reconcile()
        self.assertEqual(manager.config.read_text(), "not json")

    def test_conflicting_writer_and_non_nix_symlink(self):
        path = self.home / "config.json"
        path.write_text("{}")
        with self.assertRaises(s.SettingsError):
            with s.edit_document(path) as doc:
                doc["mine"] = True
                path.write_text('{"other":true}')
        self.assertEqual(json.loads(path.read_text()), {"other": True})
        link = self.home / "link.json"
        link.symlink_to(path)
        with self.assertRaises(s.SettingsError):
            with s.edit_document(link) as doc:
                doc["mine"] = True
        self.assertTrue(link.is_symlink())

    def test_claude_preserves_hooks_and_permissions(self):
        manager = self.manager("claude")
        manager.root.mkdir()
        manager.config.write_text(json.dumps({"hooks": {"Stop": []}, "permissions": {"allow": ["user-rule"]}}))
        manager.manifest["maintainedSettings"] = {"permissions": {"allow": ["Read(/nix/store/**)"]}}
        manager.reconcile(manager.entries[1])
        doc = s.read_document(manager.config)
        self.assertEqual(doc["hooks"], {"Stop": []})
        self.assertEqual(doc["permissions"]["allow"], ["user-rule", "Read(/nix/store/**)"])

    def test_cancel_and_nonterminal_do_not_write(self):
        manager = self.manager("codex")
        with patch.object(sys.stdin, "isatty", return_value=True), patch.object(sys.stdout, "isatty", return_value=True), patch.object(manager, "choose", side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                manager.select("/fake/launcher", [])
        self.assertFalse(manager.state.exists())
        with patch.object(sys.stdin, "isatty", return_value=False):
            with self.assertRaises(s.SettingsError):
                manager.select("/fake/launcher", [])

    def test_claude_settings_merge_preserves_caller_and_cmux(self):
        manager = self.manager("claude")
        manager.reconcile(manager.entries[1])
        hooks = self.home / "cmux.json"
        hooks.write_text(json.dumps({"hooks": {"Stop": [{"hooks": [{"command": "cmux hook"}]}]}, "env": {"CALLER_VAR": "keep"}}))
        args = ["--session-id", "fixture", "--settings", str(hooks), "--settings={\"model\":\"explicit\"}", "--", "--settings", "literal"]
        _, argv, _ = self.launch(manager, args)
        settings = json.loads(argv[2])
        self.assertEqual(settings["model"], "explicit")
        self.assertEqual(settings["env"]["CALLER_VAR"], "keep")
        self.assertEqual(settings["hooks"]["Stop"][0]["hooks"][0]["command"], "cmux hook")
        self.assertEqual(argv[-3:], ["--", "--settings", "literal"])
        self.assertNotIn("hooks", s.read_document(manager.config))

    def test_invalid_secret_does_not_save_or_launch(self):
        manager = self.manager("codex")
        self.secret.write_text("bad\nembedded\n")
        with patch.object(sys.stdin, "isatty", return_value=True), patch.object(sys.stdout, "isatty", return_value=True), patch.object(manager, "choose", return_value=manager.entries[1]):
            with self.assertRaises(s.SettingsError):
                manager.select("/fake/launcher", [])
        self.assertFalse(manager.state.exists())

    def test_custom_config_directory(self):
        custom = self.home / "elsewhere"
        with patch.dict(os.environ, {"CLAUDE_CONFIG_DIR": str(custom)}):
            manager = self.manager("claude")
            manager.reconcile()
            self.assertTrue((custom / "settings.json").exists())
            self.assertTrue((custom / ".claude.json").exists())

    def test_selector_routes_through_cmux_after_save(self):
        manager = self.manager("codex")
        integration = self.home / "cmux" / "shell-integration"
        wrapper = integration.parent / "bin" / "cmux-codex-wrapper"
        wrapper.parent.mkdir(parents=True)
        wrapper.write_text("#!/bin/sh\n")
        wrapper.chmod(0o755)
        with patch.dict(os.environ, {"CMUX_SURFACE_ID": "fixture", "CMUX_SHELL_INTEGRATION_DIR": str(integration)}), patch.object(sys, "platform", "darwin"), patch.object(sys.stdin, "isatty", return_value=True), patch.object(sys.stdout, "isatty", return_value=True), patch.object(manager, "choose", return_value=manager.entries[1]), patch.object(os, "execv", side_effect=SystemExit) as execute:
            with self.assertRaises(SystemExit):
                manager.select("/fake/launcher", ["resume", "--last"])
            self.assertEqual(os.environ["CMUX_CUSTOM_CODEX_PATH"], "/fake/launcher")
        self.assertEqual(execute.call_args.args, (str(wrapper), [str(wrapper), "resume", "--last"]))
        self.assertEqual(s.read_document(manager.config)["model"], "model")

    def test_fusion_persists_role_env(self):
        manager = self.manager("claude")
        entry = copy.deepcopy(manager.entries[1])
        entry["env"]["ANTHROPIC_DEFAULT_OPUS_MODEL"] = "role-model"
        manager.managed_env.add("ANTHROPIC_DEFAULT_OPUS_MODEL")
        manager.reconcile(entry)
        _, _, parent = self.launch(manager)
        with patch.dict(os.environ, parent, clear=True):
            _, _, env = self.launch(manager)
        self.assertEqual(env["ANTHROPIC_DEFAULT_OPUS_MODEL"], "role-model")


unittest.main()
