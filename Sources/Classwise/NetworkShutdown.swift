import SwiftUI

/// Retirement switch. When active, the shipping app makes no network requests at all:
/// no PCC schedule, no Rate My Professors, no update feed. The window shows `RetiredView`
/// instead of search, so no client is ever asked to load anything.
/// 0.4.1 shipped with it on; 0.5.0 turns BYE back on. Set it to true to retire a release again.
enum NetworkShutdown {
    static let isActive = false

    static let message = "BYE is no longer active. This version doesn’t connect to the internet, so class searches, ratings and updates are turned off. Thanks for testing BYE."
}

struct RetiredView: View {
    var body: some View {
        ZStack {
            Palette.paper.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                Brand()
                Eyebrow(title: "This version is final")
                Text("BYE has been retired.")
                    .font(BYEFont.display(30, bold: true))
                Text(NetworkShutdown.message)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("You can quit BYE and move it to the Trash whenever you like.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.secondary)
            }
            .frame(maxWidth: 520, alignment: .leading)
            .padding(40)
        }
        .foregroundStyle(Palette.ink)
        .accessibilityElement(children: .contain)
    }
}
