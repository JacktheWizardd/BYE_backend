import AppKit
import ClasswiseCore
import SwiftUI

/// Settings: your name, updates (Sparkle, in builds with an update feed) and about. Shown as a sheet in the main
/// window (profile row, ⌘K) and in the standard Settings window (⌘,).
struct SettingsContent: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: AppUpdater
    @Binding var tab: SettingsTab
    let showWelcome: () -> Void
    @State private var draft = ""
    @State private var note = ""
    @State private var noteIsProblem = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let label = info?["CFBundleShortVersionString"] as? String ?? "Development"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(label) (build \(build))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Segmented(label: "Settings sections", options: [(.general, "General"), (.updates, "Updates"), (.about, "About")], selection: $tab)
            Group {
                switch tab {
                case .general: general
                case .updates: updates
                case .about: about
                }
            }
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .fadeIn()
            .id(tab)
        }
        .onAppear { draft = model.displayName }
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your name").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.secondary)
            HStack(spacing: 8) {
                TextField("Your first name", text: $draft)
                    .textFieldStyle(.plain).font(.system(size: 14)).textContentType(.givenName)
                    .padding(.horizontal, 12).frame(height: 40)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.ink, lineWidth: BYEBorder.control))
                    .onSubmit(save)
                    .onChange(of: draft) { _, value in
                        note = ""
                        if value.count > AppPreferences.maxNameLength { draft = String(value.prefix(AppPreferences.maxNameLength)) }
                    }
                    .accessibilityLabel("Your name")
                Button("Save", action: save).buttonStyle(StickerButtonStyle(kind: .secondary))
            }
            Text(note.isEmpty ? "Stays on this computer." : note).font(.system(size: 12))
                .foregroundStyle(noteIsProblem ? Palette.signal : Palette.secondary)
            numberSection.padding(.top, 10)
            Button("Show welcome again", action: showWelcome).buttonStyle(TextLinkStyle()).padding(.top, 6)
        }
    }

    /// The student's BYE number, or the optional way to get one.
    @ViewBuilder private var numberSection: some View {
        Text("Your BYE number").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.secondary)
        if let number = model.byeNumber {
            (Text(ByeNumber.label(number.number)).font(BYEFont.mono(14)) + Text("  ·  Student \(number.number) of \(number.total)").font(.system(size: 12)).foregroundStyle(Palette.secondary))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("BYE number \(number.number), student \(number.number) of \(number.total)")
            Text("Linked to your school email, so it stays yours on any Mac.").font(.system(size: 12)).foregroundStyle(Palette.secondary)
        } else if model.numbersAvailable {
            Text("Optional and just for fun: verify your PCC school email to get your own number on your student card. BYE keeps your school email and number.")
                .font(.system(size: 12)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            ByeNumberForm(model: model)
        } else {
            Text("BYE numbers are not available in this build.").font(.system(size: 12)).foregroundStyle(Palette.secondary)
        }
    }

    private var updates: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("You have BYE ") + Text(version).font(BYEFont.mono(12)) + Text(".")
            if updater.isEnabled {
                Toggle("Check for updates automatically", isOn: $updater.automaticallyChecksForUpdates)
                Toggle("Download and install updates automatically", isOn: $updater.automaticallyDownloadsUpdates)
                    .disabled(!updater.automaticallyChecksForUpdates)
                Button("Check for updates") { updater.checkForUpdates() }
                    .buttonStyle(StickerButtonStyle()).disabled(!updater.canCheckForUpdates).padding(.top, 4)
                Text("BYE checks the BYE website about once a day. The website’s host, Cloudflare, sees your IP address and app version; no other information is sent.")
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            } else if NetworkShutdown.isActive {
                Text("This is BYE’s final version. It no longer checks for updates or connects to the internet.")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Updates are not available in this build.").font(.system(size: 12)).foregroundStyle(Palette.secondary)
            }
        }
        .font(.system(size: 13))
        .toggleStyle(.checkbox)
    }

    /// The owner's own words, shared with the Windows app.
    private var about: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hi! :)").font(BYEFont.display(19, bold: true)).foregroundStyle(Palette.ink)
            Text("I’m a PCC student, just like you. I made BYE because I got tired of juggling a bunch of tabs just to find the right professor and plan my classes.")
            Text("So I thought, why not put everything in one place?")
            Text("BYE is just a little project I started to make picking classes easier for myself and hopefully for you too!")
            Text("It’s free, with no ads or tracking. Just something I built for students, by a student.")
            HStack(spacing: 4) {
                Text("Ratings from Rate My Professors, schedules from PCC.")
                if let notices = bundledResource("THIRD_PARTY_NOTICES", "txt") {
                    Button("Licenses and credits ↗") { NSWorkspace.shared.open(notices) }.buttonStyle(TextLinkStyle())
                }
            }
            .font(.system(size: 11)).foregroundStyle(Palette.secondary).padding(.top, 4)
        }
        .font(.system(size: 13)).foregroundStyle(Palette.body)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func save() {
        let value = AppPreferences.normalizedName(draft)
        if value.isEmpty { show("Type a name first.", problem: true) }
        else if !AppPreferences.isValidName(value) { show("Use letters, spaces, hyphens or apostrophes.", problem: true) }
        else if model.setDisplayName(value) { draft = value; show("Saved.", problem: false) }
        else { show("That name couldn’t be saved.", problem: true) }
    }
    private func show(_ message: String, problem: Bool) {
        note = message; noteIsProblem = problem
        AccessibilityNotification.Announcement(message).post()
    }
}

/// The Settings sheet over the main window. Esc, the close button or a click outside closes it.
struct SettingsSheet: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: AppUpdater
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    private var tab: Binding<SettingsTab> {
        Binding(get: { model.settingsTab ?? .general }, set: { model.settingsTab = $0 })
    }
    var body: some View {
        ZStack(alignment: .top) {
            Palette.ink.opacity(0.18).ignoresSafeArea()
                .onTapGesture { close() }
                .accessibilityHidden(true)
            panel
                .padding(.top, 80)
                .scaleEffect(shown || reduceMotion ? 1 : 0.94, anchor: .top)
                .opacity(shown || reduceMotion ? 1 : 0)
        }
        .onAppear { withAnimation(BYEMotion.spring(reduce: reduceMotion)) { shown = true } }
        .onExitCommand { close() }
    }
    private var panel: some View {
        let shape = RoundedRectangle(cornerRadius: 18)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Settings").font(BYEFont.display(19, bold: true)).accessibilityAddTraits(.isHeader)
                Spacer()
                Button { close() } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).frame(width: 32, height: 32).contentShape(Rectangle())
                }
                .buttonStyle(.plain).keyboardShortcut(.cancelAction).accessibilityLabel("Close settings")
            }
            SettingsContent(model: model, updater: updater, tab: tab) { model.showWelcomeAgain() }
        }
        .padding(18)
        .frame(width: 460)
        .background(Palette.card, in: shape)
        .overlay(shape.strokeBorder(Palette.ink, lineWidth: BYEBorder.sticker))
        .background(shape.fill(Palette.ink).offset(x: 4, y: 4))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings")
        .accessibilityAddTraits(.isModal)
    }
    private func close() { model.settingsTab = nil }
}

/// The standard Settings window (⌘,), with the same content as the sheet.
struct SettingsWindow: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: AppUpdater
    let reopenMainWindow: () -> Void
    @State private var tab: SettingsTab = .general
    var body: some View {
        SettingsContent(model: model, updater: updater, tab: $tab) {
            model.showWelcomeAgain(); reopenMainWindow()
        }
        .padding(22)
        .frame(width: 460, alignment: .topLeading)
        .background(Palette.paper)
        .foregroundStyle(Palette.ink)
        .tint(Palette.ink)
    }
}
