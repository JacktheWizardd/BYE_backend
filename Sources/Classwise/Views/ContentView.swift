import SwiftUI
import ClasswiseCore

struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: AppUpdater
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confetti = 0
    var body: some View {
        Group {
            switch model.route {
            case .welcome:
                firstRun { WelcomeView { withAnimation(BYEMotion.fade(reduce: reduceMotion)) { model.continueFromWelcome() } } }
            case .name:
                firstRun {
                    NameStepView(initialName: model.displayName, term: model.selectedTerm?.termName) { name in
                        if !model.numbersAvailable { confetti += 1 }
                        withAnimation(BYEMotion.fade(reduce: reduceMotion)) { model.continueFromName(name) }
                    }
                }
            case .number:
                firstRun {
                    NumberStepView(model: model, term: model.selectedTerm?.termName) { celebrate in
                        if celebrate { confetti += 1 }
                        withAnimation(BYEMotion.fade(reduce: reduceMotion)) { model.finishOnboarding(name: model.displayName) }
                    }
                    // A new number gets its confetti the moment it arrives.
                    .onChange(of: model.byeNumber?.number) { old, new in if old == nil, new != nil { confetti += 1 } }
                }
            case .home, .results:
                // A plain frame rather than NavigationSplitView: newer macOS draws that sidebar as floating
                // glass over the content, and v3 wants a flat linen sidebar beside an inset ivory panel.
                HStack(spacing: 0) {
                    Sidebar(model: model).frame(width: 210)
                    panel
                }
                .background(Palette.paper2)
                .ignoresSafeArea()
                .overlay {
                    if model.commandMenuOpen { CommandMenu(model: model) }
                    if model.settingsTab != nil { SettingsSheet(model: model, updater: updater) }
                }
                .transition(.opacity)
            }
        }
        .overlay { ConfettiBurst(trigger: confetti).ignoresSafeArea() }
        .foregroundStyle(Palette.ink)
        .tint(Palette.ink)
        .task {
            #if !BYE_MODEL_EVAL
            model.refreshNumberTotal()
            await model.loadTerms()
            #endif
        }
        .sheet(isPresented: Binding(get: { model.chooserID != nil }, set: { if !$0 { model.chooserID = nil } })) {
            ProfileChooser(model: model)
        }
        .onChange(of: model.displayed.map(\.id)) { _, _ in model.reconcileSelection() }
        .onChange(of: model.selectedID) { _, _ in model.requestSelectedReport() }
        #if BYE_AUDIT
        .onChange(of: model.selected?.summary) { _, summary in AppAudit.summaryObserved(summary, profile:model.selected?.profile?.id) }
        #endif
        #if BYE_MODEL_EVAL
        .onChange(of: model.selected?.summary) { _, summary in ModelEvaluation.summaryObserved(summary,profile:model.selected?.profile?.id,showingResults:model.showingResults) }
        .onChange(of: model.showingResults) { _, showing in ModelEvaluation.summaryObserved(model.selected?.summary,profile:model.selected?.profile?.id,showingResults:showing) }
        #endif
    }
    /// The first-run screens fill the window on ivory, without the sidebar.
    private func firstRun(@ViewBuilder _ content: () -> some View) -> some View {
        ZStack { Palette.paper.ignoresSafeArea(); content().padding(40) }
            .transition(.opacity)
    }
    /// The ivory panel inset on the linen frame, beside the sidebar.
    private var panel: some View {
        let shape = RoundedRectangle(cornerRadius: BYERadius.md + 2)
        return ZStack {
            Palette.paper
            if model.showingResults { ResultsView(model: model) } else { HomeView(model: model) }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Palette.line))
        .padding([.top, .trailing, .bottom], BYESpace.sm)
    }
}
