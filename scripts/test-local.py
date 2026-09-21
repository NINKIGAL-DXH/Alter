#!/usr/bin/env python3
"""Run the same XCTest methods on CLT-only Macs without an XCTest framework."""
from pathlib import Path
import subprocess, re, json
root = Path(__file__).resolve().parents[1]
source = root / 'Tests/AlterCoreTests/SafetyTests.swift'
out = root / '.build/selftest'
out.mkdir(parents=True, exist_ok=True)
text = source.read_text().replace('import XCTest\n', '').replace('@testable import AlterCore\n', '').replace('#filePath', json.dumps(str(source), ensure_ascii=False))
(out / 'SafetyTests.swift').write_text(text)
methods = re.findall(r'func (test\w+)\(', text)
shim = '''import Foundation
var failures = 0
class XCTestCase { func setUpWithError() throws {} ; func tearDownWithError() throws {} }
func XCTFail(_ message: String = "Assertion failed", file: String = #filePath, line: Int = #line) { failures += 1; print("FAIL \\(file):\\(line): \\(message)") }
func XCTAssertTrue(_ value: @autoclosure () throws -> Bool, file: String = #filePath, line: Int = #line) { do { if try !value() { XCTFail(file: file, line: line) } } catch { XCTFail(String(describing: error), file: file, line: line) } }
func XCTAssertFalse(_ value: @autoclosure () throws -> Bool, file: String = #filePath, line: Int = #line) { do { if try value() { XCTFail(file: file, line: line) } } catch { XCTFail(String(describing: error), file: file, line: line) } }
func XCTAssertEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, file: String = #filePath, line: Int = #line) { do { if try a() != b() { XCTFail(file: file, line: line) } } catch { XCTFail(String(describing: error), file: file, line: line) } }
func XCTAssertNotEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, file: String = #filePath, line: Int = #line) { do { if try a() == b() { XCTFail(file: file, line: line) } } catch { XCTFail(String(describing: error), file: file, line: line) } }
func XCTAssertLessThanOrEqual<T: Comparable>(_ a: T, _ b: T, file: String = #filePath, line: Int = #line) { if a > b { XCTFail(file: file, line: line) } }
func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, file: String = #filePath, line: Int = #line) { do { _ = try expression(); XCTFail("Expected refusal", file: file, line: line) } catch {} }
@main struct RunTests { static func main() {
'''
for name in methods:
    shim += 'do { let test = SafetyTests(); let before = failures; do { try test.setUpWithError(); try test.' + name + '() } catch { XCTFail(String(describing: error)) }; do { try test.tearDownWithError() } catch { XCTFail(String(describing: error)) }; print((failures == before ? "PASS " : "FAIL ") + "' + name + '") }\n'
shim += 'print("Completed '+str(len(methods))+' safety tests; failures: \\(failures)"); exit(failures == 0 ? 0 : 1) } }'
(out / 'Runner.swift').write_text(shim)
subprocess.run(['swiftc','-O','-parse-as-library','-o',str(out/'safety-tests')] + [str(p) for p in (root/'Sources/AlterCore').glob('*.swift')] + [str(out/'SafetyTests.swift'),str(out/'Runner.swift')], check=True)
subprocess.run([str(out/'safety-tests')], check=True)
