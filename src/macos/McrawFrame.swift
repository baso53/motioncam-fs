import Foundation
import FSKit
import MotioncamModule

final class McrawFrame: FSItem {

    let name: FSFileName

    let entry: MotioncamModule.motioncam.Entry
    
    let attributes = FSItem.Attributes()
    
    init(entry: MotioncamModule.motioncam.Entry, fileId: UInt64) {
        let name = String(entry.name)
        self.name = FSFileName(string: name)
        self.entry = entry
        attributes.fileID = FSItem.Identifier(rawValue: fileId) ?? .invalid
        attributes.size = UInt64(entry.size)
        attributes.allocSize = UInt64(entry.size)
        attributes.flags = 0
        attributes.mode = UInt32(S_IFREG | 0b111_000_000)

        var timespec = timespec()
        timespec_get(&timespec, TIME_UTC)
        
        attributes.addedTime = timespec
        attributes.birthTime = timespec
        attributes.changeTime = timespec
        attributes.modifyTime = timespec
        attributes.accessTime = timespec
        attributes.type = .file
        
        attributes.parentID = .rootDirectory
        attributes.linkCount = 1
    }
}
