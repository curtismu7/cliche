import ClicheKit
import SwiftUI

/// Top-center mode strip inside the all-in-one capture overlay.
struct ModeStripView: View {
    let current: AllInOneMode
    let onPick: (AllInOneMode) -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(AllInOneMode.allCases, id: \.self) { mode in
                    Button { onPick(mode) } label: {
                        VStack(spacing: 3) {
                            Image(systemName: mode.symbol).font(.system(size: 16))
                            Text(mode.label).font(.system(size: 10, weight: .medium))
                            Text(mode.keyEquivalent)
                                .font(.system(size: 9, design: .monospaced))
                                .opacity(0.65)
                        }
                        .frame(width: 78, height: 54)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(mode == current
                                    ? Color(red: 0.88, green: 0.19, blue: 0.19)
                                    : Color.white.opacity(0.08)))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.72)))
            Text("drag to capture · 1–4 switch mode · esc cancel")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(Capsule().fill(Color.black.opacity(0.55)))
        }
    }
}
