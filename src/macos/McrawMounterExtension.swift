import Foundation
import FSKit

@main
struct McrawMounterExtension : UnaryFileSystemExtension {
    
    var fileSystem : FSUnaryFileSystem & FSUnaryFileSystemOperations {
        McrawFS()
    }
}
