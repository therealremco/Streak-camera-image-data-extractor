import AppKit
import StreakData
import SwiftUI
import UniformTypeIdentifiers

@main
struct StreakExtractorApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 580)
                .onAppear {
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 1100, height: 720)
    }
}

struct ContentView: View {
    @State private var image: PixelImage?
    @State private var preview: CGImage?
    @State private var sourceURL: URL?
    @State private var row = 0
    @State private var samples: [Double] = []
    @State private var errorMessage: String?
    @State private var status = "Open a TIFF image to begin."

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button("Open TIFF…", action: openImage)
                    .keyboardShortcut("o")
                Text(sourceURL?.lastPathComponent ?? "Streak-camera data extractor")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button("Save…", action: saveData)
                    .keyboardShortcut("s")
                    .disabled(image == nil)
            }
            if let image, let preview {
                HStack(alignment: .top, spacing: 24) {
                    VStack {
                        Text("Image · \(image.width) × \(image.height)")
                            .font(.headline)
                        ImageSampler(image: preview, row: row, selectRow: selectRow)
                        Text("Click or drag to select a row. Preview contrast is auto-scaled.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    VStack {
                        Text("Brightness · row \(row)")
                            .font(.headline)
                        ProfilePlot(samples: samples)
                        Text(image.isColor ? "Y: RGB luminance (original \(image.bitDepth)-bit scale)" :
                                "Y: original \(image.bitDepth)-bit pixel value")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                HStack {
                    Text("Row \(row) / \(image.height - 1)")
                        .monospacedDigit()
                        .frame(width: 130, alignment: .leading)
                    Button("↑") { selectRow(row - 1) }
                        .keyboardShortcut(.upArrow, modifiers: [])
                        .disabled(row == 0)
                        .help("Move one row up")
                    Slider(
                        value: Binding(get: { Double(row) }, set: { selectRow(Int($0)) }),
                        in: 0...Double(max(1, image.height - 1)), step: 1
                    )
                    .disabled(image.height == 1)
                    .accessibilityLabel("Sample row")
                    Button("↓") { selectRow(row + 1) }
                        .keyboardShortcut(.downArrow, modifiers: [])
                        .disabled(row == image.height - 1)
                        .help("Move one row down")
                }
            } else {
                ContentUnavailableView {
                    Label("Open a streak-camera TIFF", systemImage: "photo")
                } description: {
                    Text("Select a horizontal row to inspect and export its pixel values.")
                } actions: {
                    Button("Open TIFF…", action: openImage)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(20)
        .alert("Unable to complete the operation", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func selectRow(_ value: Int) {
        guard let image else { return }
        let selected = max(0, min(image.height - 1, value))
        do {
            samples = try image.row(selected)
            row = selected
            status = "Row \(row) from top · \(image.width) samples · X starts at 0"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.tiff]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let loaded = try PixelImage(contentsOf: url)
            let display = try loaded.preview()
            let initialRow = loaded.height / 2
            let initialSamples = try loaded.row(initialRow)
            image = loaded
            preview = display
            sourceURL = url
            row = initialRow
            samples = initialSamples
            status = "Row \(row) from top · \(loaded.width) samples · X starts at 0"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveData() {
        guard let image, let sourceURL else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(sourceURL.deletingPathExtension().lastPathComponent)_row\(row).txt"
        panel.directoryURL = sourceURL.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try image.save(row: row, to: url)
            status = "Saved row \(row): \(url.path)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ImageSampler: View {
    let image: CGImage
    let row: Int
    let selectRow: (Int) -> Void

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / CGFloat(image.width),
                            geometry.size.height / CGFloat(image.height))
            let width = CGFloat(image.width) * scale
            let height = CGFloat(image.height) * scale
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.none)
                .frame(width: width, height: height)
                .overlay(alignment: .topLeading) {
                    Path { path in
                        let y = (CGFloat(row) + 0.5) * scale
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: width, y: y))
                    }
                    .stroke(.red, lineWidth: 2)
                    .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    selectRow(Int(floor(value.location.y / scale)))
                })
                .accessibilityLabel("TIFF image with sampling line on row \(row)")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct ProfilePlot: View {
    let samples: [Double]

    var body: some View {
        Canvas { context, size in
            guard !samples.isEmpty else { return }
            let area = CGRect(x: 55, y: 18, width: max(1, size.width - 75),
                              height: max(1, size.height - 64))
            let lower = min(0, samples.min() ?? 0)
            let upper = max(lower + 1, samples.max() ?? 1)
            for tick in 0...4 {
                let fraction = Double(tick) / 4
                let y = area.maxY - fraction * area.height
                var grid = Path()
                grid.move(to: CGPoint(x: area.minX, y: y))
                grid.addLine(to: CGPoint(x: area.maxX, y: y))
                context.stroke(grid, with: .color(.secondary.opacity(0.2)))
                let label = (lower + fraction * (upper - lower))
                    .formatted(.number.precision(.fractionLength(0...1)))
                context.draw(Text(label).font(.caption2).foregroundStyle(.secondary),
                             at: CGPoint(x: area.minX - 7, y: y), anchor: .trailing)
                let x = area.minX + fraction * area.width
                let pixel = Int((fraction * Double(samples.count - 1)).rounded())
                context.draw(Text("\(pixel)").font(.caption2).foregroundStyle(.secondary),
                             at: CGPoint(x: x, y: area.maxY + 14))
            }
            var profile = Path()
            for (index, value) in samples.enumerated() {
                let x = area.minX + Double(index) / Double(max(1, samples.count - 1)) * area.width
                let y = area.maxY - (value - lower) / (upper - lower) * area.height
                if index == 0 { profile.move(to: CGPoint(x: x, y: y)) }
                else { profile.addLine(to: CGPoint(x: x, y: y)) }
                if samples.count == 1 {
                    context.fill(Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6)),
                                 with: .color(.accentColor))
                }
            }
            context.stroke(profile, with: .color(.accentColor), lineWidth: 1.5)
            context.draw(Text("X: horizontal pixel index").font(.caption).foregroundStyle(.secondary),
                         at: CGPoint(x: area.midX, y: size.height - 7))
        }
        .accessibilityLabel("Brightness profile with \(samples.count) samples")
    }
}
