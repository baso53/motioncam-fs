import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var settingsManager = SettingsManager()

    var body: some View {
        GeometryReader { geometry in
            HSplitView {
                // Left Panel - File Management
                VStack(spacing: 0) {
                    // Header
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "camera.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.accentColor)
                            Text("MotionCam Fuse")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                        }

                        Text("Drop one or more MCRAW files to mount")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 30)
                    .padding(.horizontal, 24)

                    // Drop Area
                    DropAreaView()
                        .frame(height: 200)
                        .padding(.horizontal, 24)
                        .padding(.top, 10)
                        .environmentObject(settingsManager)

                    // Mounted Files Section
                    if !appState.mountedFiles.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Mounted Files")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                Spacer()
                                Text("\(appState.mountedFiles.count) file\(appState.mountedFiles.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.secondary.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                            .padding(.horizontal, 24)

                            ScrollView {
                                LazyVStack(spacing: 12) {
                                    ForEach(appState.mountedFiles) { file in
                                        MountedFileView(file: file)
                                            .padding(.horizontal, 24)
                                    }
                                }
                                .padding(.bottom, 20)
                            }
                        }
                        .padding(.top, 20)
                    }

                    Spacer()
                }
                .frame(minWidth: 420)
                .background(Color(NSColor.windowBackgroundColor))

                // Middle Panel - Render Settings
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    HStack {
                        Text("Render Settings")
                            .font(.title2)
                            .fontWeight(.bold)
                        Spacer()
                        Button(action: { settingsManager.resetToDefaults() }) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset")
                        }
                        .buttonStyle(SettingsButtonStyle())
                    }
                    .padding(20)
                    .padding(.bottom, 10)

                    ScrollView {
                        VStack(spacing: 20) {
                            // Output Settings
                            SettingsGroup(title: "Output", icon: "folder") {
                                VStack(spacing: 16) {
                                    // Cache Folder
                                    SettingsRow(label: "DNG Output Folder") {
                                        VStack(alignment: .trailing, spacing: 8) {
                                            Text(settingsManager.cacheFolder.isEmpty ? "Same as source" : URL(fileURLWithPath: settingsManager.cacheFolder).lastPathComponent)
                                                .font(.system(.body, design: .monospaced))
                                                .foregroundColor(.secondary)
                                                .truncationMode(.middle)
                                                .frame(maxWidth: 200)

                                            Button("Set Folder") {
                                                settingsManager.selectCacheFolder()
                                            }
                                            .controlSize(.small)
                                        }
                                    }

                                    Divider()
                                        .padding(.vertical, 4)

                                    Text("DNG sequences will be generated in the specified location")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            // Processing Options
                            SettingsGroup(title: "Processing", icon: "slider.horizontal.3") {
                                VStack(spacing: 20) {
                                    // Frame Rate Conversion
                                    SettingsToggleRow(
                                        label: "Frame Rate Conversion",
                                        isOn: $settingsManager.cfrConversion,
                                        description: "Maintain sync with constant framerate"
                                    ) {
                                        Picker("", selection: $settingsManager.cfrTarget) {
                                            Text("Prefer Drop Frame").tag("Prefer Drop Frame")
                                            Text("Prefer Integer").tag("Prefer Integer")
                                            Text("Median (Slowmotion)").tag("Median (Slowmotion)")
                                            Text("Average (Testing)").tag("Average (Testing)")
                                        }
                                        .pickerStyle(MenuPickerStyle())
                                        .frame(width: 180)
                                        .disabled(!settingsManager.cfrConversion)
                                    }

                                    // Normalize Exposure
                                    SettingsToggleRow(
                                        label: "Normalize Exposure",
                                        isOn: $settingsManager.normalizeExposure,
                                        description: "Compensate for exposure changes"
                                    ) {
                                        Picker("", selection: $settingsManager.exposureCompensation) {
                                            Text("-2 EV").tag("-2ev")
                                            Text("-1 EV").tag("-1ev")
                                            Text("0 EV").tag("0ev")
                                            Text("+1 EV").tag("1ev")
                                            Text("+2 EV").tag("2ev")
                                            Text("+3 EV").tag("3ev")
                                        }
                                        .pickerStyle(MenuPickerStyle())
                                        .frame(width: 100)
                                        .disabled(!settingsManager.normalizeExposure)
                                    }

                                    // Camera Model Override
                                    SettingsToggleRow(
                                        label: "Camera Model Override",
                                        isOn: $settingsManager.camModelOverride,
                                        description: "Unlock additional RAW options"
                                    ) {
                                        Picker("", selection: $settingsManager.cameraModel) {
                                            Text("Panasonic").tag("Panasonic")
                                            Text("Blackmagic").tag("Blackmagic")
                                            Text("Fujifilm").tag("Fujifilm")
                                        }
                                        .pickerStyle(MenuPickerStyle())
                                        .frame(width: 140)
                                        .disabled(!settingsManager.camModelOverride)
                                    }

                                    // White/Black Levels
                                    SettingsRow(label: "White/Black Levels") {
                                        Picker("", selection: $settingsManager.levels) {
                                            Text("Dynamic").tag("Dynamic")
                                            Text("Static").tag("Static")
                                            Text("1023/64").tag("1023/64")
                                            Text("4095/256").tag("4095/256")
                                            Text("16383/1024").tag("16383/1024")
                                            Text("65535/4096").tag("65535/4096")
                                            Text("4095/64").tag("4095/64")
                                            Text("16383/64").tag("16383/64")
                                            Text("16383/0").tag("16383/0")
                                        }
                                        .pickerStyle(MenuPickerStyle())
                                        .frame(width: 140)
                                    }
                                }
                            }
                        }
                        .padding(20)
                    }
                }
                .frame(minWidth: 350)
                .background(Color(NSColor.windowBackgroundColor))

                // Right Panel - Advanced Options
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    HStack {
                        Text("Advanced")
                            .font(.title2)
                            .fontWeight(.bold)
                        Spacer()
                        Image(systemName: "gear")
                            .foregroundColor(.secondary)
                    }
                    .padding(20)
                    .padding(.bottom, 10)

                    ScrollView {
                        VStack(spacing: 20) {
                            // Vignette Correction
                            SettingsGroup(title: "Vignette Correction", icon: "circle.grid.3x3") {
                                VStack(spacing: 16) {
                                    SettingsToggleRow(
                                        label: "Enable Vignette Correction",
                                        isOn: $settingsManager.vignetteCorrection,
                                        description: "Fix corner shading"
                                    ) {}

                                    if settingsManager.vignetteCorrection {
                                        VStack(spacing: 12) {
                                            Toggle("Color Correction Only", isOn: $settingsManager.vignetteOnlyColor)
                                                .toggleStyle(SwitchToggleStyle())

                                            HStack {
                                                Toggle("Scale Data", isOn: $settingsManager.scaleRaw)
                                                Toggle("Debug Mode", isOn: $settingsManager.debugVignette)
                                            }

                                            Text("Apply gainmaps to raw pixel values before writing DNG")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(.leading, 20)
                                    }
                                }
                            }

                            // Log Transform
                            SettingsGroup(title: "Log Transfer Curve", icon: "chart.line.uptrend.xyaxis") {
                                VStack(spacing: 16) {
                                    SettingsToggleRow(
                                        label: "Enable Log Transform",
                                        isOn: $settingsManager.logTransform,
                                        description: "Apply logarithmic curve"
                                    ) {
                                        if settingsManager.logTransform {
                                            Picker("", selection: $settingsManager.logTransformMode) {
                                                Text("Keep Input").tag("Keep Input")
                                                Text("-2 Bit").tag("Reduce by 2bit")
                                                Text("-4 Bit").tag("Reduce by 4bit")
                                                Text("-6 Bit").tag("Reduce by 6bit")
                                            }
                                            .pickerStyle(MenuPickerStyle())
                                            .frame(width: 140)
                                        }
                                    }
                                }
                            }

                            // Proxy Mode
                            SettingsGroup(title: "Proxy Mode", icon: "square.resize") {
                                VStack(spacing: 16) {
                                    SettingsToggleRow(
                                        label: "Enable Proxy/Binning",
                                        isOn: $settingsManager.draftMode,
                                        description: "Scale down for better performance"
                                    ) {
                                        if settingsManager.draftMode {
                                            Picker("", selection: $settingsManager.draftQuality) {
                                                Text("2×").tag(2)
                                                Text("4×").tag(4)
                                                Text("8×").tag(8)
                                            }
                                            .pickerStyle(SegmentedPickerStyle())
                                        }
                                    }
                                }
                            }

                            // Crop
                            SettingsGroup(title: "Crop Settings", icon: "crop") {
                                VStack(spacing: 16) {
                                    SettingsToggleRow(
                                        label: "Enable Crop",
                                        isOn: $settingsManager.cropEnable,
                                        description: "Crop to specific resolution"
                                    ) {
                                        if settingsManager.cropEnable {
                                            Picker("", selection: $settingsManager.cropTarget) {
                                                Text("4096×2304").tag("4096x2304")
                                                Text("4096×2560").tag("4096x2560")
                                                Text("4080×2296").tag("4080x2296")
                                                Text("4080×2288").tag("4080x2288")
                                                Text("4000×2256").tag("4000x2256")
                                                Text("4000×3000").tag("4000x3000")
                                                Text("4624×2608").tag("4624x2608")
                                            }
                                            .pickerStyle(MenuPickerStyle())
                                            .frame(width: 120)
                                        }
                                    }
                                }
                            }

                            // Quad Bayer
                            SettingsGroup(title: "Quad Bayer CFA", icon: "camera.macro") {
                                VStack(spacing: 16) {
                                    SettingsToggleRow(
                                        label: "Interpret as Quad Bayer",
                                        isOn: $settingsManager.quadBayer,
                                        description: "Process quad bayer sensors"
                                    ) {
                                        if settingsManager.quadBayer {
                                            Picker("", selection: $settingsManager.quadBayerOption) {
                                                Text("Wrong CFA").tag("Wrong CFA Metadata")
                                                Text("Correct QBCFA").tag("Correct QBCFA Metadata")
                                            }
                                            .pickerStyle(MenuPickerStyle())
                                            .frame(width: 140)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(20)
                    }
                }
                .frame(minWidth: 320)
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .overlay(
            // Loading Overlay
            Group {
                if appState.isLoading {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    VStack(spacing: 20) {
                        ZStack {
                            Circle()
                                .stroke(Color.accentColor.opacity(0.2), lineWidth: 8)
                                .frame(width: 80, height: 80)

                            Circle()
                                .trim(from: 0, to: 0.7)
                                .stroke(
                                    LinearGradient(
                                        colors: [.accentColor, .accentColor.opacity(0.3)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                                )
                                .frame(width: 80, height: 80)
                                .rotationEffect(.degrees(-90))
                                .animation(.easeInOut(duration: 1).repeatForever(autoreverses: false), value: appState.isLoading)
                        }

                        Text("Processing MCRAW...")
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                    .padding(32)
                    .background(Color(NSColor.windowBackgroundColor))
                    .cornerRadius(16)
                    .shadow(radius: 20)
                }
            }
        )
        .onAppear {
            settingsManager.loadSettings()
        }
        .onChange(of: settingsManager.settingsChanged) { _ in
            settingsManager.saveSettings()
            applySettingsToMountedFiles()
        }
    }

    private func applySettingsToMountedFiles() {
        let renderSettings = settingsManager.getRenderSettings()
        appState.updateSettingsForAllFiles(renderSettings)
    }
}

// MARK: - Supporting Views

struct DropAreaView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settingsManager: SettingsManager
    @State private var isHovering = false

    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(
                isHovering ? Color.accentColor : Color.secondary.opacity(0.3),
                style: StrokeStyle(lineWidth: 2, dash: [8])
            )
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isHovering ? Color.accentColor.opacity(0.05) : Color.clear)
            )
            .overlay(
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.1))
                            .frame(width: 80, height: 80)

                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 32))
                            .foregroundColor(.accentColor)
                    }

                    VStack(spacing: 8) {
                        Text("Drag & Drop MCRAW files")
                            .font(.headline)
                            .fontWeight(.medium)

                        Text("or browse from your computer")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Button("Browse Files") {
                        let settings = settingsManager.getRenderSettings()
                        appState.showOpenFilePanel(settings: settings)
                    }
                    .buttonStyle(BrowseButtonStyle())
                }
            )
            .scaleEffect(isHovering ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isHovering)
            .onDrop(of: [.fileURL], isTargeted: $isHovering) { providers in
                let settings = settingsManager.getRenderSettings()
                var mountedCount = 0

                for provider in providers {
                    provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { (item, error) in
                        guard let data = item as? Data,
                              let url = URL(dataRepresentation: data, relativeTo: nil),
                              url.pathExtension.lowercased() == "mcraw" else { return }

                        DispatchQueue.main.async {
                            appState.mountFile(at: url.path, settings: settings)
                        }
                    }
                }

                return true
            }
    }
}

struct MountedFileView: View {
    let file: MountedFile
    @EnvironmentObject var appState: AppState
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 16) {
            // File Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [.accentColor.opacity(0.2), .accentColor.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)

                Image(systemName: "video.fill")
                    .font(.title3)
                    .foregroundColor(.accentColor)
            }

            // File Info
            VStack(alignment: .leading, spacing: 6) {
                Text(URL(fileURLWithPath: file.path).lastPathComponent)
                    .font(.headline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if let fileInfo = file.fileInfo {
                    HStack(spacing: 12) {
                        Label("\(fileInfo.width)×\(fileInfo.height)", systemImage: "rectangle")
                        Label("\(fileInfo.totalFrames) frames", systemImage: "film")
                        Label("\(String(format: "%.2f", fileInfo.fps)) fps", systemImage: "speedometer")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)

                    if fileInfo.droppedFrames > 0 || fileInfo.duplicatedFrames > 0 {
                        HStack(spacing: 12) {
                            if fileInfo.droppedFrames > 0 {
                                Label("-\(fileInfo.droppedFrames)", systemImage: "minus.circle.fill")
                                    .foregroundColor(.orange)
                            }
                            if fileInfo.duplicatedFrames > 0 {
                                Label("+\(fileInfo.duplicatedFrames)", systemImage: "plus.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                        .font(.caption2)
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text(URL(fileURLWithPath: file.mountPoint).lastPathComponent)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Actions
            HStack(spacing: 8) {
                Button(action: { appState.openMountPoint(file) }) {
                    Image(systemName: "folder")
                }
                .buttonStyle(ActionButtonStyle())
                .help("Open in Finder")

                Button(action: {
                    // Play functionality if needed
                }) {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(ActionButtonStyle())
                .help("Preview")

                Button(action: { appState.unmountFile(id: file.id) }) {
                    Image(systemName: "eject.fill")
                }
                .buttonStyle(ActionButtonStyle(isDestructive: true))
                .help("Unmount")
            }
            .opacity(isHovered ? 1 : 0.7)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isHovered ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Settings Components

struct SettingsGroup<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                    .font(.headline)
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }

            content
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
        }
    }
}

struct SettingsRow<Content: View>: View {
    let label: String
    let content: Content
    
    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.body)
            Spacer()
            content
        }
    }
}

struct SettingsToggleRow<Content: View>: View {
    let label: String
    @Binding var isOn: Bool
    let description: String?
    let content: Content?

    init(label: String, isOn: Binding<Bool>, description: String? = nil, @ViewBuilder content: () -> Content) {
        self.label = label
        self._isOn = isOn
        self.description = description
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Toggle(label, isOn: $isOn)
                    .toggleStyle(SwitchToggleStyle())
                Spacer()
                content
            }

            if let description = description {
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)
            }
        }
    }
}

// MARK: - Custom Button Styles

struct BrowseButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
    
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: configuration.isPressed ? [.accentColor.opacity(0.8), .accentColor.opacity(0.6)] : [.accentColor, .accentColor.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(8)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

struct SettingsButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.1))
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

struct ActionButtonStyle: ButtonStyle {
    let isDestructive: Bool

    init(isDestructive: Bool = false) {
        self.isDestructive = isDestructive
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .foregroundColor(isDestructive ? .red : .accentColor)
            .frame(width: 32, height: 32)
            .background(
                Circle()
                    .fill((isDestructive ? Color.red : Color.accentColor).opacity(0.1))
            )
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
    }
}
