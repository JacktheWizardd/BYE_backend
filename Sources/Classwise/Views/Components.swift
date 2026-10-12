import SwiftUI
import ClasswiseCore

enum Palette {
    static let background = Color(red: 250/255, green: 250/255, blue: 249/255)
    static let surface = Color(red: 243/255, green: 243/255, blue: 241/255)
    static let line = Color.black.opacity(0.09)
    static let secondary = Color(red: 0.39, green: 0.39, blue: 0.37)
    static let accent = Color(red: 0.77, green: 0.36, blue: 0.20)
}

struct PillStyle: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 19).padding(.vertical, 11)
            .background(primary ? Color.black : Palette.surface, in: Capsule())
            .foregroundStyle(primary ? .white : .black)
            .opacity(configuration.isPressed ? 0.65 : 1)
            .contentShape(Capsule())
    }
}

struct Eyebrow: View {
    let title: String
    var body: some View { Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.8).foregroundStyle(Palette.secondary) }
}

func score(_ value: Double?) -> String { value.map { String(format: "%.1f", $0) } ?? "—" }

struct Brand: View {
    var body: some View {
        HStack(spacing: 9) {
            Circle().fill(Palette.accent).frame(width: 8, height: 8)
            Text("BYE").font(.system(size: 18, weight: .semibold))
            Text("— before you enroll").font(.system(size: 12)).foregroundStyle(Palette.secondary)
        }.accessibilityElement(children: .combine)
    }
}

struct ScoreCard: View {
    let value: Double?
    let title: String
    let helper: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(score(value)).font(.system(size: 57, weight: .medium)).tracking(-2)
                if value != nil { Text("/ 5").font(.system(size: 18)).foregroundStyle(Palette.secondary) }
            }
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(value == nil ? "Not available" : helper).font(.system(size: 11)).foregroundStyle(Palette.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(23)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title): \(value.map { String(format: "%.1f out of 5", $0) } ?? "not available"). \(helper)")
    }
}

struct ReviewCard: View {
    let review: Review
    let sourceURL: URL
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text(review.course.isEmpty ? "Course not specified" : review.course).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("Rating \(score(review.rating))/5 · Difficulty \(score(review.difficulty))/5").font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }
            Text(review.excerpt).font(.system(size: 14)).lineSpacing(5).textSelection(.enabled)
            HStack {
                Text(review.postedLabel).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                Spacer()
                Link("Original on RMP ↗", destination: sourceURL).font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }
        }.padding(21).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.line))
    }
}
