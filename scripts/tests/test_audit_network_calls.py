#!/usr/bin/env python3
"""Copaky: bounded offline-gate regressions; all sources and CI commands are synthetic."""

import contextlib
import importlib.util
import io
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

SCRIPTS = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("audit_network_calls", SCRIPTS / "audit_network_calls.py")
audit = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(audit)
MANIFEST = '''import PackageDescription
let dependencies = [
    .package(url: "https://github.com/pettipol/AzooKeyKanaKanjiConverter", revision: "21e2bdcf59ec3cc91610bac6696b2e0c6402a296"),
    .package(url: "https://github.com/azooKey/CustardKit", revision: "7bddc14eb3f8f0145c6f3a4fea20cf394f8104e8"),
]
'''


class OfflineAuditTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="copaky-offline-test-")
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        self.write("Keyboard/Display/Keyboard.swift", "let offline = true\n")
        for target in audit.SHARED_TARGETS:
            self.write(f"AzooKeyCore/Sources/{target}/Local.swift", "let offline = true\n")
        (self.repo / "azooKey_emoji_dictionary_storage/EmojiDictionary").mkdir(parents=True)
        self.write(audit.MANIFEST, MANIFEST)

    def write(self, relative: str, text: str) -> Path:
        path = self.repo / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def run_audit(self) -> tuple[int, str]:
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            result = audit.main(["audit", str(self.repo)])
        return result, output.getvalue()

    def test_clean_sources_and_exact_build_metadata_pass(self) -> None:
        rc, output = self.run_audit()
        self.assertEqual(rc, 0, output)
        self.assertIn("OFFLINE_STATIC=PASS", output)
        self.assertIn("OFFLINE_RUNTIME=NOT_RUN", output)
        self.assertIn("External dependency sources: NOT_SCANNED", output)
        self.assertEqual(output.count("[ALLOW]"), 2, output)

    def test_network_reference_in_every_extension_shared_or_synchronized_root_fails(self) -> None:
        roots = ["Keyboard", *[f"AzooKeyCore/Sources/{target}" for target in audit.SHARED_TARGETS], audit.SOURCE_ROOTS[2]]
        for root in roots:
            with self.subTest(root=root):
                path = self.write(f"{root}/Network.swift", "let task = URLSession.shared\n")
                rc, output = self.run_audit()
                self.assertEqual(rc, 1, output)
                self.assertIn(f"[BLOCK] {root}/Network.swift:1 URL_LOADING", output)
                self.assertIn("OFFLINE_STATIC=FAIL", output)
                path.unlink()

    def test_network_api_families_and_url_strings_fail(self) -> None:
        for source in ('let request: URLRequest', 'let s = NWConnection.self', 'nw_connection_create()',
                       'let s = socket(0, 0, 0)', 'let s = socket /* note */\n(0, 0, 0)',
                       'import Network', 'import\nWebKit',
                       'let s = AsyncImage.self', 'let url = #"https://example.invalid"#'):
            with self.subTest(source=source):
                self.write("Keyboard/Probe.swift", source)
                rc, output = self.run_audit()
                self.assertEqual(rc, 1, output)

    def test_comments_cannot_hide_trailing_code_or_urls(self) -> None:
        self.write("Keyboard/Probe.swift", '''/* URLSession
            /* nested https://example.invalid */
        */ let session = URLSession.shared // explanatory comment
        let url = "https://example.invalid" // still an HTTP string
        ''')
        rc, output = self.run_audit()
        self.assertEqual(rc, 1, output)
        self.assertIn("Keyboard/Probe.swift:3 URL_LOADING", output)
        self.assertIn("Keyboard/Probe.swift:4 HTTP_URL", output)
        self.assertIn("blocked: 2", output)

    def test_comment_only_references_do_not_fail(self) -> None:
        self.write("Keyboard/Probe.swift", '/* URLSession /* nested */ https://example.invalid */\n// URLRequest\nlet text = "// is text"\n')
        rc, output = self.run_audit()
        self.assertEqual(rc, 0, output)

    def test_regex_literals_cannot_hide_network_code(self) -> None:
        for literal in (r'/\//', r'#/\//#', '#/ // /#', r'##/\//##'):
            with self.subTest(literal=literal):
                self.write("Keyboard/Probe.swift", f"let slash = {literal}; let task = URLSession.shared")
                rc, output = self.run_audit()
                self.assertEqual(rc, 2, output)
                self.assertIn("requires lexer review", output)
                self.assertIn("OFFLINE_STATIC=ERROR", output)

    def test_spaced_division_and_comments_remain_scannable(self) -> None:
        self.write("Keyboard/Probe.swift", 'let ratio = 10 / 2 // arithmetic only\nlet text = #"/not a regex/"#')
        rc, output = self.run_audit()
        self.assertEqual(rc, 0, output)

    def test_string_comment_tokens_interpolations_and_multiline_urls_remain_visible(self) -> None:
        probes = (
            'let url = "https://example.invalid/path/*literal*/"',
            'let text = "prefix \\(URL(string: "https://example.invalid"))"',
            'let text = #"prefix \\#(URL(string: #"https://example.invalid"#))"#',
            'let text = """\nhttps://example.invalid\n"""',
            'let text = #"literal \\" // https://example.invalid"#',
            'let text = "prefix \\({ /* comment */ URLSession.shared }())"',
        )
        for source in probes:
            with self.subTest(source=source):
                self.write("Keyboard/Probe.swift", source)
                rc, output = self.run_audit()
                self.assertEqual(rc, 1, output)

    def test_comments_inside_interpolation_are_masked_without_masking_code(self) -> None:
        self.write("Keyboard/Probe.swift", 'let text = "prefix \\(1 /* URLSession; https://example.invalid */)"')
        rc, output = self.run_audit()
        self.assertEqual(rc, 0, output)

    def test_no_substring_based_directory_exclusions_within_source_scope(self) -> None:
        self.write("Keyboard/Contests/MainAppHelper/Probe.swift", "URLSession.shared")
        rc, output = self.run_audit()
        self.assertEqual(rc, 1, output)

    def test_known_mainapp_and_test_targets_are_outside_declared_scope(self) -> None:
        for path in ("MainApp/Network.swift", "MainAppUITests/Network.swift", "AzooKeyCore/Tests/Network.swift"):
            self.write(path, "URLSession.shared")
        rc, output = self.run_audit()
        self.assertEqual(rc, 0, output)

    def test_exception_does_not_authorize_runtime_copy_or_additional_api(self) -> None:
        line = MANIFEST.splitlines()[2]
        for path, source in (("Keyboard/Probe.swift", line), (audit.MANIFEST, MANIFEST + "URLSession.shared\n")):
            with self.subTest(path=path):
                self.write(path, source)
                rc, output = self.run_audit()
                self.assertEqual(rc, 1, output)
                if path != audit.MANIFEST:
                    (self.repo / path).unlink()

    def test_changed_missing_or_duplicated_manifest_exceptions_fail_closed(self) -> None:
        for manifest in (MANIFEST.replace("21e2bdcf", "00000000"), MANIFEST + MANIFEST.splitlines()[2], "import PackageDescription\n"):
            with self.subTest(manifest=manifest):
                self.write(audit.MANIFEST, manifest)
                rc, output = self.run_audit()
                self.assertEqual(rc, 2, output)
                self.assertIn("OFFLINE_STATIC=ERROR", output)

    def test_missing_empty_or_unreadable_inputs_error(self) -> None:
        for target in audit.SHARED_TARGETS:
            with self.subTest(target=target):
                path = self.repo / f"AzooKeyCore/Sources/{target}/Local.swift"
                path.unlink()
                rc, output = self.run_audit()
                self.assertEqual(rc, 2, output)
                self.write(str(path.relative_to(self.repo)), "let value = 1")
        (self.repo / audit.MANIFEST).unlink()
        rc, output = self.run_audit()
        self.assertEqual(rc, 2, output)
        self.assertIn("OFFLINE_STATIC=ERROR", output)

    def test_decoding_unterminated_source_and_native_source_errors(self) -> None:
        path = self.repo / "Keyboard/Probe.swift"
        for content in (b'\xffURLSession.shared', b'/* unfinished', b'let text = "unfinished'):
            with self.subTest(content=content):
                path.write_bytes(content)
                rc, output = self.run_audit()
                self.assertEqual(rc, 2, output)
        path.unlink()
        self.write("Keyboard/Network.m", "void f() {}")
        rc, output = self.run_audit()
        self.assertEqual(rc, 2, output)
        self.assertIn("unsupported native source", output)

    def test_read_and_walk_errors_are_not_success(self) -> None:
        for target in ("pathlib.Path.read_text", "audit_network_calls.os.walk"):
            # Patch the imported module directly (no dependency on sys.modules import state).
            patch = mock.patch.object(Path, "read_text", side_effect=PermissionError("read denied")) if target.startswith("pathlib") else mock.patch.object(audit.os, "walk", side_effect=OSError("walk failed"))
            with self.subTest(target=target), patch:
                rc, output = self.run_audit()
                self.assertEqual(rc, 2, output)
                self.assertIn("OFFLINE_STATIC=ERROR", output)

    def test_symlinked_source_is_an_error(self) -> None:
        (self.repo / "Keyboard/Link.swift").symlink_to(self.repo / "Keyboard/Display/Keyboard.swift")
        rc, output = self.run_audit()
        self.assertEqual(rc, 2, output)
        self.assertIn("symlink", output)

    def test_cli_invalid_input_and_real_exit_codes(self) -> None:
        script = str(SCRIPTS / "audit_network_calls.py")
        for args, expected in (([], 2), ([str(self.repo / "absent")], 2), ([str(self.repo / audit.MANIFEST)], 2), ([str(self.repo)], 0)):
            with self.subTest(args=args):
                run = subprocess.run([sys.executable, script, *args], capture_output=True, text=True, timeout=10)
                self.assertEqual(run.returncode, expected, run.stdout + run.stderr)
                self.assertIn("OFFLINE_STATIC=", run.stdout)
        self.write("Keyboard/Probe.swift", "URLSession.shared")
        run = subprocess.run([sys.executable, script, str(self.repo)], capture_output=True, text=True, timeout=10)
        self.assertEqual(run.returncode, 1, run.stdout + run.stderr)

    def run_stubbed_ci(self, *, fast: bool = False, missing_scanner: bool = False, harness_case: str = "pass") -> subprocess.CompletedProcess[str]:
        """Git/Xcode are stubs; Python runs the audit and synthetic harness tests."""
        scripts = self.repo / "scripts"
        scripts.mkdir(exist_ok=True)
        shutil.copyfile(SCRIPTS / "ci-local.sh", scripts / "ci-local.sh")
        scanner = scripts / "audit_network_calls.py"
        if missing_scanner:
            scanner.unlink(missing_ok=True)
        else:
            shutil.copyfile(SCRIPTS / scanner.name, scanner)
        test_dir = scripts / "tests"
        if test_dir.exists():
            shutil.rmtree(test_dir)
        if harness_case != "missing_directory":
            test_dir.mkdir()
            for name in ("test_audit_network_calls", "test_memory_phase_c_validate", "test_additional"):
                if harness_case == f"missing_{name}":
                    continue
                content = "import unittest\nclass SyntheticTest(unittest.TestCase):\n    def test_synthetic(self):\n        self.assertTrue(True)\n"
                if harness_case == "empty" or harness_case == f"empty_{name}":
                    content = "# Intentionally empty synthetic module\n"
                elif harness_case == "failed" and name == "test_additional":
                    content = content.replace("assertTrue(True)", "assertTrue(False)")
                (test_dir / f"{name}.py").write_text(content, encoding="utf-8")
        stubs = self.repo / "stubs"
        stubs.mkdir(exist_ok=True)
        commands = {
            "git": '#!/bin/sh\ncase "$*" in *grep*) exit 1;; *) echo .githooks;; esac\n',
            "xcodebuild": '#!/bin/sh\necho "STUB xcodebuild: NOT_RUN"\nexit 0\n',
            "python3": '#!/bin/sh\ncase "$1" in */audit_network_calls.py|-) exec ' + shlex.quote(sys.executable) + ' "$@";; *) echo "STUB non-audit Python: NOT_RUN"; exit 0;; esac\n',
        }
        for name, content in commands.items():
            path = stubs / name
            path.write_text(content, encoding="utf-8")
            path.chmod(0o755)
        env = dict(os.environ, PATH=f"{stubs}:/usr/bin:/bin")
        return subprocess.run(["/bin/bash", str(scripts / "ci-local.sh"), *(["--fast"] if fast else [])], env=env, capture_output=True, text=True, timeout=10)

    def test_full_ci_gate_propagates_pass_violation_and_scanner_error(self) -> None:
        for source, expected in (("let offline = true", 0), ("URLSession.shared", 1), ('let text = "unfinished', 1)):
            with self.subTest(source=source):
                self.write("Keyboard/Probe.swift", source)
                run = self.run_stubbed_ci()
                self.assertEqual(run.returncode, expected, run.stdout + run.stderr)
                self.assertIn("STUB xcodebuild: NOT_RUN", run.stdout)
                self.assertIn("Ran 3 tests", run.stderr)
                self.assertIn("ci-local: PASS" if expected == 0 else "ci-local: FAIL", run.stdout)
        run = self.run_stubbed_ci(missing_scanner=True)
        self.assertEqual(run.returncode, 1, run.stdout + run.stderr)
        self.assertIn("scanner exit 2", run.stdout)

    def test_ci_harness_missing_empty_and_failed_tests_fail_closed(self) -> None:
        for case in ("missing_directory", "missing_test_audit_network_calls", "missing_test_memory_phase_c_validate",
                     "empty", "empty_test_audit_network_calls", "empty_test_memory_phase_c_validate", "failed"):
            with self.subTest(case=case):
                run = self.run_stubbed_ci(harness_case=case)
                self.assertEqual(run.returncode, 1, run.stdout + run.stderr)
                self.assertIn("harness regression tests FAILED", run.stdout)

    def test_fast_ci_reports_static_audit_not_run(self) -> None:
        self.write("Keyboard/Probe.swift", "URLSession.shared")
        run = self.run_stubbed_ci(fast=True)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertIn("OFFLINE_STATIC=NOT_RUN (--fast)", run.stdout)


if __name__ == "__main__":
    unittest.main()
