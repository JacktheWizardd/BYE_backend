import SwiftUI
import ClasswiseCore

struct ProfessorListCard: View {
    @ObservedObject var model: AppModel
    let professor: Professor
    let selected: Bool
    let select: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button(action: select) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(professor.name).font(.system(size: 14, weight: .semibold)).multilineTextAlignment(.leading)
                                .foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                            if let profile = professor.profile {
                                Text("Difficulty \(score(profile.difficulty)) · \(profile.wouldTakeAgain.map { "\(Int($0.rounded()))% would take again" } ?? "take-again rate unavailable")")
                                Text(profile.ratingCount.map { "\($0) ratings · \(sectionCount)" } ?? "Rating count unavailable · \(sectionCount)")
                            } else {
                                Text(professor.state == .selectionRequired ? "Two or more RMP profiles · Choose profile" : professor.state == .unavailable ? "Cannot retrieve RMP info" : professor.state == .searching ? "Checking RMP…" : "Not checked yet")
                                Text(sectionCount)
                            }
                        }.font(.system(size: 11)).foregroundStyle(Palette.secondary)
                        Spacer(minLength: 0)
                        Text(score(professor.profile?.rating)).font(BYEFont.display(26)).foregroundStyle(professor.profile == nil ? Palette.secondary : Palette.ink)
                    }
                    if professor.profile != nil { RatingBar(value: professor.profile?.rating) }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("\(professor.name). Rating \(score(professor.profile?.rating)) out of five. Difficulty \(score(professor.profile?.difficulty)) out of five. \(professor.profile?.ratingCount.map { "\($0) ratings." } ?? "Ratings not available.") \(selected ? "Selected." : "View report.")")
            if professor.state == .selectionRequired {
                Button("Choose profile") { model.openChooser(id: professor.id) }.buttonStyle(TextLinkStyle())
            }
            if professor.state == .unavailable || professor.state == .pending {
                Button("Try again") { model.retryProfessor(id: professor.id) }
                    .buttonStyle(TextLinkStyle()).disabled(model.isPreviewing(professor.id))
            }
            if professor.state == .unavailable { Link("Check on RMP ↗", destination: professor.searchURL).font(.system(size: 11)).foregroundStyle(Palette.secondary) }
        }
        .padding(15)
        .foregroundStyle(Palette.ink)
        .background(selected ? Palette.card : Palette.tile, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Palette.ink : Palette.tileLine, lineWidth: 1.5))
        .shadow(color: selected ? Palette.ink.opacity(0.12) : .clear, radius: 10, y: 6)
    }
    private var sectionCount: String { "\(professor.sections.count) \(professor.sections.count == 1 ? "section" : "sections")" }
}
