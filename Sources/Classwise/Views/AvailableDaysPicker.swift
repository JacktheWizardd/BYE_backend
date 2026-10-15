import SwiftUI
import ClasswiseCore

struct AvailableDaysPicker: View {
    @Binding var selection: Set<Weekday>
    private func label(_ day: Weekday) -> String {
        switch day {
        case .monday: "M"
        case .tuesday: "T"
        case .wednesday: "W"
        case .thursday: "Th"
        case .friday: "F"
        case .saturday: "Sa"
        case .sunday: "Su"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Class days").font(.system(size: 12, weight: .semibold))
                Spacer()
                if !selection.isEmpty {
                    Button("Clear") { selection.removeAll() }.buttonStyle(TextLinkStyle()).font(.system(size: 11))
                }
            }
            HStack(spacing: 5) {
                ForEach(Weekday.allCases) { day in
                    let on = selection.contains(day)
                    Button {
                        if on { selection.remove(day) } else { selection.insert(day) }
                    } label: {
                        Text(label(day)).font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .foregroundStyle(on ? Palette.paper : Palette.ink)
                            .background(on ? Palette.ink : Palette.card, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(on ? Palette.ink : Palette.lineStrong, lineWidth: 1.5))
                            .contentShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(day.rawValue)
                    .accessibilityValue(on ? "Selected" : "Not selected")
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("available-day-" + day.rawValue.lowercased())
                }
            }
            Text(selection.isEmpty ? "Any day" : "Shows classes that meet on every picked day. Fully online classes still show.")
                .font(.system(size: 11)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Fully online toggle plus class days, in one card. Used in the results sidebar.
struct FilterCard: View {
    @Binding var onlineOnly: Bool
    @Binding var days: Set<Weekday>
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Filters").font(.system(size: 12, weight: .semibold))
            Toggle("Fully online only", isOn: $onlineOnly).toggleStyle(.checkbox).font(.system(size: 12))
            AvailableDaysPicker(selection: $days)
        }
        .padding(14)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.line))
    }
}
