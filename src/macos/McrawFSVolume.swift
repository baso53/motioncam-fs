import Foundation
import FSKit
import os
import MotioncamModule

final class McrawFSVolume: FSVolume {

    private let resource: FSPathURLResource
    private var options: FSTaskOptions?
    private let filePath: std.string
    private var renderSettings: motioncam.RenderSettings?

    private let logger = Logger(subsystem: "McrawMounter", category: "McrawFSVolume")

    private let root: McrawRootItem

    private var rootFileSystem: MotioncamModule.motioncam.VirtualFileSystemImpl_MCRAW?

    private let readQueue = DispatchQueue(label: "McrawFSVolume.readQueue", qos: .userInitiated)

    private var periodicTimer: DispatchSourceTimer?

    // Helper functions to convert enum values to display strings
    private func convertCFREnumToString(_ enumValue: String) -> String {
        switch enumValue {
        case "PreferInteger": return "Prefer Integer"
        case "PreferDropFrame": return "Prefer Drop Frame"
        case "MedianSlowMotion": return "Median (Slowmotion)"
        case "AverageTesting": return "Average (Testing)"
        case "Disabled": return ""
        default: return "Prefer Drop Frame"
        }
    }

    private func convertLogTransformEnumToString(_ enumValue: String) -> String {
        switch enumValue {
        case "KeepInput": return "Keep Input"
        case "ReduceBy2Bit": return "Reduce by 2bit"
        case "ReduceBy4Bit": return "Reduce by 4bit"
        case "ReduceBy6Bit": return "Reduce by 6bit"
        case "ReduceBy8Bit": return "Reduce by 8bit"
        case "": return ""
        default: return "Keep Input"
        }
    }

    private func convertQuadBayerEnumToString(_ enumValue: String) -> String {
        switch enumValue {
        case "WrongCFAMetadata": return "Wrong CFA Metadata"
        case "CorrectQBCFAMetadata": return "Correct QBCFA Metadata"
        default: return "Remosaic"
        }
    }

    init(resource: FSPathURLResource) {
        let fileName = resource.url.deletingPathExtension().lastPathComponent

        let filePath = std.string(resource.url.path)
        self.filePath = filePath

        self.resource = resource
        let rootItem = McrawRootItem(name: FSFileName(string: fileName))
        root = rootItem

        super.init(
            volumeID: FSVolume.Identifier(uuid: UUID()),
            volumeName: FSFileName(string: fileName)
        )
    }
    
    deinit {
        periodicTimer?.cancel()
        periodicTimer = nil
    }
}

extension McrawFSVolume: FSVolume.PathConfOperations {

    var maximumLinkCount: Int {
        return 100000
    }

    var maximumNameLength: Int {
        return 150
    }

    var restrictsOwnershipChanges: Bool {
        return true
    }

    var truncatesLongNames: Bool {
        return false
    }

    var maximumXattrSize: Int {
        return 0
    }

    var maximumFileSize: UInt64 {
        return UInt64.max
    }
}

extension McrawFSVolume: FSVolume.Operations {

    var supportedVolumeCapabilities: FSVolume.SupportedCapabilities {
        let capabilities = FSVolume.SupportedCapabilities()
        capabilities.supportsHardLinks = false
        capabilities.supportsSymbolicLinks = false
        capabilities.supportsPersistentObjectIDs = true
        capabilities.doesNotSupportVolumeSizes = true
        capabilities.supportsHiddenFiles = false
        capabilities.supports64BitObjectIDs = true
        capabilities.caseFormat = .insensitiveCasePreserving
        return capabilities
    }

    var volumeStatistics: FSStatFSResult {
        let result = FSStatFSResult(fileSystemTypeName: "McrawFS")

        result.blockSize = 1024000
        result.ioSize = 1024000
        result.totalBlocks = 1024000
        result.availableBlocks = 1024000
        result.freeBlocks = 0
        result.totalFiles = 100000
        result.freeFiles = 0

        return result
    }


    func activate(options: FSTaskOptions) async throws -> FSItem {
        self.options = options
        let taskOptions = options.taskOptions

        // Parse render settings from taskOptions
        var renderOptions: motioncam.FileRenderOptions = motioncam.RENDER_OPT_NONE
        var draftScale: Int32 = 1
        var cfrTarget = "PreferDropFrame"  // Changed from "Prefer Drop Frame" to enum value
        var cropTarget = ""
        var cameraModel = "Panasonic"
        var levels = "Dynamic"
        var logTransform = "KeepInput"  // Changed from "Keep Input" to enum value
        var exposureCompensation = "0ev"
        var quadBayerOption = "Remosaic"

        // Parse taskOptions array
        var i = 0
        while i < taskOptions.count {
            if taskOptions[i] == "-o" && i + 1 < taskOptions.count {
                let optionString = taskOptions[i + 1]
                let options = optionString.split(separator: ",")

                for option in options {
                    let optionStr = String(option)
                    if optionStr == "vignette_correction" {
                        renderOptions = renderOptions |  motioncam.RENDER_OPT_APPLY_VIGNETTE_CORRECTION
                    } else if optionStr == "normalize_shading_map" {
                        renderOptions = renderOptions |  motioncam.RENDER_OPT_NORMALIZE_SHADING_MAP
                    } else if optionStr == "debug_shading_map" {
                        renderOptions = renderOptions |  motioncam.RENDER_OPT_DEBUG_SHADING_MAP
                    } else if optionStr == "vignette_only_color" {
                        renderOptions = renderOptions |  motioncam.RENDER_OPT_VIGNETTE_ONLY_COLOR
                    } else if optionStr == "normalize_exposure" {
                        renderOptions = renderOptions |  motioncam.RENDER_OPT_NORMALIZE_EXPOSURE
                    } else if optionStr.hasPrefix("draft=") {
                        let value = optionStr.dropFirst(6)
                        draftScale = Int32(value) ?? 1
                        renderOptions = renderOptions |  motioncam.RENDER_OPT_DRAFT
                    } else if optionStr.hasPrefix("cfr=") {
                        cfrTarget = String(optionStr.dropFirst(4))
                        renderOptions = renderOptions |  motioncam.RENDER_OPT_FRAMERATE_CONVERSION
                    } else if optionStr.hasPrefix("crop=") {
                        cropTarget = String(optionStr.dropFirst(5))
                        if !cropTarget.isEmpty {
                            renderOptions = renderOptions |  motioncam.RENDER_OPT_CROPPING
                        }
                    } else if optionStr.hasPrefix("camera_model=") {
                        cameraModel = String(optionStr.dropFirst(13))
                        if !cameraModel.isEmpty {
                            renderOptions = renderOptions |  motioncam.RENDER_OPT_CAMMODEL_OVERRIDE
                        }
                    } else if optionStr.hasPrefix("levels=") {
                        levels = String(optionStr.dropFirst(7))
                    } else if optionStr.hasPrefix("log_transform=") {
                        logTransform = String(optionStr.dropFirst(14))
                        renderOptions = renderOptions |  motioncam.RENDER_OPT_LOG_TRANSFORM
                    } else if optionStr.hasPrefix("exposure=") {
                        exposureCompensation = String(optionStr.dropFirst(9))
                    } else if optionStr.hasPrefix("quad_bayer=") {
                        quadBayerOption = String(optionStr.dropFirst(11))
                        renderOptions = renderOptions |  motioncam.RENDER_OPT_INTERPRET_AS_QUAD_BAYER
                    }
                }
                i += 2
            } else {
                i += 1
            }
        }

        // Create render settings with converted enum values
        let renderSettings = motioncam.RenderSettings(
            renderOptions,
            draftScale,
            std.string(convertCFREnumToString(cfrTarget)),
            std.string(cropTarget),
            std.string(cameraModel),
            std.string(levels),
            std.string(convertLogTransformEnumToString(logTransform)),
            std.string(exposureCompensation),
            std.string(convertQuadBayerEnumToString(quadBayerOption))
        )
        
        self.renderSettings = renderSettings

        self.rootFileSystem = MotioncamModule.motioncam.VirtualFileSystemImpl_MCRAW(filePath)

        // Update the file system with parsed render settings
        self.rootFileSystem?.updateOptions(renderSettings)

        var j: UInt64 = 1
        rootFileSystem?.listFiles("").forEach({ entry in
            root.addItem(McrawFrame(entry: entry, fileId: j))
            j += 1
        })
        
        root.attributes.linkCount = UInt32(root.children.count)
        
        periodicTimer = DispatchSource.makeTimerSource(queue: .global())

        periodicTimer?.schedule(deadline: .now() + .seconds(10), repeating: .seconds(10), leeway: .seconds(2))
        periodicTimer?.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.rootFileSystem?.clearCache()
        }
        periodicTimer?.resume()

        return root
    }

    func deactivate(options: FSDeactivateOptions = []) async throws {
    }

    func mount(options: FSTaskOptions) async throws {
    }

    func unmount() async {
    }

    func synchronize(flags: FSSyncFlags) async throws {
    }

    func attributes(
        _ desiredAttributes: FSItem.GetAttributesRequest,
        of item: FSItem
    ) async throws -> FSItem.Attributes {
        if let item = item as? McrawFrame {
            return item.attributes
        } else if let item = item as? McrawRootItem {
            return item.attributes
        } else {
            throw fs_errorForPOSIXError(POSIXError.EIO.rawValue)
        }
    }

   func setAttributes(
       _ newAttributes: FSItem.SetAttributesRequest,
       on item: FSItem
   ) async throws -> FSItem.Attributes {
       if let item = item as? McrawFrame {
           return item.attributes
       } else {
           throw fs_errorForPOSIXError(POSIXError.EIO.rawValue)
       }
   }

    func lookupItem(
        named name: FSFileName,
        inDirectory directory: FSItem
    ) async throws -> (FSItem, FSFileName) {
        guard let directory = directory as? McrawRootItem else {
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }

        for (key, child) in directory.children {
            if key.string == name.string {
                return (child, key)
            }
        }

        throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
    }

    func reclaimItem(_ item: FSItem) async throws {
        throw fs_errorForPOSIXError(POSIXError.EIO.rawValue)
    }

    func readSymbolicLink(
        _ item: FSItem
    ) async throws -> FSFileName {
        throw fs_errorForPOSIXError(POSIXError.EIO.rawValue)
    }

    func createItem(
        named name: FSFileName,
        type: FSItem.ItemType,
        inDirectory directory: FSItem,
        attributes newAttributes: FSItem.SetAttributesRequest
    ) async throws -> (FSItem, FSFileName) {
        throw fs_errorForPOSIXError(POSIXError.EIO.rawValue)
    }

    func createSymbolicLink(
        named name: FSFileName,
        inDirectory directory: FSItem,
        attributes newAttributes: FSItem.SetAttributesRequest,
        linkContents contents: FSFileName
    ) async throws -> (FSItem, FSFileName) {
        throw fs_errorForPOSIXError(POSIXError.EIO.rawValue)
    }

    func createLink(
        to item: FSItem,
        named name: FSFileName,
        inDirectory directory: FSItem
    ) async throws -> FSFileName {
        throw fs_errorForPOSIXError(POSIXError.EIO.rawValue)
    }

    func removeItem(
        _ item: FSItem,
        named name: FSFileName,
        fromDirectory directory: FSItem
    ) async throws {
        throw fs_errorForPOSIXError(POSIXError.EIO.rawValue)
    }

    func renameItem(
        _ item: FSItem,
        inDirectory sourceDirectory: FSItem,
        named sourceName: FSFileName,
        to destinationName: FSFileName,
        inDirectory destinationDirectory: FSItem,
        overItem: FSItem?
    ) async throws -> FSFileName {
        throw fs_errorForPOSIXError(POSIXError.EIO.rawValue)
    }

    func enumerateDirectory(
        _ directory: FSItem,
        startingAt cookie: FSDirectoryCookie,
        verifier: FSDirectoryVerifier,
        attributes: FSItem.GetAttributesRequest?,
        packer: FSDirectoryEntryPacker
    ) async throws -> FSDirectoryVerifier {
        guard let directory = directory as? McrawRootItem else {
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }

        let startIndex = Int(cookie.rawValue)         // `initial` == 0
        guard startIndex <= directory.children.count else {
            throw fs_errorForPOSIXError(POSIXError.EIO.rawValue)
        }
        
        for slot in startIndex..<directory.sortedChildNames.count {
            let name = directory.sortedChildNames[slot]
            let item = directory.children[name]!
            packer.packEntry(
                name:       name,
                itemType:   item.attributes.type,
                itemID:     item.attributes.fileID,
                nextCookie: FSDirectoryCookie(UInt64(slot + 1)),
                attributes: attributes != nil ? item.attributes : nil
            )
        }

        return FSDirectoryVerifier(1)
    }
}

extension McrawFSVolume: FSVolume.ReadWriteOperations {
    
    func read(
        from item: FSItem,
        at offset: off_t,
        length: Int,
        into buffer: FSMutableFileDataBuffer
    ) async throws -> Int {
        let opt = self.renderSettings
        // dispatch the entire read work onto our single serial queue
        if let item = item as? McrawFrame {
            return await withCheckedContinuation { continuation in
                readQueue.async {
                    var bytesRead: Int = 0
                    buffer.withUnsafeMutableBytes { dst in
                        bytesRead = Int(
                            self.rootFileSystem?.readFile(
                                item.entry,
                                Int(offset),
                                Int(length),
                                dst.baseAddress!,
                                motioncam.EMPTY_CALLBACK,
                                false
                            ) ?? 0
                        )
                    }
                    continuation.resume(returning: bytesRead)
                }
            }
        }
        return 0
    }
    
    func write(contents: Data, to item: FSItem, at offset: off_t) async throws -> Int {
        throw fs_errorForPOSIXError(POSIXError.EIO.rawValue)
    }
}
