import Foundation
import FSKit
import os

enum CustomFSKitError: Error {
    case nonZeroExit(status: Int32)
}

final class McrawFS: FSUnaryFileSystem, FSUnaryFileSystemOperations {
    
    private let logger = Logger(subsystem: "McrawMounter", category: "McrawFS")
    
    func probeResource(
        resource: FSResource,
        replyHandler: @escaping (FSProbeResult?, (any Error)?) -> Void
    ) {
        guard let resource = resource as? FSPathURLResource else {
            replyHandler(FSProbeResult.notRecognized, CustomFSKitError.nonZeroExit(status: 1))
            return
        }
        
        let fileName = resource.url.deletingPathExtension().lastPathComponent

        replyHandler(
            FSProbeResult.usable(
                name: fileName,
                containerID: FSContainerIdentifier(uuid: UUID())
            ),
            nil
        )
    }
    
    func loadResource(
        resource: FSResource,
        options: FSTaskOptions,
        replyHandler: @escaping (FSVolume?, (any Error)?) -> Void
    ) {
        guard let resource = resource as? FSPathURLResource else {
            replyHandler(nil, CustomFSKitError.nonZeroExit(status: 2))
            return
        }

        let ok = resource.url.startAccessingSecurityScopedResource()
        guard ok else {
            replyHandler(nil, CustomFSKitError.nonZeroExit(status: 3))
            return
        }

        containerStatus = .ready
        let volume = McrawFSVolume(resource: resource)
        replyHandler(
            volume,
            nil
        )
    }
    
    func unloadResource(
        resource: FSResource,
        options: FSTaskOptions,
        replyHandler reply: @escaping ((any Error)?) -> Void
    ) {
        guard let resource = resource as? FSPathURLResource else {
            reply(CustomFSKitError.nonZeroExit(status: 4))
            return
        }

        resource.url.stopAccessingSecurityScopedResource()
        
        logger.debug("unloadResource: \(resource, privacy: .public)")
        reply(nil)
    }
    
    func didFinishLoading() {
        logger.debug("didFinishLoading")
    }
}
