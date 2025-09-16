import Foundation
import FSKit
import os
import MotioncamModule

final class McrawFSVolume: FSVolume {
    
    private let resource: FSResource

    private let logger = Logger(subsystem: "McrawMounter", category: "McrawFSVolume")

    private let root: McrawRootItem

    private var rootFileSystem: MotioncamModule.motioncam.VirtualFileSystemImpl_MCRAW

    private let readQueue = DispatchQueue(label: "McrawFSVolume.readQueue", qos: .userInitiated)
    
    private let periodicTimer: DispatchSourceTimer

    init(resource: FSResource) {
        guard let resource = resource as? FSPathURLResource else {
            exit(EXIT_FAILURE)
        }

        let fileName = resource.url.deletingPathExtension().lastPathComponent

        let filePath = std.string(resource.url.path)

        self.resource = resource
        self.rootFileSystem = MotioncamModule.motioncam.VirtualFileSystemImpl_MCRAW(filePath)
        let rootItem = McrawRootItem(name: FSFileName(string: fileName))
        root = rootItem

        var i: UInt64 = 1
        rootFileSystem.listFiles("").forEach({ entry in
            rootItem.addItem(McrawFrame(entry: entry, fileId: i))
            i += 1
        })
        
        root.attributes.linkCount = UInt32(root.children.count)
        
        periodicTimer = DispatchSource.makeTimerSource(queue: .global())

        super.init(
            volumeID: FSVolume.Identifier(uuid: UUID()),
            volumeName: FSFileName(string: fileName)
        )

        periodicTimer.schedule(deadline: .now() + .seconds(10), repeating: .seconds(10), leeway: .seconds(2))
        periodicTimer.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.rootFileSystem.clearCache()
        }
        periodicTimer.resume()
    }
    
    deinit {
        periodicTimer.cancel()
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
        // dispatch the entire read work onto our single serial queue
        if let item = item as? McrawFrame {
            return await withCheckedContinuation { continuation in
                readQueue.async {
                    var bytesRead: Int = 0
                    buffer.withUnsafeMutableBytes { dst in
                        bytesRead = Int(
                            self.rootFileSystem.readFile(
                                item.entry,
                                Int(offset),
                                Int(length),
                                dst.baseAddress!,
                                motioncam.EMPTY_CALLBACK,
                                false
                            )
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
