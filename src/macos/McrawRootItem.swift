import Foundation
import FSKit

final class McrawRootItem: FSItem {
    
    let name: FSFileName

    var attributes = FSItem.Attributes()
   
    private(set) var children: [FSFileName: McrawFrame] = [:]
    
    private(set) var sortedChildNames: [FSFileName] = []


    init(name: FSFileName) {
        self.name = name

        var timespec = timespec()
        timespec_get(&timespec, TIME_UTC)
        
        attributes.addedTime = timespec
        attributes.birthTime = timespec
        attributes.changeTime = timespec
        attributes.modifyTime = timespec
        attributes.accessTime = timespec

        attributes.parentID = .parentOfRoot
        attributes.fileID = .rootDirectory
        attributes.type = .directory
        attributes.mode = UInt32(S_IFDIR | 0b111_000_000)
        attributes.allocSize = 0
        attributes.size = 0
        attributes.flags = 0
    }
    
    func addItem(_ item: McrawFrame) {
        children[item.name] = item
        
        let newName = item.name
        let idx = sortedChildNames.firstIndex {
            $0.string! > newName.string!
        } ?? sortedChildNames.endIndex

        sortedChildNames.insert(newName, at: idx)
    }
}
