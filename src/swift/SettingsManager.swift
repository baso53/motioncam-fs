import SwiftUI
import Foundation
import Sebo

class SettingsManager: ObservableObject {
    // Render options
    @Published var draftMode: Bool = false {
        didSet { settingsChanged = true }
    }
    @Published var vignetteCorrection: Bool = false {
        didSet { settingsChanged = true }
    }
    @Published var normalizeExposure: Bool = false {
        didSet { settingsChanged = true }
    }
    @Published var cfrConversion: Bool = false {
        didSet { settingsChanged = true }
    }
    @Published var cropEnable: Bool = false {
        didSet { settingsChanged = true }
    }
    @Published var camModelOverride: Bool = false {
        didSet { settingsChanged = true }
    }
    @Published var logTransform: Bool = false {
        didSet { settingsChanged = true }
    }
    @Published var quadBayer: Bool = false {
        didSet { settingsChanged = true }
    }

    // Additional render options
    @Published var vignetteOnlyColor: Bool = true {
        didSet { settingsChanged = true }
    }
    @Published var scaleRaw: Bool = false {
        didSet { settingsChanged = true }
    }
    @Published var debugVignette: Bool = false {
        didSet { settingsChanged = true }
    }

    // Draft quality
    @Published var draftQuality: Int = 1 {
        didSet { settingsChanged = true }
    }

    // Text fields
    @Published var cfrTarget: String = "24" {
        didSet { settingsChanged = true }
    }
    @Published var cropTarget: String = "" {
        didSet { settingsChanged = true }
    }
    @Published var cameraModel: String = "Panasonic" {
        didSet { settingsChanged = true }
    }
    @Published var levels: String = "Dynamic" {
        didSet { settingsChanged = true }
    }
    @Published var exposureCompensation: String = "0ev" {
        didSet { settingsChanged = true }
    }

    // Picker selections
    @Published var logTransformMode: String = "Disabled" {
        didSet { settingsChanged = true }
    }
    @Published var quadBayerOption: String = "Remosaic" {
        didSet { settingsChanged = true }
    }

    // Cache folder
    @Published var cacheFolder: String = "" {
        didSet { settingsChanged = true }
    }

    @Published var settingsChanged: Bool = false

    private let defaults = UserDefaults.standard
    private let settingsKey = "MotionCamRenderSettings"

    init() {
        // Set default values matching the Qt version
        cfrConversion = true
        normalizeExposure = true
        camModelOverride = true
        vignetteCorrection = true
        vignetteOnlyColor = true
        logTransform = true

        cfrTarget = "Prefer Drop Frame"
        exposureCompensation = "0ev"
        cameraModel = "Panasonic"
        levels = "Dynamic"
        logTransformMode = "Keep Input"
        quadBayerOption = "Wrong CFA Metadata"

        loadSettings()
    }

    func loadSettings() {
        if let data = defaults.data(forKey: settingsKey),
           let settings = try? JSONDecoder().decode([String: AnyCodable].self, from: data) {

            // Load render options
            draftMode = settings["draftMode"]?.boolValue ?? false
            vignetteCorrection = settings["vignetteCorrection"]?.boolValue ?? true
            normalizeExposure = settings["normalizeExposure"]?.boolValue ?? true
            cfrConversion = settings["cfrConversion"]?.boolValue ?? true
            cropEnable = settings["cropEnable"]?.boolValue ?? false
            camModelOverride = settings["camModelOverride"]?.boolValue ?? true
            logTransform = settings["logTransform"]?.boolValue ?? true
            quadBayer = settings["quadBayer"]?.boolValue ?? false

            // Load additional render options
            vignetteOnlyColor = settings["vignetteOnlyColor"]?.boolValue ?? true
            scaleRaw = settings["scaleRaw"]?.boolValue ?? false
            debugVignette = settings["debugVignette"]?.boolValue ?? false

            // Load draft quality
            draftQuality = settings["draftQuality"]?.intValue ?? 1

            // Load text fields
            cfrTarget = settings["cfrTarget"]?.stringValue ?? "Prefer Drop Frame"
            cropTarget = settings["cropTarget"]?.stringValue ?? ""
            cameraModel = settings["cameraModel"]?.stringValue ?? "Panasonic"
            levels = settings["levels"]?.stringValue ?? "Dynamic"
            exposureCompensation = settings["exposureCompensation"]?.stringValue ?? "0ev"

            // Load picker selections
            logTransformMode = settings["logTransformMode"]?.stringValue ?? "Keep Input"
            quadBayerOption = settings["quadBayerOption"]?.stringValue ?? "Wrong CFA Metadata"

            // Load cache folder
            cacheFolder = settings["cacheFolder"]?.stringValue ?? ""
        }
    }

    func saveSettings() {
        guard settingsChanged else { return }

        var settings: [String: AnyCodable] = [:]

        // Save render options
        settings["draftMode"] = AnyCodable(draftMode)
        settings["vignetteCorrection"] = AnyCodable(vignetteCorrection)
        settings["normalizeExposure"] = AnyCodable(normalizeExposure)
        settings["cfrConversion"] = AnyCodable(cfrConversion)
        settings["cropEnable"] = AnyCodable(cropEnable)
        settings["camModelOverride"] = AnyCodable(camModelOverride)
        settings["logTransform"] = AnyCodable(logTransform)
        settings["quadBayer"] = AnyCodable(quadBayer)

        // Save additional render options
        settings["vignetteOnlyColor"] = AnyCodable(vignetteOnlyColor)
        settings["scaleRaw"] = AnyCodable(scaleRaw)
        settings["debugVignette"] = AnyCodable(debugVignette)

        // Save draft quality
        settings["draftQuality"] = AnyCodable(draftQuality)

        // Save text fields
        settings["cfrTarget"] = AnyCodable(cfrTarget)
        settings["cropTarget"] = AnyCodable(cropTarget)
        settings["cameraModel"] = AnyCodable(cameraModel)
        settings["levels"] = AnyCodable(levels)
        settings["exposureCompensation"] = AnyCodable(exposureCompensation)

        // Save picker selections
        settings["logTransformMode"] = AnyCodable(logTransformMode)
        settings["quadBayerOption"] = AnyCodable(quadBayerOption)

        // Save cache folder
        settings["cacheFolder"] = AnyCodable(cacheFolder)

        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: settingsKey)
        }

        settingsChanged = false
    }

    func resetToDefaults() {
        draftMode = false
        vignetteCorrection = true
        normalizeExposure = true
        cfrConversion = true
        cropEnable = false
        camModelOverride = true
        logTransform = true
        quadBayer = false

        // Additional render options
        vignetteOnlyColor = true
        scaleRaw = false
        debugVignette = false

        draftQuality = 1

        cfrTarget = "Prefer Drop Frame"
        cropTarget = ""
        cameraModel = "Panasonic"
        levels = "Dynamic"
        exposureCompensation = "0ev"

        logTransformMode = "Keep Input"
        quadBayerOption = "Wrong CFA Metadata"

        // Don't reset cache folder

        settingsChanged = true
        saveSettings()
    }

    func selectCacheFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.title = "Select Cache Folder"

        if panel.runModal() == .OK, let url = panel.url {
            cacheFolder = url.path
        }
    }

    func getRenderSettings() -> motioncam.RenderSettings {
        var options: UInt32 = motioncam.RENDER_OPT_NONE.rawValue

        if draftMode {
            options |= motioncam.RENDER_OPT_DRAFT.rawValue
        }
        if vignetteCorrection {
            options |= motioncam.RENDER_OPT_APPLY_VIGNETTE_CORRECTION.rawValue
        }
        if vignetteOnlyColor {
            options |= motioncam.RENDER_OPT_VIGNETTE_ONLY_COLOR.rawValue
        }
        if scaleRaw {
            options |= motioncam.RENDER_OPT_NORMALIZE_SHADING_MAP.rawValue
        }
        if debugVignette {
            options |= motioncam.RENDER_OPT_DEBUG_SHADING_MAP.rawValue
        }
        if normalizeExposure {
            options |= motioncam.RENDER_OPT_NORMALIZE_EXPOSURE.rawValue
        }
        if cfrConversion {
            options |= motioncam.RENDER_OPT_FRAMERATE_CONVERSION.rawValue
        }
        if cropEnable {
            options |= motioncam.RENDER_OPT_CROPPING.rawValue
        }
        if camModelOverride {
            options |= motioncam.RENDER_OPT_CAMMODEL_OVERRIDE.rawValue
        }
        if logTransform {
            options |= motioncam.RENDER_OPT_LOG_TRANSFORM.rawValue
        }
        if quadBayer {
            options |= motioncam.RENDER_OPT_INTERPRET_AS_QUAD_BAYER.rawValue
        }

        // Parse CFR target
        let cfrTargetValue = parseCFRTarget(cfrTarget)

        // Parse log transform mode
        let logMode: motioncam.LogTransformMode = {
            switch logTransformMode {
            case "Keep Input": return motioncam.LogTransformMode.KeepInput
            case "Reduce by 2bit": return motioncam.LogTransformMode.ReduceBy2Bit
            case "Reduce by 4bit": return motioncam.LogTransformMode.ReduceBy4Bit
            case "Reduce by 6bit": return motioncam.LogTransformMode.ReduceBy6Bit
            case "Reduce by 8bit": return motioncam.LogTransformMode.ReduceBy8Bit
            default: return motioncam.LogTransformMode.Disabled
            }
        }()

        // Parse quad bayer mode
        let quadMode: motioncam.QuadBayerMode = {
            switch quadBayerOption {
            case "Remosaic": return motioncam.QuadBayerMode.Remosaic
            case "Wrong CFA Metadata": return motioncam.QuadBayerMode.WrongCFAMetadata
            case "Correct QBCFA Metadata": return motioncam.QuadBayerMode.CorrectQBCFAMetadata
            default: return motioncam.QuadBayerMode.Remosaic
            }
        }()

        return motioncam.RenderSettings(
            motioncam.FileRenderOptions(rawValue: options) ?? motioncam.FileRenderOptions(rawValue: 0),
            Int32(draftQuality),
            cfrTargetValue,
            std.string(cropTarget),
            std.string(cameraModel),
            std.string(levels),
            logMode,
            std.string(exposureCompensation),
            quadMode
        )
    }

    private func parseCFRTarget(_ input: String) -> motioncam.CFRTarget {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        switch trimmed.lowercased() {
        case "", "disabled":
            return motioncam.CFRTarget(motioncam.CFRMode.Disabled, 0.0)
        case "prefer integer":
            return motioncam.CFRTarget(motioncam.CFRMode.PreferInteger, 0.0)
        case "prefer drop frame":
            return motioncam.CFRTarget(motioncam.CFRMode.PreferDropFrame, 0.0)
        case "median (slowmotion)":
            return motioncam.CFRTarget(motioncam.CFRMode.MedianSlowMotion, 0.0)
        case "average (testing)":
            return motioncam.CFRTarget(motioncam.CFRMode.AverageTesting, 0.0)
        default:
            // Try to parse as custom float
            if let value = Float(trimmed) {
                return motioncam.CFRTarget(motioncam.CFRMode.Custom, value)
            } else {
                return motioncam.CFRTarget(motioncam.CFRMode.PreferDropFrame, 0.0)
            }
        }
    }
}

// Helper struct for encoding/decoding Any values
struct AnyCodable: Codable {
    let value: Any

    var boolValue: Bool? {
        return value as? Bool
    }

    var intValue: Int {
        return value as? Int ?? 1
    }

    var stringValue: String {
        return value as? String ?? ""
    }

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let boolVal = try? container.decode(Bool.self) {
            value = boolVal
        } else if let intVal = try? container.decode(Int.self) {
            value = intVal
        } else if let doubleVal = try? container.decode(Double.self) {
            value = doubleVal
        } else if let stringVal = try? container.decode(String.self) {
            value = stringVal
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        if let boolVal = value as? Bool {
            try container.encode(boolVal)
        } else if let intVal = value as? Int {
            try container.encode(intVal)
        } else if let doubleVal = value as? Double {
            try container.encode(doubleVal)
        } else if let stringVal = value as? String {
            try container.encode(stringVal)
        } else {
            try container.encodeNil()
        }
    }
}
