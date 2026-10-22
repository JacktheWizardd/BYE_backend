#if BYE_AUDIT
import AppKit
import ClasswiseCore
import BYEAPI

@MainActor
enum AppAudit {
    static var log: AuditLog?
    private static var pcc: PCCClient!
    private static var directory: URL!
    private static var started = false
    private static var offlineOnly = false
    static func makeModel(directory: URL) -> AppModel {
        do {
            self.directory = directory
            offlineOnly = CommandLine.arguments.contains("--audit-offline")
            let log = try AuditLog(directory: directory); self.log = log; AuditTrace.log = log
            AuditHTTP.shared = try AuditHTTP(log: log, offline: offlineOnly)
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [AuditURLProtocol.self]; config.urlCache = nil; config.httpCookieStorage = nil
            pcc = PCCClient(session: URLSession(configuration: config))
            let client = RMPClient(transport: RMPTransport(protocolClasses: [AuditURLProtocol.self], spacing: 0, maximumAttempts: 1))
            let storage = directory.appendingPathComponent("Reports")
            let model = AppModel(pcc: pcc, cache: ReportCache(directory: storage), choices: ProfileChoiceStore(directory: storage),
                                 summariesEnabled: true, makeReader: { RMPAPIReader(client: client) }, byeReviews: nil, byeNumbers: nil)
            model.auditPreviewLimit = 2; model.auditSummariesEnabled = false
            log.event("app_initialized", ["pid":getpid(),"mode":offlineOnly ? "offline" : "live", "optimized":true,
                                          "request_limit":AuditSettings.maximum,"spacing_s":2,"live_deadline_s":AuditSettings.duration,"summaries_during_collection":false])
            return model
        } catch { fatalError("Audit initialization failed; refusing normal network fallback: \(error)") }
    }
    static func summaryObserved(_ summary: ReviewSummary?, profile: String?) {
        guard let summary, let log else { return }
        log.event("summary_view_state_observed",["profile":profile ?? "", "generated_at":summary.generatedAt.timeIntervalSince1970,
                  "positives":summary.positives.count,"concerns":summary.concerns.count,"note":"SwiftUI state observation, not compositor timing."])
        Task { await pause(0.02); screenshot("summary-view-"+String(Int(summary.generatedAt.timeIntervalSince1970*1000))) }
    }
    static func windowAppeared(model: AppModel) {
        guard let log, !started else { return }; started = true
        log.event("window_appeared", ["elapsed_from_initialization_s":ProcessInfo.processInfo.systemUptime-log.origin])
        Task { await run(model: model) }
    }
    private static func screenshot(_ name: String) {
        guard let log, let view = NSApplication.shared.windows.first(where: { $0.isVisible })?.contentView,
              let image = view.bitmapImageRepForCachingDisplay(in:view.bounds) else { return }
        view.cacheDisplay(in:view.bounds,to:image)
        do {
            guard let data = image.representation(using:.png,properties:[:]) else { return }
            try data.write(to:directory.appendingPathComponent(name+".png"))
            log.event("view_snapshot",["name":name,"method":"App-owned NSView bitmap; not a compositor screenshot."])
        } catch { log.event("view_snapshot_failure",["error":String(describing:error)]) }
    }
    private static func pause(_ seconds: Double = 0.05) async { try? await Task.sleep(for: .seconds(seconds)) }
    private static func wait(_ predicate: () -> Bool, seconds: Double = 45) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        while !predicate(), ProcessInfo.processInfo.systemUptime < deadline { await pause() }
        return predicate()
    }
    private static func run(model: AppModel) async {
        guard let log, let http = AuditHTTP.shared else { return }
        let heartbeat = Task { @MainActor in
            while !Task.isCancelled {
                let due = ProcessInfo.processInfo.systemUptime + 0.25
                do { try await Task.sleep(for: .milliseconds(250)) } catch { break }
                log.event("main_thread_probe", ["delay_s":max(0,ProcessInfo.processInfo.systemUptime-due),
                                               "thermal_state":ProcessInfo.processInfo.thermalState.rawValue])
            }
        }
        defer { heartbeat.cancel() }
        let deadline = Task {
            do { try await Task.sleep(for: .seconds(AuditSettings.duration)) } catch { return }
            await http.setOffline(); model.cancel(); log.event("collection_deadline")
        }
        do {
            log.event("idle_baseline_start"); screenshot("initial-window"); await pause(10); log.event("idle_baseline_end")
            let termsStart = ProcessInfo.processInfo.systemUptime
            await model.loadTerms()
            guard await wait({ !model.loadingTerms }), !model.terms.isEmpty else { throw AppError.message("Semester loading failed") }
            // Choose the current Fall term if published; otherwise retain the app's default.
            if let current = model.terms.first(where: { $0.termName == "Fall 2026" }) { model.termID = current.id }
            guard let term = model.selectedTerm else { throw AppError.message("No published semester") }
            log.event("terms_ready", ["seconds":ProcessInfo.processInfo.systemUptime-termsStart,"term":term.termName,
                                       "note":"ContentView may have started loading before this observer; request timings are authoritative."])
            let rows = try await pcc.schedule(term: term)
            let catalog = CourseSuggestions.catalog(rows: rows)
            let preference = ["PSYC","HIST","BIOL","SOC","POLS","ART","BUS"]
            var courses: [Course] = []
            if offlineOnly, let data = try? Data(contentsOf: directory.appendingPathComponent("collection-plan.json")),
               let value = try JSONSerialization.jsonObject(with: data) as? [String: Any], let labels = value["courses"] as? [String] {
                courses = labels.compactMap { try? Course($0) }
                let source = directory.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("rmp-benchmark-2026-10-11/snapshot.json")
                let snapshot = try JSONSerialization.jsonObject(with:Data(contentsOf:source)) as! [String:Any]
                let cases = snapshot["cases"] as! [[String:Any]]
                let cache = ReportCache(directory:directory.appendingPathComponent("Reports"))
                var seeded:[Course] = []
                for item in cases where ["cs2","math55","chem22"].contains(item["name"] as? String ?? "") {
                    let query = try Course(item["course"] as! String)
                    let course = try CourseSuggestions.resolve(query,rows:rows)
                    let raw = try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:item["source_file"] as! String))) as! [String:Any]
                    let profile = try JSONDecoder().decode(RMPProfile.self,from:JSONSerialization.data(withJSONObject:raw["profile"]!))
                    if let professor = ScheduleParser.professors(rows:rows,course:course).first(where:{ IdentityMatcher.matches(name:$0.name,profile:profile) }) {
                        cache.save(CachedReport(profile:profile,summary:nil,checkedAt:Date(),reviewsComplete:true),name:professor.name,course:course,subject:professor.subjectCode)
                        seeded.append(course)
                        log.event("development_cache_seeded",["profile":profile.id,"course":course.display,"source":item["source_file"]!,"reviews":profile.reviews.count])
                    }
                }
                if !seeded.isEmpty { courses = seeded; model.auditPreviewLimit = 0 }
                try log.save("offline-development-plan.json",["courses":courses.map(\.display),"note":"Previously used evidence only; fresh held-out data is not opened."])
            } else {
                for subject in preference {
                    let options = catalog.filter { $0.course.subject == subject && ScheduleParser.professors(rows: rows, course: $0.course).count >= 2 }
                    if let first = options.first { courses.append(first.course) }
                    if courses.count == 3 { break }
                }
                try log.save("collection-plan.json", ["term":term.termName,"courses":courses.map(\.display),"selection":"First published course with >=2 instructors per preferred new subject; no selection by model output."])
            }
            for course in courses {
                let start = ProcessInfo.processInfo.systemUptime
                model.changeSearch(); model.input = course.display
                log.event("search_start", ["course":course.display]); model.start()
                var firstRating: Double?
                _ = await wait({
                    if firstRating == nil, model.professors.contains(where: { $0.profile != nil }) { firstRating = ProcessInfo.processInfo.systemUptime-start }
                    return !model.busy
                }, seconds: 75)
                log.event("ratings_ready", ["course":course.display,"seconds":ProcessInfo.processInfo.systemUptime-start,
                                             "first_rating_s":firstRating as Any? ?? NSNull(),"busy_timeout":model.busy,
                                             "verified":model.professors.filter { $0.profile != nil }.count])
                let selected = offlineOnly ? Array(model.professors.filter { $0.profile != nil }.prefix(2)) : Array(model.professors.prefix(2)).filter { $0.profile != nil }
                for professor in selected {
                    let opened = ProcessInfo.processInfo.systemUptime
                    model.selectedID = professor.id; model.requestSelectedReport()
                    await pause() // Let the scheduled detail task publish its active state before observing completion.
                    _ = await wait({ model.loadingDetailsID == nil && !model.loadingDetails }, seconds: 60)
                    guard let result = model.professors.first(where: { $0.id == professor.id }), let profile = result.profile else { continue }
                    log.event("report_expanded", ["course":course.display,"profile":profile.id,"name":profile.name,
                        "seconds":ProcessInfo.processInfo.systemUptime-opened,"reviews":profile.reviews.count,
                        "exact_course_reviews":profile.reviews.filter { course.matchesReview($0.course) }.count,
                        "complete":result.reviewsComplete,"issue":result.reviewIssue ?? ""])
                    let frozen: [String: Any] = ["course":course.display,"profile":try JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)),
                        "reviews_complete":result.reviewsComplete,"captured_utc":ISO8601DateFormatter().string(from:Date())]
                    try log.save("profile-\(profile.id)-\(course.key).json", frozen)
                    await pause(0.3)
                }
                screenshot("results-"+course.key)
                if (await http.state())["stop_reason"] != "none" { break }
            }
            deadline.cancel(); model.cancel(); await http.setOffline()
            try log.save("network-final.json", await http.state())
            log.event("collection_complete")
            // Repeat in-process warm cache workflows. Cold-process replay is a separate invocation.
            for round in 1...3 {
                for course in courses {
                    let start = ProcessInfo.processInfo.systemUptime
                    model.changeSearch(); model.input = course.display; model.start()
                    let finished = await wait({ !model.busy }, seconds: 10)
                    log.event("cached_search", ["round":round,"course":course.display,"seconds":ProcessInfo.processInfo.systemUptime-start,"finished":finished])
                    let sortedStart = ProcessInfo.processInfo.systemUptime
                    model.sort = .difficulty; _ = model.filtered; model.onlineOnly = true; _ = model.filtered
                    model.onlineOnly = false; model.sort = .rating
                    log.event("local_filter_sort", ["round":round,"seconds":ProcessInfo.processInfo.systemUptime-sortedStart,
                                                    "note":"Model computation timing; visual interactions verified separately."])
                    let cancelStart = ProcessInfo.processInfo.systemUptime; model.cancelDetails()
                    log.event("cancel_completion", ["round":round,"seconds":ProcessInfo.processInfo.systemUptime-cancelStart,
                                                   "note":"No active request in this warm-cache check; in-flight cancellation tested by mocks."])
                    await pause(0.1)
                }
            }
            if CommandLine.arguments.contains("--audit-apple") { await apple(model: model) }
            screenshot("final-window")
            log.event("recovery_idle_start"); await pause(10); log.event("recovery_idle_end")
            try log.save("complete.json", ["finished_utc":ISO8601DateFormatter().string(from:Date()),"offline_only":offlineOnly,"network":await http.state()])
        } catch {
            deadline.cancel(); model.cancel(); await http.setOffline()
            log.event("audit_failure", ["error":String(describing:error)])
            try? log.save("complete.json", ["error":String(describing:error),"network":await http.state()])
        }
        log.event("audit_finished")
    }
    private static func apple(model: AppModel) async {
        guard let log else { return }
        let source = directory.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("rmp-benchmark-2026-10-11/snapshot.json")
        do {
            let value = try JSONSerialization.jsonObject(with: Data(contentsOf: source)) as! [String: Any]
            let cases = value["cases"] as! [[String: Any]]
            for item in cases.prefix(3) {
                let course = try Course(item["course"] as! String)
                let reviews = (item["reviews"] as! [[String: Any]]).prefix(6).map { row in
                    Review(id:row["id"] as! String,course:row["course"] as! String,text:row["text"] as! String,
                           date:row["date"] as? String ?? "",rating:nil,difficulty:nil,online:nil)
                }
                for round in 1...3 {
                    let provider = AppleSummaries.make(), start = ProcessInfo.processInfo.systemUptime
                    log.event("apple_start", ["case":item["name"]!,"round":round,"provider":provider.cacheIdentity])
                    do {
                        let output = try await provider.summarize(reviews:Array(reviews),course:course)
                        let duration = ProcessInfo.processInfo.systemUptime-start
                        let data = try JSONEncoder().encode(output)
                        try data.write(to:directory.appendingPathComponent("apple-\(item["name"]!)-\(round).json"))
                        // Display the old evidence in the real report view; keep the held-out collection untouched.
                        if let term = model.selectedTerm, let sourcePath = item["source_file"] as? String {
                            let source = try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:sourcePath))) as! [String:Any]
                            var profile = try JSONDecoder().decode(RMPProfile.self,from:JSONSerialization.data(withJSONObject:source["profile"]!))
                            profile.reviews = Array(reviews)
                            let rows = try await pcc.schedule(term:term)
                            if var professor = ScheduleParser.professors(rows:rows,course:course).first(where:{ IdentityMatcher.matches(name:$0.name,profile:profile) }) {
                                professor.profile = profile; professor.summary = output; professor.state = .ready; professor.reviewsComplete = true
                                model.course = course; model.professors = [professor]; model.selectedID = professor.id
                                log.event("apple_display_assigned",["profile":profile.id,"course":course.display])
                            } else { log.event("apple_display_unavailable",["course":course.display,"reason":"No matching scheduled instructor; summary saved without fabricated sections."]) }
                        }
                        await pause(0.05)
                        log.event("apple_complete", ["case":item["name"]!,"round":round,"generation_s":duration,
                            "next_main_turn_s":ProcessInfo.processInfo.systemUptime-start,"note":"Next main turn is not pixel presentation latency."])
                    } catch { log.event("apple_failure", ["case":item["name"]!,"round":round,"seconds":ProcessInfo.processInfo.systemUptime-start,"error":String(describing:error)]) }
                }
            }
        } catch { log.event("apple_setup_failure", ["error":String(describing:error)]) }
    }
}
#endif
