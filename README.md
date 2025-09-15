# MotionCam-FS (FSKit Edition)

A macOS **FSKit** file-system extension that lets you treat native MotionCam **`.mcraw`** files like ordinary disk images.  
Mount any `.mcraw` with a single command, browse its full-resolution DNG frames in Finder, and work with them in your favorite editor—no conversion step required.

```
mount -F -t mcrawfs /path/to/video.mcraw /Volumes/MotionCam
```

---

## Table of Contents
1. 🔧 Features  
2. 📋 Requirements  
3. 🏗️ Building from Source  
4. 📦 Installing the Extension  
5. 🚀 Usage  
6. 👩‍💻 Graphical Companion App  
7. 🛠️ Troubleshooting  
8. 🤝 Contributing  
9. 📄 License

---

## 1. 🔧 Features
* **Native FSKit module** – written against Apple’s new `FSPathURLResource` API (macOS 26+).  
* **Read-only, zero-copy access** to individual DNG frames inside a `.mcraw`.  
* **FUSE-like workflow** but without third-party kernel components—pure user-space.  
* **Command-line or GUI** (via [McrawMounterClient](https://github.com/baso53/McrawMounterClient)).  
* Automatic detection of frame rate, resolution and bit-depth metadata.

---

## 2. 📋 Requirements
* **macOS 26** or later (FSKit with `FSPathURLResource` support).  
* Xcode
* [CMake](https://cmake.org/) ≥ 3.26.  
* [vcpkg](https://github.com/microsoft/vcpkg) for dependency management.

---

## 3. 🏗️ Building from Source

```bash
# Clone
git clone https://github.com/baso53/motioncam-fs
cd motioncam-fs

# Prepare build directory and generate Xcode project
mkdir build && cd build
cmake -G Xcode .. \
  -DCMAKE_TOOLCHAIN_FILE=$HOME/vcpkg/scripts/buildsystems/vcpkg.cmake
```

Open `MotionCamFuse.xcodeproj` and hit **Product ▶︎ Build**, or build directly:

The resulting `.appex` is your extension.

---

## 4. 📦 Installing the Extension

1. Register the app extension with the system:

   ```bash
   pluginkit -a MotionCamFuse.appex
   ```

2. Open System Settings to the **File System Extensions** pane:

   ```bash
   open "x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=com.apple.fskit.fsmodule"
   ```

3. Enable **MotionCamFuse** in the list.  
   You might be prompted to grant Full Disk Access the first time.

---

## 5. 🚀 Usage

### Command-Line

```bash
# Mount a .mcraw
sudo mount -F -t mcrawfs \
    /Users/alice/Videos/007-VIDEO_24mm-240328_141729.0.mcraw \
    /Volumes/007-VIDEO_24mm-240328_141729.0.mcraw

# Work with the files
open /Volumes/007-VIDEO_24mm-240328_141729.0.mcraw/frame_00042.dng

# Unmount when done
umount /Volumes/007-VIDEO_24mm-240328_141729.0.mcraw
```

Tips  
• The mount point must exist and be empty.  
• Only one `.mcraw` per mount invocation is supported.  
• Read-only by design; editing frames in-place is not supported.

---

## 6. 👩‍💻 Graphical Companion App

Prefer point-and-click? [**McrawMounterClient**](https://github.com/baso53/McrawMounterClient).  

---

## 8. 🤝 Contributing

Pull requests and bug reports are welcome!  

```bash
git checkout -b feature/my-awesome-idea
git commit -s -m "Add awesome idea"
git push origin feature/my-awesome-idea
```

---

## 9. 📄 License

Released under the Apache 2.0 License.  

---
