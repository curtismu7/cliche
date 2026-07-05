import AppKit
import ClicheKit
import SwiftUI

/// Pick 2–6 recent captures and a layout; the combined image is saved as a
/// new capture (file + clipboard + Captures tab).
struct CombineSheet: View {
    let store: CapturesStore
    let onDone: () -> Void

    @State private var selectedIDs: [UUID] = []  // ordered by pick
    @State private var layout: Combiner.Layout = .horizontal

    private var recent: [CapturesStore.Capture] { Array(store.captures.prefix(8)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Combine captures")
                .font(.system(size: 13, weight: .semibold))
            Text("Pick 2–6 (numbers show the order), choose a layout.")
                .font(.system(size: 11.5)).foregroundStyle(.secondary)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(recent, id: \.id) { capture in
                        thumbnail(for: capture)
                    }
                }
            }
            .frame(height: 84)

            Picker("Layout", selection: $layout) {
                ForEach(Combiner.Layout.allCases, id: \.self) { layout in
                    Text(layout.label).tag(layout)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack {
                Spacer()
                Button("Cancel", action: onDone)
                    .keyboardShortcut(.cancelAction)
                Button("Combine") { combine() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedIDs.count < 2)
            }
        }
        .padding(14)
        .frame(width: 420)
    }

    private func thumbnail(for capture: CapturesStore.Capture) -> some View {
        let order = selectedIDs.firstIndex(of: capture.id)
        return ZStack(alignment: .topLeading) {
            if let image = NSImage(contentsOfFile: capture.path) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 110, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                    .frame(width: 110, height: 76)
            }
            RoundedRectangle(cornerRadius: 6)
                .stroke(order != nil ? Color.red : Color.primary.opacity(0.15),
                        lineWidth: order != nil ? 2 : 1)
                .frame(width: 110, height: 76)
            if let order {
                Text("\(order + 1)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(.red))
                    .padding(4)
            }
        }
        .onTapGesture {
            if let index = selectedIDs.firstIndex(of: capture.id) {
                selectedIDs.remove(at: index)
            } else if selectedIDs.count < 6 {
                selectedIDs.append(capture.id)
            }
        }
    }

    private func combine() {
        let images = selectedIDs.compactMap { id -> CGImage? in
            guard let capture = recent.first(where: { $0.id == id }) else { return nil }
            return NSImage(contentsOfFile: capture.path)?
                .cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        guard images.count >= 2,
              let combined = Combiner.combine(images, layout: layout),
              let url = CaptureDelivery.deliver(combined)
        else {
            NSSound.beep()
            return
        }
        store.add(path: url.path)
        onDone()
    }
}
