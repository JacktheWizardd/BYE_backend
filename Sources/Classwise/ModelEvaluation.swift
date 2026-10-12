#if BYE_MODEL_EVAL
import Foundation
import AppKit
import ClasswiseCore

/// Exists only in the isolated measurement build; no live evidence transport.
actor EvaluationSummaryProvider: SummaryProvider {
    nonisolated let cacheIdentity: String
    private let endpoint: URL
    private let directory: URL
    private let instructions: String
    private let context: Int
    private let session: URLSession
    private var active = false
    init(config: [String:Any], directory: URL) throws {
        guard let port = config["port"] as? Int, (1...65535).contains(port),
              let identity = config["identity"] as? String,
              let instructions = config["instructions"] as? String,
              let context = config["context"] as? Int else { throw AppError.message("Invalid isolated evaluation configuration") }
        self.endpoint = URL(string:"http://127.0.0.1:\(port)")!
        self.directory=directory;self.instructions=instructions;self.context=context
        self.cacheIdentity=identity
        let configuration=URLSessionConfiguration.ephemeral
        configuration.urlCache=nil;configuration.httpCookieStorage=nil
        configuration.connectionProxyDictionary=[:]
        configuration.timeoutIntervalForRequest=180;configuration.timeoutIntervalForResource=180
        session=URLSession(configuration:configuration)
    }
    private func request(_ path: String,_ body: [String:Any]) async throws -> [String:Any] {
        try Task.checkCancellation()
        var request=URLRequest(url:endpoint.appendingPathComponent(path))
        request.httpMethod="POST";request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.httpBody=try JSONSerialization.data(withJSONObject:body)
        let (data,response)=try await session.data(for:request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AppError.message("Local runtime error") }
        return try JSONSerialization.jsonObject(with:data) as! [String:Any]
    }
    func summarize(reviews: [Review],course: Course) async throws -> ReviewSummary {
        while active { try Task.checkCancellation();try await Task.sleep(for:.milliseconds(20)) }
        active=true;defer { active=false }
        let start=ProcessInfo.processInfo.systemUptime
        let source=reviews.map { ["id":$0.id,"course":$0.course,"text":$0.text] }
        let text=String(data:try JSONSerialization.data(withJSONObject:source,options:.sortedKeys),encoding:.utf8)!
        let rendered=try await request("apply-template",["messages":[["role":"system","content":instructions],["role":"user","content":"Requested course: \(course.display)\nBEGIN REVIEWS\n\(text)\nEND REVIEWS"]],"add_generation_prompt":true,"chat_template_kwargs":["enable_thinking":false]])
        guard let prompt=rendered["prompt"] as? String else { throw AppError.message("Missing rendered prompt") }
        let tokenized=try await request("tokenize",["content":prompt,"add_special":false,"parse_special":true])
        guard let tokens=tokenized["tokens"] as? [Int],tokens.count+256<=context else { throw AppError.message("Evidence exceeds context; no truncation") }
        let ids=Array(Set(reviews.map(\.id))).sorted()
        let point:[String:Any] = ["type":"object","properties":["text":["type":"string","maxLength":96],"reviewIDs":["type":"array","items":["type":"string","enum":ids],"minItems":2,"maxItems":2]],"required":["text","reviewIDs"],"additionalProperties":false]
        let schema:[String:Any] = ["type":"object","properties":["overview":["type":"string","maxLength":180],"positives":["type":"array","items":point,"maxItems":2],"concerns":["type":"array","items":point,"maxItems":2]],"required":["overview","positives","concerns"],"additionalProperties":false]
        await ModelEvaluation.event("native_inference_started",["prompt_tokens":tokens.count,"evidence_ids":ids])
        let raw:[String:Any]
        do {
            raw=try await request("completion",["prompt":prompt,"n_predict":256,"temperature":0,"seed":42,"top_k":1,"top_p":1,"min_p":0,"repeat_penalty":1,"cache_prompt":false,"stream":false,"json_schema":schema])
            await ModelEvaluation.event("native_inference_finished",["evidence_ids":ids])
        } catch {
            await ModelEvaluation.event("native_inference_failed_or_cancelled",["evidence_ids":ids,"error":error.localizedDescription])
            throw error
        }
        let output=raw["content"] as? String ?? ""
        let name="native-"+UUID().uuidString
        // Persist verbatim generation before parsing or validation.
        try JSONSerialization.data(withJSONObject:["raw":raw,"prompt":prompt,"source":source,"started_uptime":start,"generation_finished_uptime":ProcessInfo.processInfo.systemUptime],options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent(name+"-raw.json"))
        try Task.checkCancellation()
        var result=try SummaryBuilder.validate(Data(output.utf8),reviews:reviews,course:course)
        result.providerIdentity=cacheIdentity;result.evidence=reviews
        try JSONEncoder().encode(result).write(to:directory.appendingPathComponent(name+"-displayed.json"))
        return result
    }
}

@MainActor enum ModelEvaluation {
    static var directory: URL!
    static var started=false
    static var origin=ProcessInfo.processInfo.systemUptime
    static var controllerLaunch: Double?
    static var bundledStackLaunch: Double?
    static var providerIdentity: String?
    static func event(_ kind: String,_ values:[String:Any]=[:]) {
        guard let directory else { return }
        var object=values;object["kind"]=kind;object["uptime_s"]=ProcessInfo.processInfo.systemUptime
        object["thermal"]=ProcessInfo.processInfo.thermalState.rawValue
        let path=directory.appendingPathComponent("native-events.jsonl")
        if !FileManager.default.fileExists(atPath:path.path) { FileManager.default.createFile(atPath:path.path,contents:nil) }
        if let handle=try? FileHandle(forWritingTo:path),let data=try? JSONSerialization.data(withJSONObject:object,options:.sortedKeys) {
            try? handle.seekToEnd();try? handle.write(contentsOf:data+Data([10]));try? handle.close()
        }
    }
    static func makeModel() -> AppModel {
        origin=ProcessInfo.processInfo.systemUptime
        guard let index=CommandLine.arguments.firstIndex(of:"--model-eval-session"),CommandLine.arguments.count>index+1 else {
            fputs("Measurement build requires isolated session; refusing startup.\n",stderr);exit(64)
        }
        do {
            directory=URL(fileURLWithPath:CommandLine.arguments[index+1],isDirectory:true)
            let config=try JSONSerialization.jsonObject(with:Data(contentsOf:directory.appendingPathComponent("native-config.json"))) as! [String:Any]
            controllerLaunch=config["controller_prelaunch_monotonic_s"] as? Double
            bundledStackLaunch=config["bundled_stack_start_monotonic_s"] as? Double
            let provider=try EvaluationSummaryProvider(config:config,directory:directory)
            providerIdentity=provider.cacheIdentity
            let storage=directory.appendingPathComponent("Reports")
            let model=AppModel(summaryProvider:provider,cache:ReportCache(directory:storage),choices:ProfileChoiceStore(directory:storage))
            let cases=config["cases"] as! [[String:Any]]
            guard cases.count>=2 else { throw AppError.message("Two offline UI fixtures required") }
            model.course=try Course(cases[0]["course"] as! String);model.input=model.course!.display
            // Repeat the two frozen fictional banks only to make the actual list
            // scrollable. These are UI placeholders, not new independent evidence.
            for index in 0..<16 {
                let item=cases[index % cases.count]
                let reviews=(item["reviews"] as! [[String:Any]]).map {
                    Review(id:$0["id"] as! String,course:$0["course"] as! String,text:$0["text"] as! String,date:"",rating:nil,difficulty:nil,online:nil)
                }
                let seed:[String:Any] = ["id":"evaluation-\(index)","name":"Fictional Fixture \(index+1)","sections":[],"subjectCode":"ETH","subjectDescription":"Offline fictional fixture","candidates":[],"generation":UUID().uuidString,"state":"ready","reviewsComplete":true]
                var professor=try JSONDecoder().decode(Professor.self,from:JSONSerialization.data(withJSONObject:seed))
                professor.profile=RMPProfile(id:professor.id,firstName:"Fictional",lastName:"Fixture \(index+1)",school:"Offline measurement",schoolID:nil,department:"Fixture",rating:Double(5-index % 5),difficulty:Double(index % 5+1),ratingCount:reviews.count,wouldTakeAgain:nil,reviews:reviews,courseCounts:nil,reviewCoverage:nil)
                professor.state = .ready;professor.reviewsComplete=true
                model.professors.append(professor)
            }
            model.showingResults=true;event("initialized",["pid":getpid(),"synthetic_ui_fixtures":true,"ui_rows":16,"independent_fixture_banks":cases.count,"repeated_rows_are_not_new_evidence":true,"provider":provider.cacheIdentity])
            return model
        } catch { fputs("Isolated evaluation initialization failed: \(error)\n",stderr);exit(65) }
    }
    static func windowAppeared(model: AppModel) {
        guard !started else { return };started=true
        NSApplication.shared.windows.first?.title="BYE model measurement — fictional offline fixtures"
        event("window_appeared",["initialization_to_observed_window_s":ProcessInfo.processInfo.systemUptime-origin,
            "controller_prelaunch_to_observed_window_s":controllerLaunch.map { ProcessInfo.processInfo.systemUptime-$0 } as Any? ?? NSNull(),
            "bundled_stack_start_to_observed_window_s":bundledStackLaunch.map { ProcessInfo.processInfo.systemUptime-$0 } as Any? ?? NSNull(),
            "note":"Native window observation, not compositor presentation."])
        Task { @MainActor in
            let heartbeat=Task { @MainActor in
                while !Task.isCancelled {
                    let due=ProcessInfo.processInfo.systemUptime+0.1
                    do { try await Task.sleep(for:.milliseconds(100)) } catch { break }
                    event("main_thread_probe",["delay_s":max(0,ProcessInfo.processInfo.systemUptime-due)])
                }
            }
            defer { heartbeat.cancel() }
            event("native_ui_idle_begin",["note":"Two-second deliberate idle baseline with bundled helper loaded; excluded from request latency."])
            try? await Task.sleep(for:.seconds(2))
            event("native_ui_idle_end")
            model.selectedID=model.professors[0].id;model.requestSelectedReport()
            model.showingResults=false
            for index in 0..<20 {
                try? await Task.sleep(for:.milliseconds(100))
                let start=ProcessInfo.processInfo.systemUptime
                if index<5 {
                    let editor=NSApplication.shared.windows.first?.firstResponder as? NSTextView
                    editor?.selectAll(nil);editor?.insertText("ETH \(index+10)",replacementRange:NSRange(location:NSNotFound,length:0))
                    let dispatch=ProcessInfo.processInfo.systemUptime-start
                    try? await Task.sleep(for:.milliseconds(25))
                    event("text_edit_observed",["field_editor_found":editor != nil,"bound_input":model.input,"expected_input":"ETH \(index+10)","edit_dispatch_s":dispatch,"deliberate_yield_s":0.025,"summary_loading":model.summaryLoadingID != nil,"seconds":ProcessInfo.processInfo.systemUptime-start,"note":"Programmatic editing through actual focused text field; elapsed includes a labeled observation yield, not hardware input latency."])
                } else {
                    model.showingResults=true
                    model.sort=ProfessorSort.allCases[index % ProfessorSort.allCases.count]
                    model.onlineOnly=true;let filtered=model.displayed.count
                    try? await Task.sleep(for:.milliseconds(25))
                    model.onlineOnly=false;model.showAll.toggle()
                    try? await Task.sleep(for:.milliseconds(25))
                    if let view=NSApplication.shared.windows.first?.contentView,let scroll=findScrollView(view) {
                        let before=scroll.contentView.bounds.origin.y
                        scroll.contentView.scroll(to:NSPoint(x:0,y:Double(index*20)));scroll.reflectScrolledClipView(scroll.contentView)
                        event("scroll_observed",["before_y":before,"after_y":scroll.contentView.bounds.origin.y,"document_height":scroll.documentView?.bounds.height ?? 0,"viewport_height":scroll.contentView.bounds.height])
                    }
                    event("programmatic_ui_actions",["seconds":ProcessInfo.processInfo.systemUptime-start,"deliberate_yield_s":0.05,"summary_loading":model.summaryLoadingID != nil,"filtered_count":filtered,"restored_count":model.displayed.count,"actions":["sort","filter","scroll"],"note":"Model/view actions with two labeled observation yields; not hardware input-to-pixel latency."])
                }
            }
            let start=ProcessInfo.processInfo.systemUptime;let initialActive=model.summaryLoadingID != nil;model.cancelDetails()
            event("cancel_state_completed",["seconds":ProcessInfo.processInfo.systemUptime-start,"summary_was_loading":initialActive,"provider_task_cancellation_requested":true])
            try? await Task.sleep(for:.milliseconds(500))
            model.retrySummary(id:model.professors[0].id)
            try? await Task.sleep(for:.milliseconds(50))
            let cancelStart=ProcessInfo.processInfo.systemUptime;let active=model.summaryLoadingID != nil
            model.cancelDetails()
            event("fresh_request_cancel_state_completed",["seconds":ProcessInfo.processInfo.systemUptime-cancelStart,"summary_was_loading":active,"note":"App task-state cancellation; runtime release measured separately."])
            // Let the server observe stream closure before replacing the active request.
            try? await Task.sleep(for:.seconds(1))
            model.retrySummary(id:model.professors[1].id);event("professor_switched")
            try? await Task.sleep(for:.milliseconds(25))
            let replacementActive=model.summaryLoadingID != nil
            model.retrySummary(id:model.professors[0].id)
            try? await Task.sleep(for:.milliseconds(25))
            model.retrySummary(id:model.professors[1].id)
            event("rapid_replacement_requested",["selected_profile":model.selectedID ?? "","first_request_was_loading":replacementActive,"cached_summaries_invalidated":true])
            try? await Task.sleep(for:.milliseconds(50))
            let deadline=ProcessInfo.processInfo.systemUptime+180
            while model.summaryLoadingID != nil,ProcessInfo.processInfo.systemUptime<deadline { try? await Task.sleep(for:.milliseconds(50)) }
            event("summary_state_observed",["present":model.selected?.summary != nil,"error":model.selected?.summaryIssue ?? ""])
            if let summary=model.selected?.summary {
                let start=ProcessInfo.processInfo.systemUptime
                model.selectedID=model.professors[0].id;model.selectedID=model.professors[1].id
                event("cached_view_reopened",["seconds":ProcessInfo.processInfo.systemUptime-start,"same_summary":model.selected?.summary == summary])
                if let selected=model.selected,let course=model.course,let profile=selected.profile {
                    for round in 1...3 {
                        let begin=ProcessInfo.processInfo.systemUptime
                        let cache=ReportCache(directory:directory.appendingPathComponent("Reports"))
                        let cached=cache.load(name:selected.name,course:course,subject:selected.subjectCode,preferredProfileID:profile.id,summaryProvider:providerIdentity)
                        event("disk_cache_reopened",["round":round,"seconds":ProcessInfo.processInfo.systemUptime-begin,"summary_matches":cached?.summary == summary,"profile_matches":cached?.profile.id == profile.id])
                    }
                    let other=ReportCache(directory:directory.appendingPathComponent("Reports")).load(name:selected.name,course:course,subject:selected.subjectCode,preferredProfileID:profile.id,summaryProvider:"deliberately-different-model-identity")
                    event("cache_identity_checked",["wrong_identity_hides_summary":other?.summary == nil,"same_raw_profile_available":other?.profile.id == profile.id])
                }
            }
            if let view=NSApplication.shared.windows.first?.contentView,let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds) {
                view.cacheDisplay(in:view.bounds,to:rep)
                if let data=rep.representation(using:.png,properties:[:]) { try? data.write(to:directory.appendingPathComponent("native-view.png")) }
            }
            event("complete",["note":"Real BYE SwiftUI views with fictional offline fixtures and a local bundled-runtime adapter."])
            try? Data("{}".utf8).write(to:directory.appendingPathComponent("native-complete.json"))
            // Keep the scheduling probe active through controller-owned idle unloading.
            while !Task.isCancelled { try? await Task.sleep(for:.seconds(1)) }
        }
    }
    private static func findScrollView(_ view:NSView) -> NSScrollView? {
        var candidates:[NSScrollView]=[]
        if let scroll=view as? NSScrollView { candidates.append(scroll) }
        for child in view.subviews { if let scroll=findScrollView(child) { candidates.append(scroll) } }
        return candidates.max { ($0.documentView?.bounds.height ?? 0)-$0.contentView.bounds.height < ($1.documentView?.bounds.height ?? 0)-$1.contentView.bounds.height }
    }
    static func summaryObserved(_ summary:ReviewSummary?,profile:String?,showingResults:Bool) {
        guard let summary else { return }
        event("summary_view_state_observed",["profile":profile ?? "","report_view_enabled":showingResults,"generated_at_reference_s":summary.generatedAt.timeIntervalSinceReferenceDate,
            "overview":summary.overview,"positives":summary.positives.count,"concerns":summary.concerns.count,
            "note":"SwiftUI state observation, not compositor timing."])
    }
}
#endif
