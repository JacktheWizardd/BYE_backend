import SwiftUI
import ClasswiseCore

struct AvailableDaysPicker: View {
    @Binding var selection: Set<Weekday>
    private func binding(for day: Weekday) -> Binding<Bool> {
        Binding(get: { selection.contains(day) }, set: { selected in
            if selected { selection.insert(day) } else { selection.remove(day) }
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Class days").font(.system(size: 12, weight: .semibold))
                Spacer()
                if !selection.isEmpty {
                    Button("Clear days") { selection.removeAll() }.buttonStyle(.link).font(.system(size: 11))
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 0), count: 7), spacing: 0) {
                ForEach(Weekday.allCases) { day in
                    VStack(spacing: 6) {
                        Toggle(day.rawValue, isOn: binding(for: day)).labelsHidden().toggleStyle(.checkbox).fixedSize()
                            .accessibilityLabel(day.rawValue)
                            .accessibilityIdentifier("available-day-" + day.rawValue.lowercased())
                        Text(day.shortLabel).font(.system(size: 11))
                            .onTapGesture { binding(for: day).wrappedValue.toggle() }
                            .accessibilityHidden(true)
                    }.frame(maxWidth: .infinity)
                }
            }
            Text(selection.isEmpty ? "Any day" : "Showing classes that meet only on these days. Fully online classes are also shown.")
                .font(.system(size: 11)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
