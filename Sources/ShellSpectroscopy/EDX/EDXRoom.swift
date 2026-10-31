//
//  EDXRoom.swift
//  Role: the EDX room (mac4DSTEM's Spectroscopy room, ADR 056 "maps first", cut to macTEM): a spectrum image from a Velox
//        .emd or a GMS .dm4 shown as maps, one spectrum and one results table, mounted by `WorkspaceView`'s room switch.
//        The room has its own document, the spectrum image, which is not an open image: it is opened from here
//        (`EDXRoomState.requestImport`) and held by `EDXSession`, so the Image, FFT and Results rooms keep their files.
//
//        LAYOUT: a 26-pt header (the file · the region's counts · Quantify) over the maps; below them the spectrum with the
//        results table beside it. The elements, Auto ID, the region, the quantification choices and the exports are the
//        inspector's (`EDXRoomInspector.swift`). The numbers are SpectroKit's; this file draws them.
//
//        EXPORT: the save panel is SwiftUI's `fileExporter` over a small text document (the results table, the method, the
//        spectrum are all text; no accessory is needed, which is what the Image room's AppKit panel exists for).
//

import ShellLayout
import SwiftUI
import UniformTypeIdentifiers
import ShellEDXModel

public struct EDXRoom: View {
    let session: EDXSession
    let state: EDXRoomState
    let actions: EDXRoomActions
    let openExtensions: [String]
    @State private var showImporter = false

    /// `openExtensions`: the file extensions the Open panel offers and the empty room names ("emd", "dm4", "msa"), the ones the
    /// app's opener reads.
    public init(session: EDXSession, state: EDXRoomState, actions: EDXRoomActions, openExtensions: [String]) {
        self.session = session; self.state = state; self.actions = actions; self.openExtensions = openExtensions
    }

    /// The Open panel's types: one per extension; any file when none is known.
    package static func importTypes(for extensions: [String]) -> [UTType] {
        let types = extensions.compactMap { UTType(filenameExtension: $0) }
        return types.isEmpty ? [.data] : types
    }

    public var body: some View {
        Group {
            if session.isOpening {
                VStack(spacing: 12) {
                    ProgressView(value: session.openProgress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: EDXLayout.openingBarWidth)
                    Text("Opening spectrum image").font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("edx.opening")
            } else if session.hasImage {
                VStack(spacing: 0) {
                    // No strip above the maps: the file, counts and region are the toolbar's display; the tools, the map mode and the lower pane are the inspector's.
                    if session.isSingleSpectrum {
                        // One pixel has no maps: the spectrum and its results are the whole room.
                        EDXLowerPane(session: session, state: state)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VerticalPaneSplit(storageKey: "edx.lowerSplit", defaultFraction: 0.6, resizeLabel: "Resize the maps and the spectrum",
                                          topName: "Maps", minimumTop: EDXLayout.lowerPaneMinimumHeight, minimumBottom: EDXLayout.lowerPaneMinimumHeight) {
                            EDXMapsBlock(session: session, state: state, overlay: actions.mapOverlay)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } bottom: {
                            EDXLowerPane(session: session, state: state)
                        }
                    }
                }
            } else {
                ContentUnavailableView {
                    Label(EDXRoomFormat.emptyTitle, systemImage: "waveform.path.ecg")
                } description: {
                    Text(EDXRoomFormat.openPrompt(extensions: openExtensions))
                } actions: {
                    Button("Open Spectrum Image…") { state.requestImport() }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("edx.openImage")
                }
            }
        }
        .onChange(of: state.importRequest) { showImporter = true }
        .onChange(of: session.fileName) { state.window = nil; state.soloTile = nil; state.appearance = MapAppearance() }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: Self.importTypes(for: openExtensions), allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { session.open(url: url) }
            case .failure(let error): actions.present(error)
            }
        }
        .fileExporter(isPresented: Binding(get: { state.exporting != nil }, set: { if !$0 { state.exporting = nil } }),
                      document: EDXExportFile(data: state.exportData),
                      contentType: state.exporting?.contentType ?? .commaSeparatedText,
                      defaultFilename: session.exportStem + (state.exporting?.suffix ?? "")) { result in
            switch result {
            case .success(let url): actions.report("Exported \(url.lastPathComponent)")
            case .failure(let error): actions.present(error)
            }
        }
        // Esc goes back to the arrow tool wherever the focus is in the window (the tools are in the inspector, outside this view, and a
        // tile being drawn on holds no focus, so `onExitCommand` here would rarely hear the key). A key equivalent, enabled only while a
        // drawing tool is chosen, so Esc is left alone otherwise; a text field or a sheet that takes Esc itself still comes first.
        .background {
            Button("Arrow Tool") { state.escape() }
                .keyboardShortcut(.cancelAction)
                .disabled(state.tool == .pointer)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("edx.room")
    }
}

/// The lower block: the spectrum (always, the regions' spectra overlaid; a profile along a drawn line as a faint inset over it) and the results beside it with a divider to drag. The per-region table
/// is a result, so it is part of the results area, not a pane of its own.
private struct EDXLowerPane: View {
    let session: EDXSession
    let state: EDXRoomState

    var body: some View {
        let layers = EDXRegionBridge.layers(session, pixel: state.hoverPixel.flatMap { session.pixelSpectrum(x: $0.x, y: $0.y) }, plot: session.plot)
        let profile = session.isSingleSpectrum ? [] : EDXRegionBridge.series(session)
        HorizontalPaneSplit(storageKey: "edx.resultsSplit", defaultFraction: 0.6, resizeLabel: "Resize the spectrum and the results", leadingName: "Spectrum",
                            minimumLeading: EDXLayout.spectrumMinimumWidth, minimumTrailing: EDXLayout.resultsWidth.min) {
            EDXSpectrumView(plot: session.plot, markers: session.markers, hasFit: session.fit != nil, layers: layers, state: state)
                .overlay(alignment: .topLeading) {
                    SpectrumLayerLegend(layers: layers.filter { !$0.isTemporary }).padding(.leading, 56).padding(.top, 2)
                }
                .overlay(alignment: .topTrailing) {
                    if !profile.isEmpty {
                        // The profile along the selected line, over the spectrum: its own colours on a faint plate, so the spectrum stays visible.
                        ProfileChart(series: profile, unit: session.scanPixel?.unit ?? "px", valueTitle: session.mapMode.title)
                            .frame(width: 240, height: 120)   // science: an inset chart
                            .padding(6)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                            .padding(8)
                    }
                }
        } trailing: {
            EDXResultsPanel(session: session)
        }
    }
}

/// A file the save panel writes: the bytes `EDXRoomState.export` made (text, or the maps PNG).
public struct EDXExportFile: FileDocument {
    public static var readableContentTypes: [UTType] { [.commaSeparatedText, .json, .png, .plainText] }
    public var data: Data

    public init(data: Data) { self.data = data }

    public init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
