import SwiftUI
import ClasswiseCore

struct ProfileChooser: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Choose RMP profile").font(.title2.weight(.semibold))
            if let professor = model.chooserProfessor {
                Text(professor.name).font(.headline)
                Text([professor.subjectCode, professor.subjectDescription].filter { !$0.isEmpty }.joined(separator: " · "))
                    .foregroundStyle(Palette.secondary)
                Text("Profiles stay separate. Choose the profile you want to use for this PCC instructor and subject.")
                    .font(.callout).foregroundStyle(Palette.secondary)
                if model.isPreviewing(professor.id) {
                    ProgressView("Finding profiles…").accessibilityLabel("Loading profile choices")
                }
                if let issue = model.chooserIssue {
                    Text(issue).foregroundStyle(Palette.secondary)
                    Button("Try again") { model.openChooser(id: professor.id) }.disabled(model.isPreviewing(professor.id))
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(professor.candidates) { candidate in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(candidate.name).font(.headline)
                                Text("Department: \(candidate.department.isEmpty ? "Unavailable" : candidate.department)")
                                Text(candidate.school).foregroundStyle(Palette.secondary)
                                HStack {
                                    Link("View on RMP ↗", destination: candidate.url)
                                    Spacer()
                                    Button("Use this profile") { model.chooseProfile(id: professor.id, profileID: candidate.id) }
                                        .disabled(model.isPreviewing(professor.id))
                                        .accessibilityLabel("Use \(candidate.name), \(candidate.department.isEmpty ? "department unavailable" : candidate.department), profile \(candidate.id)")
                                }
                            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                if professor.candidates.isEmpty && !model.isPreviewing(professor.id) {
                    Text("No eligible profile is available. Retry this professor or check the source.")
                    Link("Check on RMP ↗", destination: professor.searchURL)
                }
            }
            HStack { Spacer(); Button("Close") { model.chooserID = nil }.keyboardShortcut(.cancelAction) }
        }.padding(26).frame(width: 560, height: 560).background(Palette.background)
    }
}
