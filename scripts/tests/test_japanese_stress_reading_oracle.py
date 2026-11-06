"""Execute the exact pure system-reading block used by the test42 UI fallback."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


class JapaneseStressSystemReadingTests(unittest.TestCase):
    @unittest.skipUnless(sys.platform == "darwin" and shutil.which("swift"), "Apple CoreFoundation/Swift required")
    def test_actual_ui_oracle_positive_negative_and_ambiguous_readings(self):
        ui = Path(__file__).resolve().parents[2] / "MainAppUITests" / "MainAppUITests.swift"
        source = ui.read_text()
        block = source.split("// BEGIN COPAKY_SYSTEM_READING_ORACLE\n", 1)[1].split(
            "// END COPAKY_SYSTEM_READING_ORACLE", 1)[0]
        driver = r'''
let cases: [(String, String?)] = [
    ("課さた", "かさた"), ("坂", "さか"), ("咲か", "さきか"),
    ("さか", "さか"), ("かさた", "かさた"), ("はまや", "はまや"),
    ("5坂", nil), ("X坂", nil), ("坂5", nil), (" 坂", nil), ("坂。", nil),
    ("別坂", "べつさか"), ("坂さ", "さかさ"), ("課さたあ", "かさたあ"),
    ("5課さた", nil), ("課さだ", "かさだ"), ("仮さた", "かさた"),
    ("生", "なま"), ("日本", "にっぽん"), ("今日", "きょう"),
    ("\u{200B}坂", nil), ("坂\u{200B}", nil), ("", nil),
    (String(repeating: "か", count: 33), nil)
]
var receipts: [[String: Any]] = []
for (input, expected) in cases {
    let result = copakyCompleteJapaneseSystemReading(input)
    guard result?.kana == expected else { fatalError("Oracle regression for controlled fixture: \(input)") }
    if let result {
        guard result.utf16Length == (input as NSString).length, result.tokenCount > 0 else {
            fatalError("Incomplete source coverage")
        }
    }
    receipts.append(["input": input, "reading": result?.kana as Any? ?? NSNull(),
                     "fullCoverage": result != nil, "matchedFixture": true])
}
print(String(decoding: try JSONSerialization.data(withJSONObject: receipts, options: [.sortedKeys]), as: UTF8.self))
'''
        with tempfile.TemporaryDirectory(prefix="copaky-system-reading-") as directory:
            swift = Path(directory) / "oracle.swift"
            swift.write_text("import Foundation\nimport CoreFoundation\n" + block + driver)
            result = subprocess.run([shutil.which("swift"), "-module-cache-path", str(Path(directory) / "cache"), str(swift)],
                                    capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stderr[-4000:])
            receipts = json.loads(result.stdout)
            self.assertEqual(len(receipts), 24)
            self.assertTrue(all(item["matchedFixture"] for item in receipts))

    def test_fallback_is_opt_in_and_restricted_to_long_test42_groups(self):
        ui = Path(__file__).resolve().parents[2] / "MainAppUITests" / "MainAppUITests.swift"
        source = ui.read_text()
        self.assertIn("allowLongStressSystemReading: Bool = false", source)
        self.assertEqual(source.count("allowLongStressSystemReading:"), 2,
                         "Only test42 may explicitly opt in; the other occurrence is the default-false parameter")
        fallback = source.split("if allowLongStressSystemReading,", 1)[1].split("return (converted,", 1)[0]
        self.assertIn('["かさた", "はまや"].contains(reading)', fallback)
        self.assertIn("readings.count == 0", fallback)
        self.assertIn("system.kana == reading", fallback)
        self.assertIn("field.value as? String == converted", fallback)


if __name__ == "__main__":
    unittest.main()
