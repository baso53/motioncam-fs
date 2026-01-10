import SwiftUI
import AppKit

// Enum definitions matching Types.h
enum CFRMode: String, CaseIterable {
    case disabled = "Disabled"
    case preferInteger = "PreferInteger"
    case preferDropFrame = "PreferDropFrame"
    case medianSlowMotion = "MedianSlowMotion"
    case averageTesting = "AverageTesting"
}

enum LevelsMode: String, CaseIterable {
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

enum CameraModel: String, CaseIterable {
    case disabled = "Disabled"
    case panasonic = "Panasonic"
    case blackmagic = "Blackmagic"
    case fujifilm = "Fujifilm"
    case custom = "Custom"
}

@main
struct MotionCamExplorerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene { }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var didOpenFile = false
    private let commandTimeout: TimeInterval = 2

    // MARK: - Render Options
    struct RenderOptions {
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
    private func showRenderOptionsDialog(for fileURL: URL) -> RenderOptions? {
        var options = RenderOptions()

        let alert = NSAlert()
        alert.messageText = "Render Options"
        alert.informativeText = "Configure render settings for mounting."
        alert.addButton(withTitle: "Mount")
        alert.addButton(withTitle: "Use Defaults")
        alert.addButton(withTitle: "Cancel")

        // Compact height: 340 (was 540)
        let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 340))

        // --- 1. Top Section: Checkboxes (Processing) ---
        // Top-down logic: Start Y at 310

        let vignetteCorrectionCheckbox = NSButton(checkboxWithTitle: "Enable Vignette Correction", target: nil, action: nil)
        vignetteCorrectionCheckbox.frame = NSRect(x: 20, y: 310, width: 250, height: 18)
        vignetteCorrectionCheckbox.state = .on
        accessoryView.addSubview(vignetteCorrectionCheckbox)

        // Nested options (Indented, positioned tighter)
        let normalizeShadingCheckbox = NSButton(checkboxWithTitle: "Scale data (normalize shading map)", target: nil, action: nil)
        normalizeShadingCheckbox.frame = NSRect(x: 45, y: 285, width: 280, height: 18)
        normalizeShadingCheckbox.state = .on
        accessoryView.addSubview(normalizeShadingCheckbox)

        let vignetteOnlyColorCheckbox = NSButton(checkboxWithTitle: "Color correction only", target: nil, action: nil)
        vignetteOnlyColorCheckbox.frame = NSRect(x: 45, y: 263, width: 200, height: 18)
        accessoryView.addSubview(vignetteOnlyColorCheckbox)

        // Handler for nesting logic
        class VignetteHandler: NSObject {
            let sub1: NSButton, sub2: NSButton
            init(s1: NSButton, s2: NSButton) { self.sub1 = s1; self.sub2 = s2 }
            @objc func handleChange(_ sender: NSButton) {
                let on = (sender.state == .on)
                sub1.isEnabled = on; sub2.isEnabled = on
                // Optional: Reduce opacity to visually indicate disabled state
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

        // --- 2. CFR Section (Y: 160) ---
        let cfrGroup = createGroup(y: 160, title: "Constant Frame Rate (CFR)")
        accessoryView.addSubview(cfrGroup)

        let cfrModePopup = NSPopUpButton(frame: NSRect(x: 10, y: 5, width: 200, height: 26))
        cfrModePopup.addItems(withTitles: ["Disabled", "Prefer Integer", "Prefer Drop Frame", "Median (Slow Motion)", "Average (Testing)", "Custom"])
        cfrModePopup.selectItem(at: 0)
        cfrGroup.addSubview(cfrModePopup)

        // Custom FPS - Placed to the RIGHT of popup
        let cfrCustomContainer = NSView(frame: NSRect(x: 220, y: 5, width: 200, height: 30))
        cfrCustomContainer.isHidden = true
        cfrGroup.addSubview(cfrCustomContainer)

        let cfrCustomLabel = NSTextField(labelWithString: "FPS:")
        cfrCustomLabel.frame = NSRect(x: 0, y: 7, width: 35, height: 16)
        cfrCustomContainer.addSubview(cfrCustomLabel)

        let cfrCustomField = NSTextField(frame: NSRect(x: 35, y: 4, width: 60, height: 21))
        cfrCustomField.stringValue = "24.00"
        cfrCustomField.placeholderString = "24.00"
        cfrCustomContainer.addSubview(cfrCustomField)
        
        let cfrHint = NSTextField(labelWithString: "(e.g., 23.976)")
        cfrHint.font = NSFont.systemFont(ofSize: 10); cfrHint.textColor = .tertiaryLabelColor
        cfrHint.frame = NSRect(x: 100, y: 7, width: 100, height: 14)
        cfrCustomContainer.addSubview(cfrHint)

        // --- 3. Levels Section (Y: 90) ---
        let levelsGroup = createGroup(y: 90, title: "White Level / Black Level")
        accessoryView.addSubview(levelsGroup)

        let levelsModePopup = NSPopUpButton(frame: NSRect(x: 10, y: 5, width: 200, height: 26))
        levelsModePopup.addItems(withTitles: LevelsMode.allCases.map { $0.rawValue })
        levelsModePopup.selectItem(withTitle: "Dynamic")
        levelsGroup.addSubview(levelsModePopup)

        let levelsCustomContainer = NSView(frame: NSRect(x: 220, y: 5, width: 240, height: 30))
        levelsCustomContainer.isHidden = true
        levelsGroup.addSubview(levelsCustomContainer)
        
        let levelsCustomField = NSTextField(frame: NSRect(x: 0, y: 4, width: 100, height: 21))
        levelsCustomField.placeholderString = "16383/1024"
        levelsCustomField.stringValue = "16383/1024"
        levelsCustomContainer.addSubview(levelsCustomField)

        // --- 4. Camera Model Section (Y: 20) ---
        let camGroup = createGroup(y: 20, title: "Override Camera Model")
        accessoryView.addSubview(camGroup)

        let camModelPopup = NSPopUpButton(frame: NSRect(x: 10, y: 5, width: 140, height: 26))
        camModelPopup.addItems(withTitles: CameraModel.allCases.map { $0.rawValue })
        camModelPopup.selectItem(withTitle: "Disabled")
        camGroup.addSubview(camModelPopup)

        let camCustomContainer = NSView(frame: NSRect(x: 160, y: 5, width: 300, height: 30))
        camCustomContainer.isHidden = true
        camGroup.addSubview(camCustomContainer)

        let camCustomField = NSTextField(frame: NSRect(x: 0, y: 4, width: 150, height: 21))
        camCustomField.placeholderString = "e.g., Sony, Canon"
        camCustomContainer.addSubview(camCustomField)

        // --- Visibility Handlers ---
        class VisibilityHandler: NSObject {
            let targetView: NSView
            let triggerIndex: Int?       // Use index (for CFR)
            let triggerTitle: String?    // Or use title (for others)
            
            init(view: NSView, index: Int? = nil, title: String? = nil) {
                self.targetView = view; self.triggerIndex = index; self.triggerTitle = title
            }
            @objc func handleChange(_ sender: NSPopUpButton) {
                if let idx = triggerIndex { targetView.isHidden = (sender.indexOfSelectedItem != idx) }
                else if let title = triggerTitle { targetView.isHidden = (sender.selectedItem?.title != title) }
            }
        }

        let cfrHandler = VisibilityHandler(view: cfrCustomContainer, index: 5)
        cfrModePopup.target = cfrHandler; cfrModePopup.action = #selector(VisibilityHandler.handleChange(_:))

        let levelsHandler = VisibilityHandler(view: levelsCustomContainer, title: "Custom")
        levelsModePopup.target = levelsHandler; levelsModePopup.action = #selector(VisibilityHandler.handleChange(_:))

        let camHandler = VisibilityHandler(view: camCustomContainer, title: "Custom")
        camModelPopup.target = camHandler; camModelPopup.action = #selector(VisibilityHandler.handleChange(_:))

        alert.accessoryView = accessoryView

        // --- Response Handling ---
        let response = alert.runModal()
        if response == .alertThirdButtonReturn {
            // Cancel - go back to mount options
            return nil
        }
        if response == .alertFirstButtonReturn {
            options.applyVignetteCorrection = vignetteCorrectionCheckbox.state == .on
            options.normalizeShadingMap = normalizeShadingCheckbox.state == .on
            options.vignetteOnlyColor = vignetteOnlyColorCheckbox.state == .on

            // CFR
            let selCFR = cfrModePopup.indexOfSelectedItem
            if selCFR > 0 {
                options.cfrEnabled = true
                if selCFR == 5 { // Custom
                     let val = cfrCustomField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                     options.cfrCustomValue = (Double(val) != nil) ? val : "24.00"
                } else {
                    let modes: [CFRMode] = [.disabled, .preferInteger, .preferDropFrame, .medianSlowMotion, .averageTesting, .disabled]
                    options.cfrMode = modes[selCFR]
                }
            }

            // Levels
            if let title = levelsModePopup.selectedItem?.title {
                if title == "Custom" {
                    options.levelsMode = .custom
                    options.levelsCustomValue = levelsCustomField.stringValue
                } else {
                    options.levelsMode = LevelsMode.allCases.first(where: { $0.rawValue == title }) ?? .dynamic
                }
            }

            // Camera
            if let title = camModelPopup.selectedItem?.title {
                if title == "Custom" {
                    options.cameraModel = .custom
                    options.cameraModelCustomValue = camCustomField.stringValue
                } else {
                    options.cameraModel = CameraModel.allCases.first(where: { $0.rawValue == title }) ?? .disabled
                }
            }
        }
        return options
    }

    private func showRenderOptionsDialogLoop(for fileURL: URL) {
        while true {
            if let options = showRenderOptionsDialog(for: fileURL) {
                try? mountSingleFile(at: fileURL, with: options)
                showAlertAndExit(message: "✅ Mounted with custom options.")
            } else {
                // User cancelled - go back to mount options
                showMountOptionsAlert(for: fileURL)
                return
            }
        }
    }

    // MARK: - Rest of the File (Unchanged Logic)
    private func showUnmountOptionsAlert() {
        let alert = NSAlert()
        alert.messageText = "No file was opened at launch."
        alert.informativeText = "Would you like to unmount all existing .mcraw mounts and remove /tmp/mcraws?"
        alert.addButton(withTitle: "Unmount All")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let results = unmountAllMcraws()
            let failures = results.filter { entry in
                guard let err = entry.error else { return false }
                if let unErr = err as? UnmountError,
                   case .nonZeroExit(_, let output) = unErr,
                   output.contains("not currently mounted") { return false }
                return true
            }
            if failures.isEmpty {
                showAlertAndExit(message: "✅ Unmounted all \(results.count) mounts successfully.")
            } else {
                showAlertAndExit(message: "Unmounted \(results.count - failures.count)/\(results.count) successfully.")
            }
        default: exit(EXIT_FAILURE)
        }
    }

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

    private func unmountAllMcraws() -> [(mountPoint: String, error: Error?)] {
        let container = "/tmp/mcraws"
        let fm = FileManager.default
        var results = [(mountPoint: String, error: Error?)]()
        let resultsLock = NSLock()
        let group = DispatchGroup()
        let semaphore = DispatchSemaphore(value: 10)

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: container, isDirectory: &isDir), isDir.boolValue,
              let subdirs = try? fm.contentsOfDirectory(atPath: container) else { return results }

        for name in subdirs {
            let mp = container + "/" + name
            group.enter()
            semaphore.wait()
            DispatchQueue.global().async {
                defer { semaphore.signal(); group.leave() }
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/sbin/umount")
                proc.arguments = ["-f", mp]
                let outPipe = Pipe()
                proc.standardOutput = outPipe; proc.standardError = outPipe
                
                var errorOccurred: Error?
                do {
                    try proc.run()
                    let start = Date()
                    while proc.isRunning && Date().timeIntervalSince(start) < self.commandTimeout {
                        Thread.sleep(forTimeInterval: 0.1)
                    }
                    if proc.isRunning {
                        proc.terminate(); proc.waitUntilExit()
                        errorOccurred = UnmountError.timeout(timeout: self.commandTimeout)
                    } else if proc.terminationStatus != 0 {
                        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                        errorOccurred = UnmountError.nonZeroExit(status: proc.terminationStatus, output: String(data: data, encoding: .utf8) ?? "")
                    }
                } catch { errorOccurred = error }

                resultsLock.lock()
                results.append((mountPoint: mp, error: errorOccurred))
                resultsLock.unlock()
            }
        }
        group.wait()
        try? fm.removeItem(atPath: container)
        return results
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
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=com.apple.fskit.fsmodule")!)
            exit(EXIT_FAILURE)
        }
    }

    private func showMountOptionsAlert(for fileURL: URL) {
        let alert = NSAlert()
        alert.messageText = "Mount Options"
        alert.informativeText = fileURL.lastPathComponent
        alert.addButton(withTitle: "Just This File")
        alert.addButton(withTitle: "All Files in Folder")
        alert.addButton(withTitle: "Mount with Options")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            try? mountSingleFile(at: fileURL)
            showAlertAndExit(message: "✅ Mounted successfully.")
        case .alertSecondButtonReturn:
            mountAllFiles(in: fileURL.deletingLastPathComponent())
        case .alertThirdButtonReturn:
            showRenderOptionsDialogLoop(for: fileURL)
        default: exit(EXIT_FAILURE)
        }
    }

    enum DirectoryError: Error { case fileExistsButIsNotDirectory(path: String) }

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

    private func mountMyFS(fileUrl: URL, at mountPoint: String, options: RenderOptions? = nil) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/mount")
        var arguments: [String] = ["-F", "-t", "mcrawfs"]
        if let options = options {
            let optionsString = options.buildOptionsString()
            if !optionsString.isEmpty { arguments.append("-o"); arguments.append(optionsString) }
        }
        arguments.append(fileUrl.path)
        arguments.append(mountPoint)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe; process.standardError = pipe

        try process.run()
        let start = Date()
        while process.isRunning && Date().timeIntervalSince(start) < commandTimeout { Thread.sleep(forTimeInterval: 0.1) }
        
        if process.isRunning {
            process.terminate(); process.waitUntilExit()
            try? FileManager.default.removeItem(atPath: mountPoint)
            throw MountError.timeout(timeout: commandTimeout)
        }
        if process.terminationStatus != 0 {
            try? FileManager.default.removeItem(atPath: mountPoint)
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            throw MountError.nonZeroExit(status: process.terminationStatus, output: String(data: data, encoding: .utf8) ?? "")
        }
    }

    private func mountSingleFile(at url: URL, with options: RenderOptions? = nil) throws {
        let mountPoint = try volumeMountPoint(for: url)
        try mountMyFS(fileUrl: url, at: mountPoint, options: options)
    }

    private func showMultipleFilesAlert(for urls: [URL]) {
        let alert = NSAlert()
        alert.messageText = "Mount \(urls.count) files?"
        alert.informativeText = "Selected files will be mounted with default settings."
        alert.addButton(withTitle: "Mount")
        alert.addButton(withTitle: "Mount with Options")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: mountMultipleFiles(urls)
        case .alertSecondButtonReturn:
            // Use first file as reference for options dialog
            let options = showRenderOptionsDialog(for: urls[0])
            if let options = options {
                mountMultipleFiles(urls, with: options)
            }
        default: exit(EXIT_FAILURE)
        }
    }

    private func mountMultipleFiles(_ urls: [URL], with options: RenderOptions? = nil) {
        let mcrawFiles = urls.filter { $0.pathExtension.lowercased() == "mcraw" }
        guard !mcrawFiles.isEmpty else { showAlertAndExit(message: "⚠️ No .mcraw files found.") }

        var results = [(file: URL, error: Error?)]()
        let resultsLock = NSLock()
        let group = DispatchGroup()
        let semaphore = DispatchSemaphore(value: 10)

        // First one synchronous to catch file system errors
        do {
            try mountSingleFile(at: mcrawFiles[0], with: options)
            results.append((mcrawFiles[0], nil))
        } catch {
            if let mountError = error as? MountError { handleDisabledError(mountError) }
            results.append((mcrawFiles[0], error))
        }

        for file in mcrawFiles.dropFirst() {
            group.enter()
            semaphore.wait()
            DispatchQueue.global().async {
                defer { semaphore.signal(); group.leave() }
                do {
                    try self.mountSingleFile(at: file, with: options)
                    resultsLock.lock(); results.append((file, nil)); resultsLock.unlock()
                } catch {
                    resultsLock.lock(); results.append((file, error)); resultsLock.unlock()
                }
            }
        }
        group.wait()

        let failures = results.filter { $0.error != nil }
        if failures.isEmpty {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/tmp/mcraws"))
            showAlertAndExit(message: "✅ All \(results.count) images mounted successfully.")
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/tmp/mcraws"))
            showAlertAndExit(message: "Mounted \(results.count - failures.count)/\(results.count) successfully.")
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
        } catch { showAlertAndExit(message: "❌ Error reading folder: \(error)") }
        guard !mcrawFiles.isEmpty else { showAlertAndExit(message: "⚠️ No .mcraw files found.") }
        mountMultipleFiles(mcrawFiles)
    }
}
