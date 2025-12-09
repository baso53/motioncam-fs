import SwiftUI
import Foundation
import Sebo

class AppState: ObservableObject {
    @Published var mountedFiles: [MountedFile] = []
    @Published var isLoading: Bool = false
    @Published var cacheFolder: String = ""

    private var motionCamWrapper = MotionCamWrapper()
    private var mountCheckTimer: Timer?

    init() {
        startMountCheckTimer()
    }

    deinit {
        stopMountCheckTimer()
    }

    private func startMountCheckTimer() {
        // Use weak self to prevent retain cycles
        mountCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.checkForUnmountedFiles()
        }
    }

    private func stopMountCheckTimer() {
        mountCheckTimer?.invalidate()
        mountCheckTimer = nil
    }

    private func checkForUnmountedFiles() {
        // Create a copy to avoid modifying the array while iterating
        let currentMountedFiles = mountedFiles
        let now = Date()
        let mountGracePeriod: TimeInterval = 5.0 // 5 seconds grace period after mounting

        for mountedFile in currentMountedFiles {
            // Skip files that were mounted less than 3 seconds ago
            if now.timeIntervalSince(mountedFile.mountTime) < mountGracePeriod {
                continue
            }

            // Check if the mount point still exists and is still a mount
            if !isPathStillMounted(mountedFile.mountPoint) {
                // Remove from the main thread since we're modifying @Published property
                DispatchQueue.main.async { [weak self] in
                    // Delete the mount point folder
                    self?.deleteMountPoint(at: mountedFile.mountPoint)
                    // Remove from mounted files array
                    self?.mountedFiles.removeAll { $0.id == mountedFile.id }
                }
            }
        }
    }

    private func deleteMountPoint(at path: String) {
        do {
            // Check if the path exists before attempting to delete
            if FileManager.default.fileExists(atPath: path) {
                try FileManager.default.removeItem(atPath: path)
                print("Successfully deleted mount point at: \(path)")
            }
        } catch {
            print("Failed to delete mount point at \(path): \(error.localizedDescription)")
        }
    }

    private func isPathStillMounted(_ mountPoint: String) -> Bool {
        var statInfo = stat()
        let result = stat(mountPoint, &statInfo)

        // If stat fails, path doesn't exist
        if result != 0 {
            return false
        }

        // Check if it's a directory
        if statInfo.st_mode & S_IFDIR != S_IFDIR {
            return false
        }

        // Use getmntinfo to check if this path is a mount point
        var mountsPtr: UnsafeMutablePointer<statfs>?
        let mountsCount = getmntinfo(&mountsPtr, MNT_NOWAIT)

        if mountsCount == 0 || mountsPtr == nil {
            return false
        }

        let mountsBuffer = UnsafeBufferPointer<statfs>(
            start: mountsPtr,
            count: Int(mountsCount)
        )

        // Check if any mount matches our mount point
        for mount in mountsBuffer {
            let mountPath = withUnsafePointer(to: mount.f_mntonname) { ptr in
                String(cString: UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self))
            }

            if mountPath == mountPoint {
                return true
            }
        }

        return false
    }

    func showOpenFilePanel(settings: motioncam.RenderSettings? = nil) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK {
            let urls = panel.urls
            if !urls.isEmpty {
                for url in urls {
                    mountFile(at: url.path, settings: settings)
                }
            }
        }
    }

    func mountFile(at path: String, settings: motioncam.RenderSettings? = nil) {
        isLoading = true

        DispatchQueue.global(qos: .background).async {
            let result = self.motionCamWrapper.mountFile(path: path, settings: settings)

            DispatchQueue.main.async {
                self.isLoading = false

                if result.success {
                    var mountedFile = MountedFile(
                        id: result.mountId,
                        path: path,
                        mountPoint: result.mountPoint,
                        mountTime: Date()
                    )

                    // Get file info
                    if let fileInfo = self.motionCamWrapper.getFileInfo(mountId: result.mountId) {
                        mountedFile.fileInfo = fileInfo
                    }

                    self.mountedFiles.append(mountedFile)

                    // Open mount point in Finder
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: result.mountPoint)
                } else {
                    let alert = NSAlert()
                    alert.messageText = "Failed to mount file"
                    alert.informativeText = result.error ?? "Unknown error"
                    alert.alertStyle = .critical
                    alert.runModal()
                }
            }
        }
    }

    func unmountFile(id: Int) {
        guard let index = mountedFiles.firstIndex(where: { $0.id == id }) else { return }

        let mountedFile = mountedFiles[index]
        let success = motionCamWrapper.unmountFile(mountId: mountedFile.id)

        if success {
            mountedFiles.remove(at: index)
        } else {
            let alert = NSAlert()
            alert.messageText = "Failed to unmount file"
            alert.informativeText = "Unable to unmount \(mountedFile.path)"
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    func openMountPoint(_ mountedFile: MountedFile) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: mountedFile.mountPoint)
    }

    func updateSettingsForAllFiles(_ settings: motioncam.RenderSettings) {
        DispatchQueue.global(qos: .background).async {
            for mountedFile in self.mountedFiles {
                self.motionCamWrapper.updateOptions(mountId: mountedFile.id, settings: settings)

                // Update file info
                DispatchQueue.main.async {
                    if let index = self.mountedFiles.firstIndex(where: { $0.id == mountedFile.id }) {
                        self.mountedFiles[index].fileInfo = self.motionCamWrapper.getFileInfo(mountId: mountedFile.id)
                    }
                }
            }
        }
    }
}

struct MountedFile: Identifiable {
    let id: Int
    let path: String
    let mountPoint: String
    var fileInfo: motioncam.FileInfo?
    let mountTime: Date
}
