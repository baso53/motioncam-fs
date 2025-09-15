import Foundation
import FSKit
import os

final class McrawFS: FSUnaryFileSystem, FSUnaryFileSystemOperations {
    
    private let logger = Logger(subsystem: "McrawMounter", category: "McrawFS")
    
    func probeResource(
        resource: FSResource,
        replyHandler: @escaping (FSProbeResult?, (any Error)?) -> Void
    ) {
        guard let resource = resource as? FSPathURLResource else {
            exit(EXIT_FAILURE)
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
            exit(EXIT_FAILURE)
        }

        let ok = resource.url.startAccessingSecurityScopedResource()
        guard ok else { exit(EXIT_FAILURE) }

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
            exit(EXIT_FAILURE)
        }

        resource.url.stopAccessingSecurityScopedResource()
        
        logger.debug("unloadResource: \(resource, privacy: .public)")
        reply(nil)
    }
    
    func didFinishLoading() {
        logger.debug("didFinishLoading")
    }
}
