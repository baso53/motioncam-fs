cmake_minimum_required(VERSION 3.26)

if(APPLE)
    set(CMAKE_OSX_DEPLOYMENT_TARGET "26.0")
endif()

project(MotionCamFuse VERSION 1.0 LANGUAGES CXX Swift)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(APP_NAME "MotionCam Fuse")
set(DEPENDENCIES_PATH deps)

if ("${CMAKE_GENERATOR}" MATCHES "Xcode")
  set(CMAKE_CONFIGURATION_TYPES "Release" CACHE STRING
      "Available build configurations" FORCE)
endif()

set(PROJECT_SOURCES
        src/VirtualFileSystemImpl_MCRAW.cpp
        src/CameraMetadata.cpp
        src/CameraFrameMetadata.cpp
        src/AudioWriter.cpp
        src/Utils.cpp

        include/Types.h
        include/IVirtualFileSystem.h
        include/IFuseFileSystem.h
        include/VirtualFileSystemImpl_MCRAW.h
        include/AudioWriter.h
        include/CameraMetadata.h
        include/CameraFrameMetadata.h
        include/Utils.h

        src/macos/McrawFrame.swift
        src/macos/McrawFS.swift
        src/macos/McrawFSVolume.swift
        src/macos/McrawMounterExtension.swift
        src/macos/McrawRootItem.swift
)

set(CMAKE_AUTOUIC_SEARCH_PATHS ui)

add_executable(${PROJECT_NAME}
    ${PROJECT_SOURCES}
)

target_include_directories(${PROJECT_NAME} PRIVATE include)

target_compile_definitions(${PROJECT_NAME} PRIVATE _FILE_OFFSET_BITS=64 FUSE_USE_VERSION=26)

# # Debug configuration with sanitizers
# if(CMAKE_BUILD_TYPE STREQUAL "Debug")
#     target_compile_options(${PROJECT_NAME} PRIVATE
#         -fsanitize=address,undefined
#         -fsanitize-address-use-after-scope
#         -fno-sanitize-recover=all
#         -fstack-protector-strong
#         -g
#         -O0
#         -fno-omit-frame-pointer  # Better stack traces
#     )

#     target_link_options(${PROJECT_NAME} PRIVATE
#       -fsanitize=address,undefined
#       -fsanitize-address-use-after-scope
#       -fno-sanitize-recover=all
#       -fstack-protector-strong
#     )
# endif()

# Instead, compile the decoder sources right into the fuse target:
target_sources(${PROJECT_NAME} PRIVATE
    ${DEPENDENCIES_PATH}/motioncam-decoder/lib/Decoder.cpp
    ${DEPENDENCIES_PATH}/motioncam-decoder/lib/RawData.cpp
    ${DEPENDENCIES_PATH}/motioncam-decoder/lib/RawData_Legacy.cpp
)
target_include_directories(${PROJECT_NAME} PRIVATE
    ${DEPENDENCIES_PATH}/bw64/include
    ${DEPENDENCIES_PATH}/motioncam-decoder/thirdparty
    ${DEPENDENCIES_PATH}/motioncam-decoder/lib/include
)
target_link_libraries(${PROJECT_NAME} PRIVATE ${platform-specific})

set_target_properties(${PROJECT_NAME} PROPERTIES
    BUNDLE_EXTENSION "appex"
    XCODE_ATTRIBUTE_WRAPPER_EXTENSION "appex"

    # point at your custom Info.plist (which must include an NSExtension dictionary)
    MACOSX_BUNDLE TRUE
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/src/macos/Info.plist"

    # Xcode-specific: mark as an ExtensionKit extension
    XCODE_PRODUCT_TYPE "com.apple.product-type.extensionkit-extension"

    XCODE_ATTRIBUTE_CODE_SIGN_ENTITLEMENTS "${CMAKE_CURRENT_SOURCE_DIR}/src/macos/McrawMounterExtension.entitlements"
    XCODE_ATTRIBUTE_GENERATE_INFOPLIST_FILE YES
    XCODE_ATTRIBUTE_SWIFT_VERSION 6
    XCODE_ATTRIBUTE_SWIFT_OBJC_INTEROP_MODE "objcxx"
    XCODE_ATTRIBUTE_SWIFT_DISABLE_SAFETY_CHECKS YES
    XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "hr.leadtheway.motioncamexplorer.extension"
    XCODE_ATTRIBUTE_GCC_OPTIMIZATION_LEVEL 3
    XCODE_ATTRIBUTE_LLVM_LTO YES
    XCODE_ATTRIBUTE_ENABLE_HARDENED_RUNTIME YES
    XCODE_ATTRIBUTE_OTHER_CODE_SIGN_FLAGS "--timestamp"
    XCODE_ATTRIBUTE_CODE_SIGN_INJECT_BASE_ENTITLEMENTS NO
    XCODE_ATTRIBUTE_DEAD_CODE_STRIPPING YES
    XCODE_ATTRIBUTE_ENABLE_APP_SANDBOX YES
    XCODE_ATTRIBUTE_GCC_INLINES_ARE_PRIVATE_EXTERN YES
)

set_source_files_properties(${MACOS_BUNDLE_ICON_FILE} PROPERTIES
    MACOSX_PACKAGE_LOCATION "Resources"
)

include(GNUInstallDirs)
install(TARGETS ${PROJECT_NAME}
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

# Add MotionCamExplorer target (empty macOS app for embedding)
add_executable(MotionCamExplorer MACOSX_BUNDLE
    src/macos/client/MotionCamExplorer.swift
)

set_target_properties(MotionCamExplorer PROPERTIES
    # point at your custom Info.plist (which must include an NSExtension dictionary)
    MACOSX_BUNDLE TRUE
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/src/macos/client/Info.plist"

    XCODE_ATTRIBUTE_GENERATE_INFOPLIST_FILE YES
    XCODE_ATTRIBUTE_SWIFT_VERSION 6
    XCODE_ATTRIBUTE_SWIFT_DISABLE_SAFETY_CHECKS YES
    XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "hr.leadtheway.motioncamexplorer"
    XCODE_ATTRIBUTE_GCC_OPTIMIZATION_LEVEL 3
    XCODE_ATTRIBUTE_LLVM_LTO YES
    XCODE_EMBED_EXTENSIONKIT_EXTENSIONS "${PROJECT_NAME}"
    XCODE_ATTRIBUTE_ENABLE_HARDENED_RUNTIME YES
    XCODE_ATTRIBUTE_OTHER_CODE_SIGN_FLAGS "--timestamp"
    XCODE_ATTRIBUTE_CODE_SIGN_INJECT_BASE_ENTITLEMENTS NO
)
if(QT_VERSION_MAJOR EQUAL 6)
    qt_finalize_executable(${PROJECT_NAME})
    
    # Deploy Qt dependencies using Qt's deployment tool
    if(WIN32)
        # Get Qt installation directory
        get_target_property(QT_QMAKE_EXECUTABLE Qt6::qmake IMPORTED_LOCATION)
        get_filename_component(QT_BIN_DIR "${QT_QMAKE_EXECUTABLE}" DIRECTORY)
        
        # Use windeployqt to copy all required Qt dependencies
        add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
            COMMAND "${QT_BIN_DIR}/windeployqt.exe"
                --debug
                --no-translations
                --no-system-d3d-compiler
                --no-opengl-sw
                --no-compiler-runtime
                --verbose 2
                $<TARGET_FILE:${PROJECT_NAME}>
        )
        add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
            COMMAND "${QT_BIN_DIR}/windeployqt.exe"
                --no-translations
                --no-system-d3d-compiler
                --no-opengl-sw
                --no-compiler-runtime
                --verbose 2
                $<TARGET_FILE:${PROJECT_NAME}>
        )       # add both release and debug qt dlls because im lazy
    endif()
endif()
