import SwiftUI
import AppKit

// MARK: - Enum Definitions matching Types.h

enum CFRMode: String, CaseIterable, Codable {
    case disabled = "Disabled"
    case preferInteger = "PreferInteger"
    case preferDropFrame = "PreferDropFrame"
    case medianSlowMotion = "MedianSlowMotion"
    case averageTesting = "AverageTesting"
}

enum LevelsMode: String, CaseIterable, Codable {
    case dynamic = "Dynamic"
    case originalStatic = "Original (Static)"
    case custom1023_64 = "1023/64"
    case custom4095_256 = "4095/256"
    case custom16383_1024 = "16383/1024"
    case custom65535_4096 = "65535/4096"
    case custom4095_64 = "4095/64"
    case custom16383_64 = "16383/64"
    case custom16383_0 = "16383/0"
    case custom = "Custom"
}

enum CameraModel: String, CaseIterable, Codable {
    case disabled = "Disabled"
    case panasonic = "Panasonic"
    case blackmagic = "Blackmagic"
    case fujifilm = "Fujifilm"
    case custom = "Custom"
}

// MARK: - Error Types

enum UnmountError: Error, CustomStringConvertible {
    case nonZeroExit(status: Int32, output: String)
    case timeout(timeout: TimeInterval)

    var description: String {
        switch self {
        case .nonZeroExit(let s, let out): return "umount failed (exit \(s)): \(out)"
        case .timeout(let t): return "umount timed out after \(t) seconds"
        }
    }
}

enum MountError: Error, CustomStringConvertible {
    case nonZeroExit(status: Int32, output: String)
    case timeout(timeout: TimeInterval)

    var description: String {
        switch self {
        case .nonZeroExit(let s, let out): return "Mount failed (exit \(s)): \(out)"
        case .timeout(let t): return "mount timed out after \(t) seconds"
        }
    }
}

enum DirectoryError: Error {
    case fileExistsButIsNotDirectory(path: String)
}

// MARK: - Thread-safe Results Actor

actor MountResultsCollector {
    private var results: [(String, Error?)] = []

    func append(_ result: (String, Error?)) {
        results.append(result)
    }

    func getAll() -> [(String, Error?)] {
        results
    }

    var count: Int {
        results.count
    }
}

// MARK: - Async Process Execution

extension Process {
    /// Runs the process asynchronously and waits for completion with a timeout
    func runWithTimeout(_ timeout: TimeInterval) async throws -> String {
        let stdout = Pipe()
        let stderr = Pipe()
        self.standardOutput = stdout
        self.standardError = stderr

        try run()

        // Wait for process with timeout using Task
        let startTime = Date()
        while isRunning {
            try Task.checkCancellation()

            if Date().timeIntervalSince(startTime) > timeout {
                terminate()
                // Wait with timeout to avoid indefinite hang
                let terminateStartTime = Date()
                let terminateTimeout: TimeInterval = 5.0
                while isRunning {
                    if Date().timeIntervalSince(terminateStartTime) > terminateTimeout {
                        // Process didn't terminate, give up
                        throw MountError.timeout(timeout: timeout)
                    }
                    try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
                }
                throw MountError.timeout(timeout: timeout)
            }

            // Sleep in a non-blocking way
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }

        // Check exit status
        if terminationStatus != 0 {
            let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            var output = String(data: outputData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            if !errorOutput.isEmpty { output += "\n" + errorOutput }
            throw MountError.nonZeroExit(status: terminationStatus, output: output)
        }

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: outputData, encoding: .utf8) ?? ""
    }
}

// MARK: - Render Options

struct RenderOptions: Codable {
    var cfrTarget: CFRMode = .preferDropFrame
    var cameraModel: CameraModel = .disabled
    var cameraModelCustomValue: String = ""
    var levelsMode: LevelsMode = .dynamic
    var levelsCustomValue: String = ""

    var applyVignetteCorrection: Bool = true
    var normalizeShadingMap: Bool = true
    var vignetteOnlyColor: Bool = false

    var cfrEnabled: Bool = false
    var cfrMode: CFRMode = .preferDropFrame
    var cfrCustomValue: String = ""

    // MARK: - UserDefaults

    private static let key = "savedRenderOptions"

    static func save(_ options: RenderOptions) {
        if let data = try? JSONEncoder().encode(options) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func load() -> RenderOptions {
        guard let data = UserDefaults.standard.data(forKey: key),
              let options = try? JSONDecoder().decode(RenderOptions.self, from: data) else {
            return RenderOptions()
        }
        return options
    }

    func descriptionText() -> String {
        var parts: [String] = []

        if applyVignetteCorrection {
            parts.append("Vignette correction")
            if normalizeShadingMap { parts.append("  - Normalize shading map") }
            if vignetteOnlyColor { parts.append("  - Color correction only") }
        }

        if cfrEnabled {
            if !cfrCustomValue.isEmpty {
                parts.append("CFR: \(cfrCustomValue)")
            } else {
                parts.append("CFR: \(cfrMode.rawValue)")
            }
        }

        if cameraModel != .disabled {
            if !cameraModelCustomValue.isEmpty {
                parts.append("Camera model: \(cameraModelCustomValue)")
            } else {
                parts.append("Camera model: \(cameraModel.rawValue)")
            }
        }

        if !levelsCustomValue.isEmpty {
            parts.append("Levels: \(levelsCustomValue)")
        } else if levelsMode != .dynamic {
            parts.append("Levels: \(levelsMode.rawValue)")
        }

        if parts.isEmpty {
            return "Default settings"
        }
        return parts.joined(separator: "\n")
    }

    func buildOptionsString() -> String {
        var options: [String] = []
        if applyVignetteCorrection {
            options.append("vignette_correction")
            if normalizeShadingMap { options.append("normalize_shading_map") }
            if vignetteOnlyColor { options.append("vignette_only_color") }
        }

        if cfrEnabled {
            if !cfrCustomValue.isEmpty { options.append("cfr=\(cfrCustomValue)") }
            else { options.append("cfr=\(cfrMode.rawValue)") }
        }

        if !cameraModelCustomValue.isEmpty {
            options.append("camera_model=\(cameraModelCustomValue)")
        } else if cameraModel != .disabled && cameraModel != .custom {
            options.append("camera_model=\(cameraModel.rawValue)")
        }

        if !levelsCustomValue.isEmpty {
            options.append("levels=\(levelsCustomValue)")
        } else if levelsMode != .custom {
            options.append("levels=\(levelsMode.rawValue)")
        }

        return options.joined(separator: ",")
    }
}

// MARK: - Loading Progress Sheet

@MainActor
class LoadingSheet: NSWindowController {
    private let progressIndicator: NSProgressIndicator
    private let statusLabel: NSTextField
    private let panel: NSPanel

    init(message: String = "Mounting...") {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 80),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.title = ""

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 80))
        panel.contentView = contentView

        // Progress indicator
        let indicator = NSProgressIndicator()
        indicator.style = .spinning
        indicator.frame = NSRect(x: 140, y: 45, width: 20, height: 20)
        contentView.addSubview(indicator)
        self.progressIndicator = indicator

        // Status label
        let label = NSTextField(labelWithString: message)
        label.alignment = .center
        label.frame = NSRect(x: 20, y: 15, width: 260, height: 20)
        contentView.addSubview(label)
        self.statusLabel = label

        self.panel = panel
        super.init(window: panel)

        panel.center()
        indicator.startAnimation(nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(message: String) {
        statusLabel.stringValue = message
    }

    func show() {
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    override func close() {
        progressIndicator.stopAnimation(nil)
        super.close()
    }
}

// MARK: - Application Entry Point

@main
struct MotionCamExplorerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene { }
}

// MARK: - App Delegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var didOpenFile = false

    private nonisolated func commandTimeout(for fileURL: URL) -> TimeInterval {
        let fm = FileManager.default
        guard let attributes = try? fm.attributesOfItem(atPath: fileURL.path),
              let fileSize = attributes[.size] as? UInt64 else {
            return 10.0 // Default timeout if we can't get file size
        }

        let gigabytes = Double(fileSize) / (1024 * 1024 * 1024)
        let timeout = gigabytes * 2.5

        // Minimum timeout of 2 seconds
        return max(timeout, 2.0)
    }

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !didOpenFile { showUnmountOptionsAlert() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard !urls.isEmpty else { return }
        didOpenFile = true
        if urls.count == 1 { showMountOptionsAlert(for: urls[0]) }
        else { showMultipleFilesAlert(for: urls) }
    }

    // MARK: - UI Logic

    private func showRenderOptionsDialog(for fileURL: URL, loadSaved: Bool = false) -> RenderOptions? {
        let options: RenderOptions
        if loadSaved {
            options = RenderOptions.load()
        } else {
            options = RenderOptions()
        }

        let alert = NSAlert()
        alert.messageText = loadSaved ? "Customize Render Options" : "Render Options"
        alert.informativeText = loadSaved ? "Configure default render settings." : "Configure render settings for mounting."
        if loadSaved {
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Cancel")
        } else {
            alert.addButton(withTitle: "Mount")
            alert.addButton(withTitle: "Use Defaults")
            alert.addButton(withTitle: "Cancel")
        }

        let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 340))

        // --- 1. Top Section: Checkboxes (Processing) ---
        let vignetteCorrectionCheckbox = NSButton(checkboxWithTitle: "Enable Vignette Correction", target: nil, action: nil)
        vignetteCorrectionCheckbox.frame = NSRect(x: 20, y: 310, width: 250, height: 18)
        vignetteCorrectionCheckbox.state = options.applyVignetteCorrection ? .on : .off
        accessoryView.addSubview(vignetteCorrectionCheckbox)

        let normalizeShadingCheckbox = NSButton(checkboxWithTitle: "Scale data (normalize shading map)", target: nil, action: nil)
        normalizeShadingCheckbox.frame = NSRect(x: 45, y: 285, width: 280, height: 18)
        normalizeShadingCheckbox.state = options.normalizeShadingMap ? .on : .off
        accessoryView.addSubview(normalizeShadingCheckbox)

        let vignetteOnlyColorCheckbox = NSButton(checkboxWithTitle: "Color correction only", target: nil, action: nil)
        vignetteOnlyColorCheckbox.frame = NSRect(x: 45, y: 263, width: 200, height: 18)
        vignetteOnlyColorCheckbox.state = options.vignetteOnlyColor ? .on : .off
        accessoryView.addSubview(vignetteOnlyColorCheckbox)

        // Handler for nesting logic
        class VignetteHandler: NSObject {
            let sub1: NSButton, sub2: NSButton
            init(s1: NSButton, s2: NSButton) { self.sub1 = s1; self.sub2 = s2 }
            @objc func handleChange(_ sender: NSButton) {
                let on = (sender.state == .on)
                sub1.isEnabled = on; sub2.isEnabled = on
                sub1.alphaValue = on ? 1.0 : 0.5
                sub2.alphaValue = on ? 1.0 : 0.5
            }
        }
        let vignetteHandler = VignetteHandler(s1: normalizeShadingCheckbox, s2: vignetteOnlyColorCheckbox)
        vignetteCorrectionCheckbox.target = vignetteHandler
        vignetteCorrectionCheckbox.action = #selector(VignetteHandler.handleChange(_:))

        // --- Helper to create Sections ---
        func createGroup(y: CGFloat, title: String) -> NSView {
            let box = NSView(frame: NSRect(x: 15, y: y, width: 470, height: 60))
            box.wantsLayer = true
            box.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            box.layer?.cornerRadius = 6
            box.layer?.borderWidth = 1
            box.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor

            let label = NSTextField(labelWithString: title)
            label.font = NSFont.boldSystemFont(ofSize: 12)
            label.textColor = NSColor.secondaryLabelColor
            label.frame = NSRect(x: 12, y: 34, width: 200, height: 16)
            box.addSubview(label)
            return box
        }

        // --- 2. CFR Section ---
        let cfrGroup = createGroup(y: 160, title: "Constant Frame Rate (CFR)")
        accessoryView.addSubview(cfrGroup)

        let cfrModePopup = NSPopUpButton(frame: NSRect(x: 10, y: 5, width: 200, height: 26))
        cfrModePopup.addItems(withTitles: ["Disabled", "Prefer Integer", "Prefer Drop Frame", "Median (Slow Motion)", "Average (Testing)", "Custom"])
        if options.cfrEnabled {
            if !options.cfrCustomValue.isEmpty {
                cfrModePopup.selectItem(at: 5) // Custom
            } else {
                switch options.cfrMode {
                case .preferInteger: cfrModePopup.selectItem(at: 1)
                case .preferDropFrame: cfrModePopup.selectItem(at: 2)
                case .medianSlowMotion: cfrModePopup.selectItem(at: 3)
                case .averageTesting: cfrModePopup.selectItem(at: 4)
                default: cfrModePopup.selectItem(at: 0)
                }
            }
        } else {
            cfrModePopup.selectItem(at: 0)
        }
        cfrGroup.addSubview(cfrModePopup)

        let cfrCustomContainer = NSView(frame: NSRect(x: 220, y: 5, width: 200, height: 30))
        cfrCustomContainer.isHidden = !options.cfrEnabled || options.cfrCustomValue.isEmpty
        cfrGroup.addSubview(cfrCustomContainer)

        let cfrCustomLabel = NSTextField(labelWithString: "FPS:")
        cfrCustomLabel.frame = NSRect(x: 0, y: 7, width: 35, height: 16)
        cfrCustomContainer.addSubview(cfrCustomLabel)

        let cfrCustomField = NSTextField(frame: NSRect(x: 35, y: 4, width: 60, height: 21))
        cfrCustomField.stringValue = options.cfrCustomValue.isEmpty ? "24.00" : options.cfrCustomValue
        cfrCustomField.placeholderString = "24.00"
        cfrCustomContainer.addSubview(cfrCustomField)

        let cfrHint = NSTextField(labelWithString: "(e.g., 23.976)")
        cfrHint.font = NSFont.systemFont(ofSize: 10)
        cfrHint.textColor = .tertiaryLabelColor
        cfrHint.frame = NSRect(x: 100, y: 7, width: 100, height: 14)
        cfrCustomContainer.addSubview(cfrHint)

        // --- 3. Levels Section ---
        let levelsGroup = createGroup(y: 90, title: "White Level / Black Level")
        accessoryView.addSubview(levelsGroup)

        let levelsModePopup = NSPopUpButton(frame: NSRect(x: 10, y: 5, width: 200, height: 26))
        levelsModePopup.addItems(withTitles: LevelsMode.allCases.map { $0.rawValue })
        levelsModePopup.selectItem(withTitle: options.levelsMode.rawValue)
        levelsGroup.addSubview(levelsModePopup)

        let levelsCustomContainer = NSView(frame: NSRect(x: 220, y: 5, width: 240, height: 30))
        levelsCustomContainer.isHidden = options.levelsMode != .custom || options.levelsCustomValue.isEmpty
        levelsGroup.addSubview(levelsCustomContainer)

        let levelsCustomField = NSTextField(frame: NSRect(x: 0, y: 4, width: 100, height: 21))
        levelsCustomField.placeholderString = "16383/1024"
        levelsCustomField.stringValue = options.levelsCustomValue.isEmpty ? "16383/1024" : options.levelsCustomValue
        levelsCustomContainer.addSubview(levelsCustomField)

        // --- 4. Camera Model Section ---
        let camGroup = createGroup(y: 20, title: "Override Camera Model")
        accessoryView.addSubview(camGroup)

        let camModelPopup = NSPopUpButton(frame: NSRect(x: 10, y: 5, width: 140, height: 26))
        camModelPopup.addItems(withTitles: CameraModel.allCases.map { $0.rawValue })
        camModelPopup.selectItem(withTitle: options.cameraModel.rawValue)
        camGroup.addSubview(camModelPopup)

        let camCustomContainer = NSView(frame: NSRect(x: 160, y: 5, width: 300, height: 30))
        camCustomContainer.isHidden = options.cameraModel != .custom || options.cameraModelCustomValue.isEmpty
        camGroup.addSubview(camCustomContainer)

        let camCustomField = NSTextField(frame: NSRect(x: 0, y: 4, width: 150, height: 21))
        camCustomField.placeholderString = "e.g., Sony, Canon"
        camCustomField.stringValue = options.cameraModelCustomValue
        camCustomContainer.addSubview(camCustomField)

        // --- Visibility Handlers ---
        class VisibilityHandler: NSObject {
            let targetView: NSView
            let triggerIndex: Int?
            let triggerTitle: String?

            init(view: NSView, index: Int? = nil, title: String? = nil) {
                self.targetView = view
                self.triggerIndex = index
                self.triggerTitle = title
            }

            @objc func handleChange(_ sender: NSPopUpButton) {
                if let idx = triggerIndex {
                    targetView.isHidden = (sender.indexOfSelectedItem != idx)
                } else if let title = triggerTitle {
                    targetView.isHidden = (sender.selectedItem?.title != title)
                }
            }
        }

        let cfrHandler = VisibilityHandler(view: cfrCustomContainer, index: 5)
        cfrModePopup.target = cfrHandler
        cfrModePopup.action = #selector(VisibilityHandler.handleChange(_:))

        let levelsHandler = VisibilityHandler(view: levelsCustomContainer, title: "Custom")
        levelsModePopup.target = levelsHandler
        levelsModePopup.action = #selector(VisibilityHandler.handleChange(_:))

        let camHandler = VisibilityHandler(view: camCustomContainer, title: "Custom")
        camModelPopup.target = camHandler
        camModelPopup.action = #selector(VisibilityHandler.handleChange(_:))

        alert.accessoryView = accessoryView

        // --- Response Handling ---
        let response = alert.runModal()

        // Handle cancel (always second button when loadSaved, third button otherwise)
        if loadSaved {
            if response == .alertSecondButtonReturn {
                return nil
            }
        } else {
            if response == .alertThirdButtonReturn {
                return nil
            }
            // Use Defaults button - return default options
            if response == .alertSecondButtonReturn {
                return RenderOptions()
            }
        }

        // Build options from UI state
        var resultOptions = RenderOptions()
        resultOptions.applyVignetteCorrection = vignetteCorrectionCheckbox.state == .on
        resultOptions.normalizeShadingMap = normalizeShadingCheckbox.state == .on
        resultOptions.vignetteOnlyColor = vignetteOnlyColorCheckbox.state == .on

        // CFR
        let selCFR = cfrModePopup.indexOfSelectedItem
        if selCFR > 0 && selCFR != 5 {
            resultOptions.cfrEnabled = true
            let modes: [CFRMode] = [.disabled, .preferInteger, .preferDropFrame, .medianSlowMotion, .averageTesting, .disabled]
            resultOptions.cfrMode = modes[selCFR]
        } else if selCFR == 5 {
            // Custom
            resultOptions.cfrEnabled = true
            let val = cfrCustomField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            resultOptions.cfrCustomValue = (Double(val) != nil) ? val : "24.00"
        }

        // Levels
        if let title = levelsModePopup.selectedItem?.title {
            if title == "Custom" {
                resultOptions.levelsMode = .custom
                resultOptions.levelsCustomValue = levelsCustomField.stringValue
            } else {
                resultOptions.levelsMode = LevelsMode.allCases.first(where: { $0.rawValue == title }) ?? .dynamic
            }
        }

        // Camera
        if let title = camModelPopup.selectedItem?.title {
            if title == "Custom" {
                resultOptions.cameraModel = .custom
                resultOptions.cameraModelCustomValue = camCustomField.stringValue
            } else {
                resultOptions.cameraModel = CameraModel.allCases.first(where: { $0.rawValue == title }) ?? .disabled
            }
        }

        return resultOptions
    }

    // MARK: - Alert Dialogs

    private func showUnmountOptionsAlert() {
        let alert = NSAlert()
        alert.messageText = "No file was opened at launch."
        alert.informativeText = "Would you like to unmount all existing .mcraw mounts and remove /tmp/mcraws?"
        alert.addButton(withTitle: "Unmount All")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task {
                await performUnmountAll()
            }
        default:
            exit(EXIT_FAILURE)
        }
    }

    private func performUnmountAll() async {
        let results = await unmountAllMcraws()
        let failures = results.filter { entry in
            guard let err = entry.error else { return false }
            if let unErr = err as? UnmountError,
               case .nonZeroExit(_, let output) = unErr,
               output.contains("not currently mounted") { return false }
            return true
        }

        let message: String
        if failures.isEmpty {
            message = "✅ Unmounted all \(results.count) mounts successfully."
        } else {
            message = "Unmounted \(results.count - failures.count)/\(results.count) successfully."
        }
        showAlertAndExit(message: message)
    }

    private func showAlertAndExit(message: String) -> Never {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        _ = alert.runModal()
        exit(EXIT_FAILURE)
    }

    private func handleDisabledError(_ mountError: MountError) {
        if case .nonZeroExit(_, let output) = mountError, output.contains("is disabled") {
            let disableAlert = NSAlert()
            disableAlert.messageText = "Please enable the MotionCamFuse filesystem and try again."
            disableAlert.addButton(withTitle: "OK")
            _ = disableAlert.runModal()
            NSWorkspace.shared.open(
              URL(string:
                "x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=com.apple.fskit.fsmodule"
              )!
            )
            exit(EXIT_FAILURE)
        }
    }

    private func showMountOptionsAlert(for fileURL: URL) {
        while true {
            let savedOptions = RenderOptions.load()
            let alert = NSAlert()
            alert.messageText = "Mount Options"
            alert.informativeText = fileURL.lastPathComponent + "\n\nCurrent render options:\n" + savedOptions.descriptionText()
            alert.addButton(withTitle: "Just This File")
            alert.addButton(withTitle: "All Files in Folder")
            alert.addButton(withTitle: "Customize Options")
            alert.addButton(withTitle: "Cancel")

            switch alert.runModal() {
            case .alertFirstButtonReturn:
                let options = RenderOptions.load()
                Task { @MainActor in
                    do {
                        try await mountSingleFile(at: fileURL, with: options)
                        showAlertAndExit(message: "✅ Mounted successfully.")
                    } catch {
                        if let mountError = error as? MountError {
                            handleDisabledError(mountError)
                        }
                        showAlertAndExit(message: "❌ Mount failed: \(error)")
                    }
                }
                return
            case .alertSecondButtonReturn:
                mountAllFiles(in: fileURL.deletingLastPathComponent())
                return
            case .alertThirdButtonReturn:
                if let options = showRenderOptionsDialog(for: fileURL, loadSaved: true) {
                    RenderOptions.save(options)
                    // Loop back to show the alert with updated options
                } else {
                    // User cancelled, exit
                    exit(EXIT_FAILURE)
                }
            default:
                exit(EXIT_FAILURE)
            }
        }
    }

    private func showMultipleFilesAlert(for urls: [URL]) {
        let savedOptions = RenderOptions.load()
        let alert = NSAlert()
        alert.messageText = "Mount \(urls.count) files?"
        alert.informativeText = "Files will be mounted with your saved render options:\n" + savedOptions.descriptionText()
        alert.addButton(withTitle: "Mount")
        alert.addButton(withTitle: "Customize Options")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let options = RenderOptions.load()
            Task { await mountMultipleFiles(urls, with: options) }
        case .alertSecondButtonReturn:
            let options = showRenderOptionsDialog(for: urls[0], loadSaved: true)
            if let options = options {
                RenderOptions.save(options)
                Task { await mountMultipleFiles(urls, with: options) }
            }
        default:
            exit(EXIT_FAILURE)
        }
    }

    // MARK: - File System Operations

    private func ensureDirectoryExists(at path: String) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: path, isDirectory: &isDir) {
            if !isDir.boolValue { throw DirectoryError.fileExistsButIsNotDirectory(path: path) }
        } else {
            try fm.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
        }
    }

    private func volumeMountPoint(for fileURL: URL) throws -> String {
        let containerPath = "/tmp/mcraws"
        let volumePath = containerPath + "/" + fileURL.deletingPathExtension().lastPathComponent
        try ensureDirectoryExists(at: containerPath)
        try ensureDirectoryExists(at: volumePath)
        return volumePath
    }

    // MARK: - Mount Operations (Async)

    private func mountMyFS(fileUrl: URL, at mountPoint: String, options: RenderOptions? = nil) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/mount")
        var arguments: [String] = ["-F", "-t", "mcrawfs"]
        if let options = options {
            let optionsString = options.buildOptionsString()
            if !optionsString.isEmpty {
                arguments.append("-o")
                arguments.append(optionsString)
            }
        }
        arguments.append(fileUrl.path)
        arguments.append(mountPoint)
        process.arguments = arguments

        do {
            _ = try await process.runWithTimeout(commandTimeout(for: fileUrl))
        } catch {
            // Clean up the mount point directory, report any cleanup failure
            do {
                try FileManager.default.removeItem(atPath: mountPoint)
            } catch let cleanupError {
                print("⚠️ Failed to clean up mount point '\(mountPoint)': \(cleanupError)")
            }
            throw error
        }
    }

    private func mountSingleFile(at url: URL, with options: RenderOptions? = nil, showLoading: Bool = true) async throws {
        let loadingSheet = showLoading ? LoadingSheet(message: "Mounting \(url.lastPathComponent)...") : nil
        loadingSheet?.show()

        defer { loadingSheet?.close() }

        let mountPoint = try volumeMountPoint(for: url)
        try await mountMyFS(fileUrl: url, at: mountPoint, options: options)
    }

    private func unmountSingleMountPoint(_ mountPoint: String) async -> (String, Error?) {
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/sbin/umount")
            process.arguments = ["-f", mountPoint]
            _ = try await process.runWithTimeout(2.0)
            return (mountPoint, nil)
        } catch {
            return (mountPoint, error)
        }
    }

    private func unmountAllMcraws() async -> [(mountPoint: String, error: Error?)] {
        let container = "/tmp/mcraws"
        let fm = FileManager.default
        let collector = MountResultsCollector()

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: container, isDirectory: &isDir), isDir.boolValue,
              let subdirs = try? fm.contentsOfDirectory(atPath: container) else {
            return []
        }

        // Use TaskGroup for concurrent unmounting with controlled parallelism
        await withTaskGroup(of: (String, Error?).self) { group in
            var activeTasks = 0
            let maxConcurrentTasks = 10

            for name in subdirs {
                // Limit concurrency
                if activeTasks >= maxConcurrentTasks {
                    if let result = await group.next() {
                        await collector.append(result)
                        activeTasks -= 1
                    }
                }

                let mp = container + "/" + name
                activeTasks += 1
                group.addTask {
                    await self.unmountSingleMountPoint(mp)
                }
            }

            // Collect remaining results
            for await result in group {
                await collector.append(result)
            }
        }

        // Clean up the container directory, report any failure
        do {
            try fm.removeItem(atPath: container)
        } catch let cleanupError {
            print("⚠️ Failed to remove container directory '\(container)': \(cleanupError)")
        }
        return await collector.getAll()
    }

    private func mountMultipleFiles(_ urls: [URL], with options: RenderOptions? = nil) async {
        let mcrawFiles = urls.filter { $0.pathExtension.lowercased() == "mcraw" }
        guard !mcrawFiles.isEmpty else {
            showAlertAndExit(message: "⚠️ No .mcraw files found.")
            return
        }

        let loadingSheet = LoadingSheet(message: "Mounting 1 of \(mcrawFiles.count)...")
        loadingSheet.show()

        defer { loadingSheet.close() }

        let collector = MountResultsCollector()
        var completedCount = 0

        // First file is done synchronously to catch filesystem errors early
        do {
            try await mountSingleFile(at: mcrawFiles[0], with: options, showLoading: false)
            await collector.append((mcrawFiles[0].path, nil))
        } catch {
            if let mountError = error as? MountError {
                handleDisabledError(mountError)
            }
            await collector.append((mcrawFiles[0].path, error))
        }
        completedCount += 1
        loadingSheet.update(message: "Mounting \(completedCount) of \(mcrawFiles.count)...")

        // Use TaskGroup for concurrent mounting with controlled parallelism
        await withTaskGroup(of: (String, Error?).self) { group in
            var activeTasks = 0
            let maxConcurrentTasks = 10

            for file in mcrawFiles.dropFirst() {
                // Limit concurrency
                if activeTasks >= maxConcurrentTasks {
                    if let result = await group.next() {
                        await collector.append(result)
                        activeTasks -= 1
                        completedCount += 1
                        loadingSheet.update(message: "Mounting \(completedCount) of \(mcrawFiles.count)...")
                    }
                }

                activeTasks += 1
                group.addTask {
                    do {
                        try await self.mountSingleFile(at: file, with: options, showLoading: false)
                        return (file.path, nil)
                    } catch {
                        return (file.path, error)
                    }
                }
            }

            // Collect remaining results
            for await result in group {
                await collector.append(result)
                completedCount += 1
                loadingSheet.update(message: "Mounting \(completedCount) of \(mcrawFiles.count)...")
            }
        }

        let results = await collector.getAll()
        let failures = results.filter { $0.1 != nil }
        let successCount = results.count - failures.count

        // Only open folder if at least one mount succeeded
        if successCount > 0 {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/tmp/mcraws"))
        }

        // Bring app to front before showing alert
        NSApp.activate(ignoringOtherApps: true)

        if failures.isEmpty {
            showAlertAndExit(message: "✅ All \(results.count) images mounted successfully.")
        } else {
            showAlertAndExit(message: "Mounted \(successCount)/\(results.count) successfully.")
        }
    }

    private func mountAllFiles(in folderURL: URL) {
        let fm = FileManager.default
        let mcrawFiles: [URL]

        do {
            let items = try fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            mcrawFiles = try items.filter { url in
                let props = try url.resourceValues(forKeys: [.isDirectoryKey])
                return (props.isDirectory == false) && url.pathExtension.lowercased() == "mcraw"
            }
        } catch {
            showAlertAndExit(message: "❌ Error reading folder: \(error)")
            return
        }

        guard !mcrawFiles.isEmpty else {
            showAlertAndExit(message: "⚠️ No .mcraw files found.")
            return
        }

        Task { await mountMultipleFiles(mcrawFiles) }
    }
}
