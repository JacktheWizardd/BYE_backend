import Foundation
import AppKit
import Darwin

// A native host, deliberately independent of BYE's production summary provider.
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let root = Bundle.main.bundleURL.appendingPathComponent("Contents")
let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 3 else { fputs("usage: BYEBenchmark PID_FILE LOG_FILE SERVER_ARGS...\n", stderr); exit(64) }
let child = Process()
child.executableURL = root.appendingPathComponent("MacOS/runtime/llama-server")
child.arguments = Array(arguments.dropFirst(2))
var environment = ProcessInfo.processInfo.environment
// Do not inherit external runtime/model paths or llama configuration.
environment = environment.filter { !$0.key.hasPrefix("LLAMA_") && !$0.key.hasPrefix("DYLD_") }
child.environment = environment
FileManager.default.createFile(atPath: arguments[1], contents: nil)
let log = try FileHandle(forWritingTo: URL(fileURLWithPath: arguments[1]))
child.standardOutput = log
child.standardError = log
try child.run()
let state: [String: Any] = ["host": ProcessInfo.processInfo.processIdentifier,
                            "runtime": child.processIdentifier,
                            "thermalState": ProcessInfo.processInfo.thermalState.rawValue,
                            "lowPowerMode": ProcessInfo.processInfo.isLowPowerModeEnabled]
try JSONSerialization.data(withJSONObject: state, options: .sortedKeys)
    .write(to: URL(fileURLWithPath: arguments[0]))
signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
termination.setEventHandler { if child.isRunning { child.terminate() } }
termination.resume()
let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
interrupt.setEventHandler { if child.isRunning { child.terminate() } }
interrupt.resume()
child.waitUntilExit()
var usage = rusage()
getrusage(RUSAGE_CHILDREN, &usage)
let exitMetrics: [String: Any] = ["runtime_peak_rss_bytes": usage.ru_maxrss,
                                 "exit_status": child.terminationStatus,
                                 "thermal_state_end": ProcessInfo.processInfo.thermalState.rawValue]
try JSONSerialization.data(withJSONObject: exitMetrics, options: .sortedKeys)
    .write(to: URL(fileURLWithPath: arguments[0] + ".exit.json"))
try log.close()
exit(child.terminationStatus)
