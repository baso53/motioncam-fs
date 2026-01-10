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

enum LogTransformMode: String, CaseIterable {
    case disabled = ""
    case keepInput = "KeepInput"
    case reduceBy2Bit = "ReduceBy2Bit"
    case reduceBy4Bit = "ReduceBy4Bit"
    case reduceBy6Bit = "ReduceBy6Bit"
    case reduceBy8Bit = "ReduceBy8Bit"
}

enum QuadBayerMode: String, CaseIterable {
    case remosaic = "Remosaic"
    case wrongCFAMetadata = "WrongCFAMetadata"
    case correctQBCFAMetadata = "CorrectQBCFAMetadata"
}

@main
struct MotionCamExplorerApp: App {
    // flag to detect if we ever got an Open-File event
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene { }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var didOpenFile = false
    // timeout for all external commands
    private let commandTimeout: TimeInterval = 15

    // MARK: - Render Options
    struct RenderOptions {
        var cfrTarget: CFRMode = .preferDropFrame
        var cameraModel: String = "Panasonic"
        var levels: String = "Dynamic"
        var logTransform: LogTransformMode = .keepInput
        var exposureCompensation: String = "0ev"
        var quadBayerOption: QuadBayerMode = .remosaic

        // Boolean options
        var applyVignetteCorrection: Bool = true
        var normalizeShadingMap: Bool = true
        var vignetteOnlyColor: Bool = false
        var normalizeExposure: Bool = false
        var framerateConversion: Bool = false
        var camModelOverride: Bool = false
        var logTransformOption: Bool = false
        var interpretAsQuadBayer: Bool = false

        func buildOptionsString() -> String {
            var options: [String] = []

            if applyVignetteCorrection {
                options.append("vignette_correction")
            }

            if normalizeShadingMap {
                options.append("normalize_shading_map")
            }

            if vignetteOnlyColor {
                options.append("vignette_only_color")
            }

            if normalizeExposure {
                options.append("normalize_exposure")
            }

            if framerateConversion {
                options.append("cfr=\(cfrTarget.rawValue)")
            }

            if camModelOverride && !cameraModel.isEmpty {
                options.append("camera_model=\(cameraModel)")
            }

            if !levels.isEmpty {
                options.append("levels=\(levels)")
            }

            if logTransformOption {
                options.append("log_transform=\(logTransform.rawValue)")
            }

            if !exposureCompensation.isEmpty {
                options.append("exposure=\(exposureCompensation)")
            }

            if interpretAsQuadBayer {
                options.append("quad_bayer=\(quadBayerOption.rawValue)")
            }

            return options.joined(separator: ",")
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !didOpenFile {
            showUnmountOptionsAlert()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard !urls.isEmpty else { return }
        didOpenFile = true

        if urls.count == 1 {
            // Single file - show the existing options alert
            showMountOptionsAlert(for: urls[0])
        } else {
            // Multiple files - show a confirmation alert
            showMultipleFilesAlert(for: urls)
        }
    }

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
                // If it’s a non‐zero exit and the output contains “not currently mounted”,
                // don’t count it as a failure.
                if let unErr = err as? UnmountError,
                   case .nonZeroExit(_, let output) = unErr,
                   output.contains("not currently mounted") {
                    return false
                }
                return true
            }

            if failures.isEmpty {
                showAlertAndExit(
                  message: "✅ Unmounted all \(results.count) mounts successfully."
                )
            } else {
                let maxLen = 1000
                var msg = "Unmounted \(results.count - failures.count)/\(results.count) successfully.\n\nFailures:\n"
                for (mp, err) in failures {
                    if msg.count > maxLen {
                        msg += "..."
                        break
                    }
                    msg += "\(mp): \(err!)\n"
                }
                showAlertAndExit(message: msg)
            }

        default:
            exit(EXIT_FAILURE)
        }
    }

    // reuse your MountError for capturing non-zero exit if you like:
    enum UnmountError: Error, CustomStringConvertible {
        case nonZeroExit(status: Int32, output: String)
        case timeout(timeout: TimeInterval)

        var description: String {
            switch self {
            case .nonZeroExit(let s, let out):
                return "umount failed (exit \(s)): \(out)"
            case .timeout(let t):
                return "umount timed out after \(t) seconds"
            }
        }
    }

    private func unmountAllMcraws() -> [(mountPoint: String, error: Error?)] {
        let container = "/tmp/mcraws"
        let fm = FileManager.default
        var results = [(mountPoint: String, error: Error?)]()
        let resultsLock = NSLock()
        let group = DispatchGroup()

        // throttle to 10 concurrent unmounts
        let semaphore = DispatchSemaphore(value: 10)

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: container, isDirectory: &isDir), isDir.boolValue,
              let subdirs = try? fm.contentsOfDirectory(atPath: container)
        else {
            // nothing to do
            return results
        }

        for name in subdirs {
            let mp = container + "/" + name
            group.enter()
            semaphore.wait()                  // <-- wait for an available “slot”
            DispatchQueue.global().async {
                defer {
                    semaphore.signal()        // <-- release slot
                    group.leave()
                }

                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/sbin/umount")
                proc.arguments = ["-f", mp]

                let outPipe = Pipe()
                proc.standardOutput = outPipe
                proc.standardError  = outPipe

                var errorOccurred: Error?
                do {
                    try proc.run()
                    let start = Date()
                    while proc.isRunning && Date().timeIntervalSince(start) < self.commandTimeout {
                        Thread.sleep(forTimeInterval: 0.1)
                    }
                    if proc.isRunning {
                        proc.terminate()
                        proc.waitUntilExit()
                        errorOccurred = UnmountError.timeout(timeout: self.commandTimeout)
                    } else if proc.terminationStatus != 0 {
                        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                        let str  = String(data: data, encoding: .utf8) ?? ""
                        errorOccurred = UnmountError.nonZeroExit(status: proc.terminationStatus, output: str)
                    }
                } catch {
                    errorOccurred = error
                }

                resultsLock.lock()
                results.append((mountPoint: mp, error: errorOccurred))
                resultsLock.unlock()
            }
        }

        group.wait()

        // Finally remove the container folder
        do {
            try fm.removeItem(atPath: container)
        } catch {
            results.append((mountPoint: container, error: error))
        }

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
        if case .nonZeroExit(_, let output) = mountError,
           output.contains("is disabled") {
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
        let alert = NSAlert()
        alert.messageText = "Do you want to mount just this file or all the files in this folder?"
        alert.informativeText = fileURL.lastPathComponent
        alert.addButton(withTitle: "Just This File")
        alert.addButton(withTitle: "All Files in this Folder")
        alert.addButton(withTitle: "Mount with Options")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            do {
                try mountSingleFile(at: fileURL)
                showAlertAndExit(message: "✅ \(fileURL.lastPathComponent) mounted successfully.")
            } catch {
                if let mountError = error as? MountError {
                    handleDisabledError(mountError)
                }
                showAlertAndExit(message: "❌ \(error)")
            }

        case .alertSecondButtonReturn:
            mountAllFiles(in: fileURL.deletingLastPathComponent())

        case .alertThirdButtonReturn:
            let options = showRenderOptionsDialog()
            do {
                try mountSingleFile(at: fileURL, with: options)
                showAlertAndExit(message: "✅ \(fileURL.lastPathComponent) mounted successfully with custom options.")
            } catch {
                if let mountError = error as? MountError {
                    handleDisabledError(mountError)
                }
                showAlertAndExit(message: "❌ \(error)")
            }

        default:
            exit(EXIT_FAILURE)
        }
    }

    private func showRenderOptionsDialog() -> RenderOptions {
        var options = RenderOptions()

        let alert = NSAlert()
        alert.messageText = "Render Options"
        alert.informativeText = "Configure render settings for mounting"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Use Defaults")

        // Create the accessory view
        let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 490))

        // Boolean options
        let vignetteCorrectionCheckbox = NSButton(checkboxWithTitle: "Apply Vignette Correction", target: nil, action: nil)
        vignetteCorrectionCheckbox.frame = NSRect(x: 20, y: 460, width: 180, height: 18)
        vignetteCorrectionCheckbox.state = .on
        accessoryView.addSubview(vignetteCorrectionCheckbox)

        let normalizeShadingCheckbox = NSButton(checkboxWithTitle: "Normalize Shading Map", target: nil, action: nil)
        normalizeShadingCheckbox.frame = NSRect(x: 20, y: 435, width: 180, height: 18)
        normalizeShadingCheckbox.state = .on
        accessoryView.addSubview(normalizeShadingCheckbox)

        let vignetteOnlyColorCheckbox = NSButton(checkboxWithTitle: "Vignette Only Color", target: nil, action: nil)
        vignetteOnlyColorCheckbox.frame = NSRect(x: 20, y: 410, width: 180, height: 18)
        accessoryView.addSubview(vignetteOnlyColorCheckbox)

        let normalizeExposureCheckbox = NSButton(checkboxWithTitle: "Normalize Exposure", target: nil, action: nil)
        normalizeExposureCheckbox.frame = NSRect(x: 20, y: 385, width: 180, height: 18)
        accessoryView.addSubview(normalizeExposureCheckbox)

        let framerateConversionCheckbox = NSButton(checkboxWithTitle: "Framerate Conversion", target: nil, action: nil)
        framerateConversionCheckbox.frame = NSRect(x: 20, y: 360, width: 180, height: 18)
        accessoryView.addSubview(framerateConversionCheckbox)

        let camModelOverrideCheckbox = NSButton(checkboxWithTitle: "Override Camera Model", target: nil, action: nil)
        camModelOverrideCheckbox.frame = NSRect(x: 20, y: 330, width: 180, height: 18)
        accessoryView.addSubview(camModelOverrideCheckbox)

        let camModelField = NSTextField(frame: NSRect(x: 210, y: 328, width: 100, height: 22))
        camModelField.stringValue = "Panasonic"
        accessoryView.addSubview(camModelField)

        let logTransformCheckbox = NSButton(checkboxWithTitle: "Log Transform", target: nil, action: nil)
        logTransformCheckbox.frame = NSRect(x: 20, y: 300, width: 120, height: 18)
        accessoryView.addSubview(logTransformCheckbox)

        let logTransformPopup = NSPopUpButton(frame: NSRect(x: 140, y: 300, width: 150, height: 24))
        logTransformPopup.addItems(withTitles: LogTransformMode.allCases.map { mode in
            switch mode {
            case .disabled: return "Disabled"
            case .keepInput: return "Keep Input"
            case .reduceBy2Bit: return "Reduce by 2bit"
            case .reduceBy4Bit: return "Reduce by 4bit"
            case .reduceBy6Bit: return "Reduce by 6bit"
            case .reduceBy8Bit: return "Reduce by 8bit"
            }
        })
        logTransformPopup.selectItem(at: 1)
        accessoryView.addSubview(logTransformPopup)

        let exposureLabel = NSTextField(labelWithString: "Exposure Compensation:")
        exposureLabel.frame = NSRect(x: 20, y: 270, width: 160, height: 20)
        accessoryView.addSubview(exposureLabel)

        let exposureField = NSTextField(frame: NSRect(x: 180, y: 268, width: 80, height: 22))
        exposureField.stringValue = "0ev"
        accessoryView.addSubview(exposureField)

        let levelsLabel = NSTextField(labelWithString: "Levels:")
        levelsLabel.frame = NSRect(x: 20, y: 240, width: 80, height: 20)
        accessoryView.addSubview(levelsLabel)

        let levelsField = NSTextField(frame: NSRect(x: 100, y: 238, width: 100, height: 22))
        levelsField.stringValue = "Dynamic"
        accessoryView.addSubview(levelsField)

        let quadBayerCheckbox = NSButton(checkboxWithTitle: "Interpret as Quad Bayer", target: nil, action: nil)
        quadBayerCheckbox.frame = NSRect(x: 20, y: 210, width: 180, height: 18)
        accessoryView.addSubview(quadBayerCheckbox)

        let quadBayerPopup = NSPopUpButton(frame: NSRect(x: 210, y: 208, width: 150, height: 24))
        quadBayerPopup.addItems(withTitles: QuadBayerMode.allCases.map { mode in
            switch mode {
            case .remosaic: return "Remosaic"
            case .wrongCFAMetadata: return "Wrong CFA Metadata"
            case .correctQBCFAMetadata: return "Correct QBCFA Metadata"
            }
        })
        quadBayerPopup.selectItem(at: 0)
        accessoryView.addSubview(quadBayerPopup)

        let cfrLabel = NSTextField(labelWithString: "CFR Target:")
        cfrLabel.frame = NSRect(x: 20, y: 180, width: 80, height: 20)
        accessoryView.addSubview(cfrLabel)

        let cfrPopup = NSPopUpButton(frame: NSRect(x: 100, y: 178, width: 180, height: 24))
        cfrPopup.addItems(withTitles: CFRMode.allCases.map { mode in
            switch mode {
            case .disabled: return "Disabled"
            case .preferInteger: return "Prefer Integer"
            case .preferDropFrame: return "Prefer Drop Frame"
            case .medianSlowMotion: return "Median (Slowmotion)"
            case .averageTesting: return "Average (Testing)"
            }
        })
        cfrPopup.selectItem(at: 2)
        accessoryView.addSubview(cfrPopup)

        alert.accessoryView = accessoryView

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            // Collect options
            options.applyVignetteCorrection = vignetteCorrectionCheckbox.state == .on
            options.normalizeShadingMap = normalizeShadingCheckbox.state == .on
            options.vignetteOnlyColor = vignetteOnlyColorCheckbox.state == .on
            options.normalizeExposure = normalizeExposureCheckbox.state == .on
            options.framerateConversion = framerateConversionCheckbox.state == .on

            // Map selected title to enum
            if let selectedTitle = cfrPopup.selectedItem?.title {
                switch selectedTitle {
                case "Disabled": options.cfrTarget = .disabled
                case "Prefer Integer": options.cfrTarget = .preferInteger
                case "Prefer Drop Frame": options.cfrTarget = .preferDropFrame
                case "Median (Slowmotion)": options.cfrTarget = .medianSlowMotion
                case "Average (Testing)": options.cfrTarget = .averageTesting
                default: options.cfrTarget = .preferDropFrame
                }
            }

            options.camModelOverride = camModelOverrideCheckbox.state == .on
            options.cameraModel = camModelField.stringValue

            options.logTransformOption = logTransformCheckbox.state == .on
            // Map selected title to enum
            if let selectedTitle = logTransformPopup.selectedItem?.title {
                switch selectedTitle {
                case "Disabled": options.logTransform = .disabled
                case "Keep Input": options.logTransform = .keepInput
                case "Reduce by 2bit": options.logTransform = .reduceBy2Bit
                case "Reduce by 4bit": options.logTransform = .reduceBy4Bit
                case "Reduce by 6bit": options.logTransform = .reduceBy6Bit
                case "Reduce by 8bit": options.logTransform = .reduceBy8Bit
                default: options.logTransform = .keepInput
                }
            }

            options.exposureCompensation = exposureField.stringValue
            options.levels = levelsField.stringValue

            options.interpretAsQuadBayer = quadBayerCheckbox.state == .on
            // Map selected title to enum
            if let selectedTitle = quadBayerPopup.selectedItem?.title {
                switch selectedTitle {
                case "Remosaic": options.quadBayerOption = .remosaic
                case "Wrong CFA Metadata": options.quadBayerOption = .wrongCFAMetadata
                case "Correct QBCFA Metadata": options.quadBayerOption = .correctQBCFAMetadata
                default: options.quadBayerOption = .remosaic
                }
            }
        }

        return options
    }

  enum DirectoryError: Error, CustomStringConvertible {
        case fileExistsButIsNotDirectory(path: String)

        var description: String {
            switch self {
            case .fileExistsButIsNotDirectory(let p):
                return "Expected a directory at \(p), but found a file."
            }
        }
    }

    private func ensureDirectoryExists(at path: String) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false

        if fm.fileExists(atPath: path, isDirectory: &isDir) {
            if !isDir.boolValue {
                throw DirectoryError.fileExistsButIsNotDirectory(path: path)
            }
        } else {
            try fm.createDirectory(atPath: path,
                                   withIntermediateDirectories: true,
                                   attributes: nil)
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
            case .nonZeroExit(let status, let output):
                return "Mount failed (exit \(status)): \(output)"
            case .timeout(let t):
                return "mount timed out after \(t) seconds"
            }
        }
    }

    private func mountMyFS(fileUrl: URL, at mountPoint: String, options: RenderOptions? = nil) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/mount")

        var arguments: [String] = ["-F", "-t", "mcrawfs"]

        // Add options if provided
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

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError  = pipe

        try process.run()
        // wait with timeout
        let start = Date()
        while process.isRunning && Date().timeIntervalSince(start) < commandTimeout {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
            // Delete the mount point folder if mount times out
            try? FileManager.default.removeItem(atPath: mountPoint)
            throw MountError.timeout(timeout: commandTimeout)
        }

        let data   = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            // Delete the mount point folder if mount fails
            try? FileManager.default.removeItem(atPath: mountPoint)
            throw MountError.nonZeroExit(status: process.terminationStatus, output: output)
        }
    }

    private func mountSingleFile(at url: URL) throws {
        let mountPoint = try volumeMountPoint(for: url)
        try mountMyFS(fileUrl: url, at: mountPoint)
    }

    private func mountSingleFile(at url: URL, with options: RenderOptions) throws {
        let mountPoint = try volumeMountPoint(for: url)
        try mountMyFS(fileUrl: url, at: mountPoint, options: options)
    }

    private func showMultipleFilesAlert(for urls: [URL]) {
        let alert = NSAlert()
        alert.messageText = "Do you want to mount all \(urls.count) selected files?"
        alert.informativeText = "Selected files will be mounted with default settings."
        alert.addButton(withTitle: "Mount All")
        alert.addButton(withTitle: "Mount with Options")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            // Mount all with default settings
            mountMultipleFiles(urls)

        case .alertSecondButtonReturn:
            // Mount with custom options
            let options = showRenderOptionsDialog()
            mountMultipleFiles(urls, with: options)

        default:
            exit(EXIT_FAILURE)
        }
    }

    private func mountMultipleFiles(_ urls: [URL], with options: RenderOptions? = nil) {
        // Filter for .mcraw files
        let mcrawFiles = urls.filter { $0.pathExtension.lowercased() == "mcraw" }

        guard !mcrawFiles.isEmpty else {
            showAlertAndExit(message: "⚠️ No .mcraw files found in selection.")
        }

        let fm = FileManager.default
        var results = [(file: URL, error: Error?)]()
        let resultsLock = NSLock()
        let group = DispatchGroup()

        // throttle to 10 concurrent mounts
        let semaphore = DispatchSemaphore(value: 10)

        // Mount the first file to catch a disabled‐fs error early
        do {
            if let options = options {
                try mountSingleFile(at: mcrawFiles[0], with: options)
            } else {
                try mountSingleFile(at: mcrawFiles[0])
            }
            resultsLock.lock()
            results.append((mcrawFiles[0], nil))
            resultsLock.unlock()
        } catch {
            if let mountError = error as? MountError {
                handleDisabledError(mountError)
            }
            resultsLock.lock()
            results.append((mcrawFiles[0], error))
            resultsLock.unlock()
        }

        // Launch each mount in parallel for the remaining files, max 10 at once
        for file in mcrawFiles.dropFirst() {
            group.enter()
            semaphore.wait()                    // <-- throttle
            DispatchQueue.global().async {
                defer {
                    semaphore.signal()          // <-- release
                    group.leave()
                }

                do {
                    if let options = options {
                        try self.mountSingleFile(at: file, with: options)
                    } else {
                        try self.mountSingleFile(at: file)
                    }
                    resultsLock.lock()
                    results.append((file, nil))
                    resultsLock.unlock()
                } catch {
                    resultsLock.lock()
                    results.append((file, error))
                    resultsLock.unlock()
                }
            }
        }

        group.wait()

        // Summarize on the main thread
        let failures = results.filter { $0.error != nil }
        if failures.isEmpty {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/tmp/mcraws"))
            showAlertAndExit(message: "✅ All \(results.count) images mounted successfully.")
        } else {
            let mountedSuccessfully = results.count - failures.count
            if mountedSuccessfully > 0 {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/tmp/mcraws"))
            }
            let maxLen = 1000
            var msg = "Mounted \(mountedSuccessfully)/\(results.count) successfully.\n\nFailures:\n"
            for (file, err) in failures {
                let entry = "\(file.lastPathComponent): \(err!)\n"
                if msg.count + entry.count > maxLen {
                    msg += "..."
                    break
                }
                msg += entry
            }
            showAlertAndExit(message: msg)
        }
    }

    private func mountAllFiles(in folderURL: URL) {
        let fm = FileManager.default

        // 1) Gather .mcraw files
        let mcrawFiles: [URL]
        do {
            let items = try fm.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            mcrawFiles = try items.filter { url in
                let props = try url.resourceValues(forKeys: [.isDirectoryKey])
                return (props.isDirectory == false) && url.pathExtension.lowercased() == "mcraw"
            }
        } catch {
            showAlertAndExit(message: "❌ Error reading folder: \(error)")
        }

        guard !mcrawFiles.isEmpty else {
            showAlertAndExit(message: "⚠️ No .mcraw files found in \(folderURL.path)")
        }

        mountMultipleFiles(mcrawFiles)
    }
}
