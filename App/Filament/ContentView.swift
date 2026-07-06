import SwiftUI
import AppKit
import ThreeMFKit

struct ContentView: View {
    @EnvironmentObject private var model: DocumentModel
    @State private var isTargeted = false

    var body: some View {
        Group {
            if let document = model.document {
                LoadedDocumentView(document: document)
            } else if model.isLoading {
                ProgressView("Loading…")
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DropZoneView(isTargeted: isTargeted, errorMessage: model.errorMessage)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            DispatchQueue.main.async {
                guard ModelFormat(fileExtension: url.pathExtension) != nil else {
                    model.setUnsupportedFormatError()
                    return
                }
                model.load(url: url)
            }
        }
        return true
    }
}

/// Empty-state drop zone, shown before a document is loaded.
private struct DropZoneView: View {
    let isTargeted: Bool
    let errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle(.secondary)
            Text("Drop a 3MF, STL, OBJ, or PLY file here")
                .font(.title2.weight(.medium))
            Text("or press ⌘O to open")
                .font(.body)
                .foregroundStyle(.secondary)
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.3))
                .padding(24)
        )
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
    }
}

/// Main split view shown once a document has finished loading.
private struct LoadedDocumentView: View {
    let document: ThreeMFDocument
    @EnvironmentObject private var model: DocumentModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var cameraMode: PreviewCameraMode = .threeD
    @State private var useModelColors = true

    private var selectedPlate: BuildPlate {
        let plates = document.plates
        let index = min(max(model.selectedPlateIndex, 0), plates.count - 1)
        return plates[index]
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                SceneKitView(
                    plate: selectedPlate,
                    cameraMode: cameraMode,
                    useModelColors: useModelColors,
                    isDark: colorScheme == .dark,
                    documentToken: model.loadGeneration
                )
                .ignoresSafeArea()
                InfoPanel(plate: selectedPlate, unit: document.unit)
                    .padding(16)
                HStack(spacing: 10) {
                    CameraModePicker(cameraMode: $cameraMode)
                    if selectedPlate.hasColorData {
                        ColorModePicker(useModelColors: $useModelColors)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            BottomBar(fileName: model.fileURL?.lastPathComponent, plates: document.plates, selectedIndex: $model.selectedPlateIndex)
        }
    }
}

/// Small floating segmented control for switching between the perspective
/// ("3D") and orthographic top-down ("2D") preview cameras.
private struct CameraModePicker: View {
    @Binding var cameraMode: PreviewCameraMode

    var body: some View {
        Picker("Camera", selection: $cameraMode) {
            Text("2D").tag(PreviewCameraMode.twoD)
            Text("3D").tag(PreviewCameraMode.threeD)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 100)
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
    }
}

/// Segmented control for switching between real filament colors and a neutral
/// monochrome studio look. Shown only for plates with multi-color data.
private struct ColorModePicker: View {
    @Binding var useModelColors: Bool

    var body: some View {
        Picker("Colors", selection: $useModelColors) {
            Text("Color").tag(true)
            Text("Mono").tag(false)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 120)
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
    }
}

/// Bottom chrome: the loaded file's name, plus the plate strip when the
/// document has more than one build plate.
private struct BottomBar: View {
    let fileName: String?
    let plates: [BuildPlate]
    @Binding var selectedIndex: Int

    var body: some View {
        VStack(spacing: 0) {
            if let fileName {
                Text(fileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(.thinMaterial)
            }
            if plates.count > 1 {
                PlateSelector(plates: plates, selectedIndex: $selectedIndex)
            }
        }
    }
}

/// Thumbnail strip for switching between build plates.
private struct PlateSelector: View {
    let plates: [BuildPlate]
    @Binding var selectedIndex: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(plates.enumerated()), id: \.element.id) { index, plate in
                    PlateThumbnailButton(
                        plate: plate,
                        isSelected: index == selectedIndex,
                        action: { selectedIndex = index }
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(.thinMaterial)
    }
}

private struct PlateThumbnailButton: View {
    let plate: BuildPlate
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                thumbnailImage
                    .frame(width: 56, height: 56)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                    )
                Text(plate.name)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var thumbnailImage: some View {
        if let data = plate.thumbnail, let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Image(systemName: "square.stack.3d.up")
                .foregroundStyle(.secondary)
        }
    }
}

/// Compact stats overlay: dimensions, triangle count, print time, weight,
/// printer model, filament chips.
private struct InfoPanel: View {
    let plate: BuildPlate
    let unit: LengthUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let dimensions = PrintStatsFormatter.dimensions(for: plate.mesh, unit: unit) {
                Label(dimensions, systemImage: "arrow.up.left.and.arrow.down.right")
            }
            Label(PrintStatsFormatter.triangleCount(plate.mesh.triangleCount), systemImage: "triangle")

            if let stats = plate.stats {
                if let seconds = stats.predictionSeconds {
                    Label(PrintStatsFormatter.duration(seconds: seconds), systemImage: "clock")
                }
                if let grams = stats.weightGrams {
                    Label(PrintStatsFormatter.weight(grams: grams), systemImage: "scalemass")
                }
                if let printer = stats.printerModel {
                    Label(printer, systemImage: "printer")
                }
                if !stats.filaments.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(stats.filaments.enumerated()), id: \.offset) { _, filament in
                            FilamentChip(filament: filament)
                        }
                    }
                }
            }
        }
        .font(.caption)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
    }
}

private struct FilamentChip: View {
    let filament: FilamentUsage

    var body: some View {
        Circle()
            .fill(PrintStatsFormatter.color(fromHex: filament.colorHex) ?? Color.gray)
            .frame(width: 12, height: 12)
            .overlay(Circle().strokeBorder(.secondary.opacity(0.3), lineWidth: 0.5))
    }
}

#Preview {
    ContentView()
        .environmentObject(DocumentModel())
}
