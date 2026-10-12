import Foundation
import AppKit
import Darwin

// This executable links the unchanged ClasswiseCore validator. It never fetches evidence.
func writeJSON(_ value: Any, _ path: String) throws {
    try JSONSerialization.data(withJSONObject:value, options:[.sortedKeys,.prettyPrinted])
        .write(to:URL(fileURLWithPath:path), options:.atomic)
}
let args = Array(CommandLine.arguments.dropFirst())
if args.first == "--validate", args.count == 3 {
    do {
        let raw = try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:args[1]))) as! [String:Any]
        let reviews = (raw["reviews"] as! [[String:Any]]).map {
            Review(id:$0["id"] as! String,course:$0["course"] as! String,text:$0["text"] as! String,
                   date:$0["date"] as? String ?? "",rating:nil,difficulty:nil,online:$0["online"] as? Bool)
        }
        // A bare "English" in the historical fixture is intentionally not a valid Course.
        let course = try Course(raw["course"] as! String)
        let start = ProcessInfo.processInfo.systemUptime
        let summary = try SummaryBuilder.validate(Data((raw["text"] as! String).utf8), reviews:reviews, course:course)
        let object = try JSONSerialization.jsonObject(with:JSONEncoder().encode(summary))
        try writeJSON(["displayed":object,"validation_s":ProcessInfo.processInfo.systemUptime-start],args[2])
        exit(0)
    } catch {
        try? writeJSON(["error":String(describing:error)],args[2]); exit(1)
    }
}
guard args.count >= 4, args.first == "--host" else { exit(64) }
let pidFile=args[1], logFile=args[2]
let child=Process()
child.executableURL=Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/runtime/llama-server")
child.arguments=Array(args.dropFirst(3))
child.environment=ProcessInfo.processInfo.environment.filter {
    !$0.key.hasPrefix("LLAMA_") && !$0.key.hasPrefix("DYLD_") && !$0.key.lowercased().hasSuffix("proxy")
}
FileManager.default.createFile(atPath:logFile,contents:nil)
let log=try FileHandle(forWritingTo:URL(fileURLWithPath:logFile))
child.standardOutput=log;child.standardError=log
try child.run()
try writeJSON(["host":getpid(),"runtime":child.processIdentifier,
               "thermal":ProcessInfo.processInfo.thermalState.rawValue,
               "low_power":ProcessInfo.processInfo.isLowPowerModeEnabled],pidFile)
signal(SIGTERM,SIG_IGN);signal(SIGINT,SIG_IGN)
let stop=DispatchSource.makeSignalSource(signal:SIGTERM,queue:.global())
stop.setEventHandler { if child.isRunning { child.terminate() } };stop.resume()
child.waitUntilExit()
var usage=rusage();getrusage(RUSAGE_CHILDREN,&usage)
try writeJSON(["runtime_peak_rss_bytes":usage.ru_maxrss,"exit_status":child.terminationStatus,
               "thermal_end":ProcessInfo.processInfo.thermalState.rawValue],pidFile+".exit.json")
try log.close();exit(child.terminationStatus)
