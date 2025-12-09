#pragma once

#include <map>
#include <memory>
#include "LRUCache.h"

#include "IFuseFileSystem.h"

namespace motioncam {

struct Session;

class FuseFileSystemImpl_MacOs
{
public:
    FuseFileSystemImpl_MacOs();

    MountId mount(
        const RenderSettings& settings,
        const std::string& srcFile,
        const std::string& dstPath);

    void unmount(MountId mountId);
    void updateOptions(
        MountId mountId,
        const RenderSettings& settings);
    std::optional<FileInfo> getFileInfo(MountId mountId);

private:
    MountId mNextMountId;
    std::map<MountId, std::shared_ptr<Session>> mMountedFiles;
    std::unique_ptr<LRUCache> mCache;
};

} // namespace motioncam
