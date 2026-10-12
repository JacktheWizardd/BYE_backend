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
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        Text(professor.name).font(.system(size: 14, weight: .semibold)).multilineTextAlignment(.leading)
                        Spacer(minLength: 3)
                        if selected { Circle().fill(Palette.accent).frame(width: 6, height: 6).padding(.top, 5) }
                    }
                    if let profile = professor.profile {
                        HStack(spacing: 14) {
                            Text("\(score(profile.rating))/5 rating")
                            Text("\(score(profile.difficulty))/5 difficulty")
                        }.font(.system(size: 10)).foregroundStyle(Palette.secondary)
                        Text(profile.ratingCount.map { "\($0) ratings · \(professor.sections.count) \(professor.sections.count == 1 ? "section" : "sections")" } ?? "Rating count unavailable")
                            .font(.system(size: 10)).foregroundStyle(Palette.secondary)
                    } else {
                        Text(professor.state == .selectionRequired ? "Choose profile" : professor.state == .unavailable ? "Cannot retrieve RMP info" : professor.state == .searching ? "Checking RMP…" : "Not checked yet")
                            .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("\(professor.name). Rating \(score(professor.profile?.rating)) out of five. Difficulty \(score(professor.profile?.difficulty)) out of five. \(professor.profile?.ratingCount.map { "\($0) ratings." } ?? "Ratings not available.") \(selected ? "Selected." : "View report.")")
            if professor.state == .selectionRequired {
                Button("Choose profile") { model.openChooser(id: professor.id) }.buttonStyle(.link)
            }
            if professor.state == .unavailable || professor.state == .pending {
                Button("Try again") { model.retryProfessor(id: professor.id) }
                    .buttonStyle(.link).disabled(model.isPreviewing(professor.id))
            }
            if professor.state == .unavailable { Link("Check on RMP ↗", destination: professor.searchURL).font(.system(size: 11)).foregroundStyle(Palette.secondary) }
        }
        .padding(15)
        .foregroundStyle(professor.state == .unavailable ? Palette.secondary : .black)
        .background(selected ? Color.white : Palette.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Palette.accent.opacity(0.6) : .clear, lineWidth: 1))
    }
}
