import Foundation
import Sebo

struct MountResult {
    let success: Bool
    let mountId: Int
    let mountPoint: String
    let error: String?
}

class MotionCamWrapper {
    private var fs: Sebo.motioncam.FuseFileSystemImpl_MacOs

    init() {
        self.fs = Sebo.motioncam.FuseFileSystemImpl_MacOs()
    }

    func mountFile(path: String, settings: motioncam.RenderSettings? = nil) -> MountResult {
        // Use default settings if none provided
        let renderSettings = settings ?? getDefaultRenderSettings()

        // Get the cache root path from UserDefaults or use the source file directory
        let defaults = UserDefaults.standard
        let cacheRoot = defaults.string(forKey: "MotionCamRenderSettings_cacheFolder") ?? ""
        let dstPath: String

        if cacheRoot.isEmpty {
            // Use same directory as source file
            let url = URL(fileURLWithPath: path)
            dstPath = url.deletingLastPathComponent().appendingPathComponent(url.deletingPathExtension().lastPathComponent).path
        } else {
            // Use configured cache folder
            let fileName = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            dstPath = URL(fileURLWithPath: cacheRoot).appendingPathComponent(fileName).path
        }

        let mountId = fs.mount(renderSettings, std.string(path), std.string(dstPath))

        if mountId != -1 {
            return MountResult(
                success: true,
                mountId: Int(mountId),
                mountPoint: dstPath,
                error: nil
            )
        } else {
            return MountResult(
                success: false,
                mountId: -1,
                mountPoint: "",
                error: "Failed to mount file"
            )
        }
    }

    func unmountFile(mountId: Int) -> Bool {
        fs.unmount(Int32(mountId))
        return true
    }

    func updateOptions(mountId: Int, settings: motioncam.RenderSettings) -> Bool {
        fs.updateOptions(Int32(mountId), settings)
        return true
    }

    func getFileInfo(mountId: Int) -> motioncam.FileInfo? {
        return fs.getFileInfo(Int32(mountId)).hasValue ? fs.getFileInfo(Int32(mountId)).value : nil
    }

    
    private func getDefaultRenderSettings() -> motioncam.RenderSettings {
        // Match the Qt defaults
        var options: UInt32 = motioncam.RENDER_OPT_APPLY_VIGNETTE_CORRECTION.rawValue
        options |= motioncam.RENDER_OPT_VIGNETTE_ONLY_COLOR.rawValue
        options |= motioncam.RENDER_OPT_NORMALIZE_EXPOSURE.rawValue
        options |= motioncam.RENDER_OPT_FRAMERATE_CONVERSION.rawValue
        options |= motioncam.RENDER_OPT_CAMMODEL_OVERRIDE.rawValue
        options |= motioncam.RENDER_OPT_LOG_TRANSFORM.rawValue

        let renderOpts = motioncam.FileRenderOptions(rawValue: options) ?? motioncam.RENDER_OPT_NONE

        let cfrTarget = motioncam.CFRTarget()
        let logTransform = motioncam.LogTransformMode.Disabled
        let quadBayerMode = motioncam.QuadBayerMode.WrongCFAMetadata

        return motioncam.RenderSettings(
            renderOpts,
            0,  // Draft quality
            cfrTarget,
            "",  // Crop target
            "Panasonic",
            "Dynamic",
            logTransform,
            "0ev",
            quadBayerMode
        )
    }
}

//// Global functions for direct calls from other Swift files
//func motioncam_mount(_ path: String, _ mountPoint: String, _ settings: motioncam.RenderSettings) -> Int {
//    // Replace with your C++ bridging call
//    return -1 // Placeholder
//}
//
//func motioncam_unmount(_ mountId: Int) -> Bool {
//    // Replace with your C++ bridging call
//    return false // Placeholder
//}
//
//func motioncam_updateOptions(_ mountId: Int, _ settings: motioncam.RenderSettings) -> Bool {
//    // Replace with your C++ bridging call
//    return false // Placeholder
//}
