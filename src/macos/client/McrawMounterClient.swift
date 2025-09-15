import SwiftUI
import AppKit

@main
struct McrawMounterClientApp: App {
    // flag to detect if we ever got an Open-File event
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene { }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var didOpenFile = false
    // timeout for all external commands
    private let commandTimeout: TimeInterval = 3

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !didOpenFile {
            showUnmountOptionsAlert()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let first = urls.first else {
            exit(EXIT_FAILURE)
        }
        didOpenFile = true
        showMountOptionsAlert(for: first)
    }

    private func showUnmountOptionsAlert() -> Never {
        let alert = NSAlert()
        alert.messageText = "No file was opened at launch."
        alert.informativeText = "Would you like to unmount all existing .mcraw mounts and remove /tmp/mcraws?"
        alert.addButton(withTitle: "Unmount All")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let results = unmountAllMcraws()
            let failures = results.filter { $0.error != nil }

            if failures.isEmpty {
                showAlertAndExit(
                  message: "✅ Unmounted all \(results.count) mounts successfully.",
                  exitCode: EXIT_SUCCESS
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
            exit(EXIT_SUCCESS)
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

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: container, isDirectory: &isDir), isDir.boolValue,
              let subdirs = try? fm.contentsOfDirectory(atPath: container)
        else {
            // nothing to do
            return results
        }

        for name in subdirs {
            let mp = container + "/" + name
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/sbin/umount")
            proc.arguments = ["-f", mp]

            let outPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError  = outPipe

            var errorOccurred: Error?
            do {
                try proc.run()
                // wait with timeout
                let start = Date()
                while proc.isRunning && Date().timeIntervalSince(start) < commandTimeout {
                    Thread.sleep(forTimeInterval: 0.1)
                }
                if proc.isRunning {
                    proc.terminate()
                    proc.waitUntilExit()
                    errorOccurred = UnmountError.timeout(timeout: commandTimeout)
                } else if proc.terminationStatus != 0 {
                    let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let str  = String(data: data, encoding: .utf8) ?? ""
                    errorOccurred = UnmountError.nonZeroExit(status: proc.terminationStatus, output: str)
                }
            } catch {
                errorOccurred = error
            }

            results.append((mountPoint: mp, error: errorOccurred))
        }

        // Finally remove the container folder
        do {
            try fm.removeItem(atPath: container)
        } catch {
            // treat container‐remove as an overall error, if desired:
            results.append((mountPoint: container, error: error))
        }

        return results
    }

    private func showAlertAndExit(message: String, exitCode: Int32 = EXIT_FAILURE) -> Never {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        _ = alert.runModal()
        exit(exitCode)
    }


    private func showMountOptionsAlert(for fileURL: URL) {
        let alert = NSAlert()
        alert.messageText = "Do you want to mount just this file or all the files in this folder?"
        alert.informativeText = fileURL.lastPathComponent
        alert.addButton(withTitle: "Just This File")
        alert.addButton(withTitle: "All Files in this Folder")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            do {
                try mountSingleFile(at: fileURL)
                showAlertAndExit(message: "✅ \(fileURL.lastPathComponent) mounted successfully.", exitCode: EXIT_SUCCESS)
            } catch {
                showAlertAndExit(message: "❌ \(error)")
            }

        case .alertSecondButtonReturn:
            mountAllFiles(in: fileURL.deletingLastPathComponent())

        default:
            NSApp.terminate(nil)
        }
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

    private func mountMyFS(fileUrl: URL, at mountPoint: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/mount")
        process.arguments = ["-F", "-t", "mcrawfs3", fileUrl.path, mountPoint]

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
            throw MountError.timeout(timeout: commandTimeout)
        }

        let data   = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw MountError.nonZeroExit(status: process.terminationStatus, output: output)
        }
    }

    private func mountSingleFile(at url: URL) throws {
        let mountPoint = try volumeMountPoint(for: url)
        try mountMyFS(fileUrl: url, at: mountPoint)
    }

    private func mountAllFiles(in folderURL: URL) {
        let fm = FileManager.default
        var results = [(file: URL, error: Error?)]()

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

        // 2) Try each mount, collect errors
        for file in mcrawFiles {
            do {
                try mountSingleFile(at: file)
                results.append((file, nil))
            } catch {
                results.append((file, error))
            }
        }

        // 3) Summarize
        let failures = results.filter { $0.error != nil }
        if failures.isEmpty {
            showAlertAndExit(message: "✅ All \(results.count) images mounted successfully.", exitCode: EXIT_SUCCESS)
        } else {
            let maxLen = 1000
            var msg = "Mounted \(results.count-failures.count)/\(results.count) successfully.\n\nFailures:\n"
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
}
