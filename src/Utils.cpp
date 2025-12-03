#include "Utils.h"

#include "CameraFrameMetadata.h"
#include "CameraMetadata.h"

#include <algorithm>
#include <cmath>
#include <memory>
#include <vector>
#include <dispatch/dispatch.h>

#include <arm_neon.h>

#define TINY_DNG_WRITER_IMPLEMENTATION 1

#include <tinydng/tiny_dng_writer.h>

namespace motioncam {
namespace utils {

namespace {
    const float IDENTITY_MATRIX[9] = {
        1.0f, 0.0f, 0.0f,
        0.0f, 1.0f, 0.0f,
        0.0f, 0.0f, 1.0f
    };

    bool isZeroMatrix(const std::array<float, 9>& matrix) {
        for (const auto& value : matrix) 
            if (value != 0.0f) 
                return false;
        return true;
    }

    enum DngIlluminant {
        lsUnknown					=  0,
        lsDaylight					=  1,
        lsFluorescent				=  2,
        lsTungsten					=  3,
        lsFlash						=  4,
        lsFineWeather				=  9,
        lsCloudyWeather				= 10,
        lsShade						= 11,
        lsDaylightFluorescent		= 12,		// D  5700 - 7100K
        lsDayWhiteFluorescent		= 13,		// N  4600 - 5500K
        lsCoolWhiteFluorescent		= 14,		// W  3800 - 4500K
        lsWhiteFluorescent			= 15,		// WW 3250 - 3800K
        lsWarmWhiteFluorescent		= 16,		// L  2600 - 3250K
        lsStandardLightA			= 17,
        lsStandardLightB			= 18,
        lsStandardLightC			= 19,
        lsD55						= 20,
        lsD65						= 21,
        lsD75						= 22,
        lsD50						= 23,
        lsISOStudioTungsten			= 24,

        lsOther						= 255
    };

    enum DngOrientation
    {
        kNormal		 = 1,
        kMirror		 = 2,
        kRotate180	 = 3,
        kMirror180	 = 4,
        kMirror90CCW = 5,
        kRotate90CW	 = 6,
        kMirror90CW	 = 7,
        kRotate90CCW = 8,
        kUnknown	 = 9
    };

    inline uint8_t ToTimecodeByte(int value)
    {
        return (((value / 10) << 4) | (value % 10));
    }

    unsigned short bitsNeeded(unsigned short value) {
        if (value == 0)
            return 1;

        unsigned short bits = 0;

        while (value > 0) {
            value >>= 1;
            bits++;
        }

        return bits;
    }

    int getColorIlluminant(const std::string& value) {
        if(value == "standarda")
            return lsStandardLightA;
        else if(value == "standardb")
            return lsStandardLightB;
        else if(value == "standardc")
            return lsStandardLightC;
        else if(value == "d50")
            return lsD50;
        else if(value == "d55")
            return lsD55;
        else if(value == "d65")
            return lsD65;
        else if(value == "d75")
            return lsD75;
        else
            return lsUnknown;
    }

    void normalizeShadingMap(std::vector<std::vector<float>>& shadingMap) {
        if (shadingMap.empty() || shadingMap[0].empty()) {
            return; // Handle empty case
        }

        // Find the maximum value
        float maxValue = 0.0f;
        for (const auto& row : shadingMap) {
            for (float value : row) {
                maxValue = std::max(maxValue, value);
            }
        }

        // Avoid division by zero
        if (maxValue == 0.0f) {
            return;
        }

        // Normalize all values
        for (auto& row : shadingMap) {
            for (float& value : row) {
                value /= maxValue;
            }
        }
    }

    void invertShadingMap(std::vector<std::vector<float>>& shadingMap) {
        if (shadingMap.empty() || shadingMap[0].empty()) 
            return;                                 // Handle empty case
        
        for (const auto& row : shadingMap) 
            for (float value : row) 
                if (value <= 0.0f) 
                    return;                             // Avoid division by zero
                  
        for (auto& row : shadingMap) 
            for (float& value : row) 
                value = 1 / value;          // Normalize all values
    }

    void colorOnlyShadingMap(std::vector<std::vector<float>>& shadingMap, int lensShadingMapWidth, int lensShadingMapHeight, const std::array<uint8_t, 4> cfa) {
        if (shadingMap.empty() || shadingMap[0].empty())
            return; // Handle empty case

        float maxValue = 0.0f;

        for (const auto& row : shadingMap) 
            for (float value : row) 
                maxValue = std::max(maxValue, value);
        
        if (maxValue == 0.0f)   // Avoid division by zero
            return;

        bool aggressive = false;            //TODO: add ui option for aggressive color fix reduction that if effective breaks awb and might not improve highlight reconstruction

        auto minValue00 = 10.0f;
        auto minValue01 = 10.0f;
        auto minValue10 = 10.0f;
        auto minValue11 = 10.0f;

        for(int j = 0; j < lensShadingMapHeight; j++) {
            for(int i = 0; i < lensShadingMapWidth; i++) {
                if(shadingMap[0][j*lensShadingMapWidth+i] < minValue00)
                    minValue00 = shadingMap[0][j*lensShadingMapWidth+i];
                if(shadingMap[1][j*lensShadingMapWidth+i] < minValue01)
                    minValue01 = shadingMap[1][j*lensShadingMapWidth+i];
                if(shadingMap[2][j*lensShadingMapWidth+i] < minValue10)
                    minValue10 = shadingMap[2][j*lensShadingMapWidth+i];
                if(shadingMap[3][j*lensShadingMapWidth+i] < minValue11)
                    minValue11 = shadingMap[3][j*lensShadingMapWidth+i];
        }}       

        if (cfa == std::array<uint8_t, 4>{0, 1, 1, 2} || cfa == std::array<uint8_t, 4>{2, 1, 1, 0}) {
            minValue01 = std::min(minValue01, minValue10);
            minValue01 = minValue10;
        } else if (cfa == std::array<uint8_t, 4>{1, 0, 2, 1} || cfa == std::array<uint8_t, 4>{1, 2, 0, 1}) {
            minValue00 = std::min(minValue00, minValue11);
            minValue00 = minValue11;
        }   
        
        for(int j = 0; j < lensShadingMapHeight; j++) {
            for(int i = 0; i < lensShadingMapWidth; i++) {
                if (aggressive) {                               // remove image-global white balance adjustment in shadingMap     
                    shadingMap[0][j*lensShadingMapWidth+i] = shadingMap[0][j*lensShadingMapWidth+i] / minValue00;   
                    shadingMap[1][j*lensShadingMapWidth+i] = shadingMap[1][j*lensShadingMapWidth+i] / minValue01;
                    shadingMap[2][j*lensShadingMapWidth+i] = shadingMap[2][j*lensShadingMapWidth+i] / minValue10;
                    shadingMap[3][j*lensShadingMapWidth+i] = shadingMap[3][j*lensShadingMapWidth+i] / minValue11;
                }
                auto localMinValue = std::min(shadingMap[0][j*lensShadingMapWidth+i], std::min(shadingMap[1][j*lensShadingMapWidth+i], std::min(shadingMap[2][j*lensShadingMapWidth+i], shadingMap[3][j*lensShadingMapWidth+i])));
                for(int channel = 0; channel < 4; channel++) {
                    shadingMap[channel][j*lensShadingMapWidth+i] = shadingMap[channel][j*lensShadingMapWidth+i] / localMinValue;
                }
            }
        }       // For every position in the shading map, divide gain by the minimum value of the four channels
    }       

    inline float getShadingMapValue(
        float x, float y, int channel, const std::vector<std::vector<float>>& lensShadingMap, int lensShadingMapWidth, int lensShadingMapHeight)
    {
        // Clamp input coordinates to [0, 1] range
        x = std::max(0.0f, std::min(1.0f, x));
        y = std::max(0.0f, std::min(1.0f, y));

        // Convert normalized coordinates to map coordinates
        const float mapX = x * (lensShadingMapWidth - 1);
        const float mapY = y * (lensShadingMapHeight - 1);

        // Get integer coordinates for the four surrounding pixels
        const int x0 = static_cast<int>(std::floor(mapX));
        const int y0 = static_cast<int>(std::floor(mapY));
        const int x1 = std::min(x0 + 1, lensShadingMapWidth - 1);
        const int y1 = std::min(y0 + 1, lensShadingMapHeight - 1);

        // Calculate interpolation weights
        const float wx = mapX - x0;  // Weight for x-direction interpolation
        const float wy = mapY - y0;  // Weight for y-direction interpolation

        // Get the four surrounding pixel values
        const float val00 = lensShadingMap[channel][y0*lensShadingMapWidth+x0];  // Top-left
        const float val01 = lensShadingMap[channel][y0*lensShadingMapWidth+x1];  // Top-right
        const float val10 = lensShadingMap[channel][y1*lensShadingMapWidth+x0];  // Bottom-left
        const float val11 = lensShadingMap[channel][y1*lensShadingMapWidth+x1];  // Bottom-right

        // Perform bilinear interpolation
        const float valTop = val00 * (1.0f - wx) + val01 * wx;     // Interpolation at y0
        const float valBottom = val10 * (1.0f - wx) + val11 * wx;  // Interpolation at y1

        // Then interpolate along y-axis
        return valTop * (1.0f - wy) + valBottom * wy;
    }
}

void encodeTo10Bit(
    std::vector<uint8_t>& data,
    uint32_t& width,
    uint32_t& height)
{
    uint16_t* srcPtr = reinterpret_cast<uint16_t*>(data.data());
    uint8_t* dstPtr = data.data();

    for(int y = 0; y < height; y++) {
        for(int x = 0; x < width; x+=4) {
            const uint16_t p0 = srcPtr[0];
            const uint16_t p1 = srcPtr[1];
            const uint16_t p2 = srcPtr[2];
            const uint16_t p3 = srcPtr[3];

            dstPtr[0] = p0 >> 2;
            dstPtr[1] = ((p0 & 0x03) << 6) | (p1 >> 4);
            dstPtr[2] = ((p1 & 0x0F) << 4) | (p2 >> 6);
            dstPtr[3] = ((p2 & 0x3F) << 2) | (p3 >> 8);
            dstPtr[4] = p3 & 0xFF;

            srcPtr += 4;
            dstPtr += 5;
        }
    }

    // Resize to fit new data
    auto newSize = dstPtr - data.data();

    data.resize(newSize);
}

void encodeTo12Bit(
    std::vector<uint8_t>& data,
    uint32_t& width,
    uint32_t& height)
{
    uint16_t* srcPtr = reinterpret_cast<uint16_t*>(data.data());
    uint8_t* dstPtr = data.data();

    for(int y = 0; y < height; y++) {
        for(int x = 0; x < width; x+=2) {
            const uint16_t p0 = srcPtr[0];
            const uint16_t p1 = srcPtr[1];

            dstPtr[0] = p0 >> 4;
            dstPtr[1] = ((p0 & 0x0F) << 4) | (p1 >> 8);
            dstPtr[2] = p1 & 0xFF;

            srcPtr += 2;
            dstPtr += 3;
        }
    }
    // Resize to fit new data
    auto newSize = dstPtr - data.data();

    data.resize(newSize);
}

void encodeTo14Bit(
    std::vector<uint8_t>& data,
    uint32_t& width,
    uint32_t& height)
{
    uint16_t* srcPtr = reinterpret_cast<uint16_t*>(data.data());
    uint8_t* dstPtr = data.data();

    for(int y = 0; y < height; y++) {
        for(int x = 0; x < width; x+=4) {
            const uint16_t p0 = srcPtr[0];
            const uint16_t p1 = srcPtr[1];
            const uint16_t p2 = srcPtr[2];
            const uint16_t p3 = srcPtr[3];

            dstPtr[0] = p0 >> 6;
            dstPtr[1] = ((p0 & 0x3F) << 2) | (p1 >> 12);
            dstPtr[2] = (p1 >> 4) & 0xFF;
            dstPtr[3] = ((p1 & 0x0F) << 4) | (p2 >> 10);
            dstPtr[4] = (p2 >> 2) & 0xFF;
            dstPtr[5] = ((p2 & 0x03) << 6) | (p3 >> 8);
            dstPtr[6] = p3 & 0xFF;

            srcPtr += 4;
            dstPtr += 7;
        }
    }

    // Resize to fit new data
    auto newSize = dstPtr - data.data();

    data.resize(newSize);
}

void encodeTo8Bit(
    std::vector<uint8_t>& data,
    uint32_t& width,
    uint32_t& height)
{
    uint16_t* srcPtr = reinterpret_cast<uint16_t*>(data.data());
    uint8_t* dstPtr = data.data();

    for(int y = 0; y < height; y++) {
        for(int x = 0; x < width; x++) {
            const uint16_t p0 = srcPtr[0];
            // Store lower 8 bits directly
            dstPtr[0] = p0 & 0xFF;

            srcPtr += 1;
            dstPtr += 1;
        }
    }

    // Resize to fit new data
    auto newSize = dstPtr - data.data();

    data.resize(newSize);
}

void encodeTo6Bit(
    std::vector<uint8_t>& data,
    uint32_t& width,
    uint32_t& height)
{
    uint16_t* srcPtr = reinterpret_cast<uint16_t*>(data.data());
    uint8_t* dstPtr = data.data();

    for(int y = 0; y < height; y++) {
        for(int x = 0; x < width; x+=4) {
            const uint16_t p0 = srcPtr[0];
            const uint16_t p1 = srcPtr[1];
            const uint16_t p2 = srcPtr[2];
            const uint16_t p3 = srcPtr[3];

            // Pack 4 pixels (6 bits each) into 3 bytes - use lower 6 bits
            const uint8_t v0 = p0 & 0x3F;
            const uint8_t v1 = p1 & 0x3F;
            const uint8_t v2 = p2 & 0x3F;
            const uint8_t v3 = p3 & 0x3F;

            dstPtr[0] = (v0 << 2) | (v1 >> 4);
            dstPtr[1] = ((v1 & 0x0F) << 4) | (v2 >> 2);
            dstPtr[2] = ((v2 & 0x03) << 6) | v3;

            srcPtr += 4;
            dstPtr += 3;
        }
    }

    // Resize to fit new data
    auto newSize = dstPtr - data.data();

    data.resize(newSize);
}

void encodeTo4Bit(
    std::vector<uint8_t>& data,
    uint32_t& width,
    uint32_t& height)
{
    uint16_t* srcPtr = reinterpret_cast<uint16_t*>(data.data());
    uint8_t* dstPtr = data.data();

    for(int y = 0; y < height; y++) {
        for(int x = 0; x < width; x+=2) {
            const uint16_t p0 = srcPtr[0];
            const uint16_t p1 = srcPtr[1];

            // Pack 2 pixels (4 bits each) into 1 byte - use lower 4 bits
            const uint8_t v0 = p0 & 0x0F;
            const uint8_t v1 = p1 & 0x0F;

            dstPtr[0] = (v0 << 4) | v1;

            srcPtr += 2;
            dstPtr += 1;
        }
    }

    // Resize to fit new data
    auto newSize = dstPtr - data.data();

    data.resize(newSize);
}

void encodeTo2Bit(
    std::vector<uint8_t>& data,
    uint32_t& width,
    uint32_t& height)
{
    uint16_t* srcPtr = reinterpret_cast<uint16_t*>(data.data());
    uint8_t* dstPtr = data.data();

    for(int y = 0; y < height; y++) {
        for(int x = 0; x < width; x+=4) {
            const uint16_t p0 = srcPtr[0];
            const uint16_t p1 = srcPtr[1];
            const uint16_t p2 = srcPtr[2];
            const uint16_t p3 = srcPtr[3];

            // Try different bit order: p3 in bits 1-0, p2 in bits 3-2, p1 in bits 5-4, p0 in bits 7-6
            dstPtr[0] = ((p0 & 0x03) << 6) | 
                       ((p1 & 0x03) << 4) | 
                       ((p2 & 0x03) << 2) | 
                       (p3 & 0x03);

            srcPtr += 4;
            dstPtr += 1;
        }
    }

    // Resize to fit new data
    auto newSize = dstPtr - data.data();

    data.resize(newSize);
}


//tinydngwriter::OpcodeList createLensShadingOpcodeList(
//    const CameraFrameMetadata& metadata,
//    uint32_t imageWidth,
//    uint32_t imageHeight,
//    int left = 0,
//    int top = 0)
//{
//    tinydngwriter::OpcodeList opcodeList;
//    
//    if (metadata.lensShadingMap.empty() || 
//        metadata.lensShadingMapWidth <= 0 || 
//        metadata.lensShadingMapHeight <= 0) {
//        return opcodeList; // Return empty list if no shading map
//    }
//    
//    // Build a gain map opcode compatible with DNG OpcodeList2 GainMap
//    tinydngwriter::GainMapParams gainParams;
//    
//    // Set the area to apply the gain map (active image area)
//    // Use provided left/top offsets if the active area is a sub-rectangle
//    gainParams.top = static_cast<unsigned int>(std::max(0, top));
//    gainParams.left = static_cast<unsigned int>(std::max(0, left));
//    gainParams.bottom = static_cast<unsigned int>(std::max<int>(0, top) + imageHeight);
//    gainParams.right = static_cast<unsigned int>(std::max<int>(0, left) + imageWidth);
//    
//    // Apply starting from plane 0
//    gainParams.plane = 0;
//    // Determine number of planes available in the shading map (expect 4 for Bayer)
//    unsigned int availablePlanes = static_cast<unsigned int>(metadata.lensShadingMap.size());
//    if (availablePlanes == 0) availablePlanes = 1;
//    if (availablePlanes >= 4) {
//        gainParams.planes = 4;
//    } else if (availablePlanes >= 3) {
//        gainParams.planes = 3;
//    } else {
//        gainParams.planes = 1;
//    }
//    
//    // Grid size in the gain map
//    const unsigned int mapPointsV = static_cast<unsigned int>(metadata.lensShadingMapHeight);
//    const unsigned int mapPointsH = static_cast<unsigned int>(metadata.lensShadingMapWidth);
//    gainParams.map_points_v = mapPointsV;
//    gainParams.map_points_h = mapPointsH;
//    
//    // Compute pixel pitch between adjacent map points in rows/cols (in pixels)
//    // If only a single point along a dimension, pitch covers the full extent
//    const unsigned int imageRows = imageHeight;
//    const unsigned int imageCols = imageWidth;
//    unsigned int rowPitch = (mapPointsV > 1)
//        ? static_cast<unsigned int>(std::max(1u, (imageRows - 1) / (mapPointsV - 1)))
//        : imageRows;
//    unsigned int colPitch = (mapPointsH > 1)
//        ? static_cast<unsigned int>(std::max(1u, (imageCols - 1) / (mapPointsH - 1)))
//        : imageCols;
//    gainParams.row_pitch = rowPitch;
//    gainParams.col_pitch = colPitch;
//    
//    // Map spacing and origin in relative coordinates
//    // Spacing is relative pitch to image size; origin is relative to active area
//    gainParams.map_spacing_v = (imageRows > 0) ? static_cast<double>(rowPitch) / static_cast<double>(imageRows) : 0.0;
//    gainParams.map_spacing_h = (imageCols > 0) ? static_cast<double>(colPitch) / static_cast<double>(imageCols) : 0.0;
//    gainParams.map_origin_v = (imageRows > 0) ? static_cast<double>(std::max(0, top)) / static_cast<double>(imageRows) : 0.0;
//    gainParams.map_origin_h = (imageCols > 0) ? static_cast<double>(std::max(0, left)) / static_cast<double>(imageCols) : 0.0;
//    
//    // Number of planes in the gain map payload (match planes when available)
//    gainParams.map_planes = gainParams.planes;
//    
//    // Fill gain data in plane-major, row-major order
//    if (!metadata.lensShadingMap.empty() && !metadata.lensShadingMap[0].empty()) {
//        const size_t perPlaneSize = static_cast<size_t>(mapPointsV) * static_cast<size_t>(mapPointsH);
//        const size_t expectedSize = perPlaneSize * static_cast<size_t>(gainParams.map_planes);
//        gainParams.gain_data.reserve(expectedSize);
//
//        for (unsigned int p = 0; p < gainParams.map_planes; ++p) {
//            const unsigned int srcPlane = (p < metadata.lensShadingMap.size()) ? p : 0;
//            for (unsigned int v = 0; v < mapPointsV; ++v) {
//                for (unsigned int h = 0; h < mapPointsH; ++h) {
//                    const size_t index = static_cast<size_t>(v) * mapPointsH + h;
//                    float gain = 1.0f;
//                    if (index < metadata.lensShadingMap[srcPlane].size()) {
//                        gain = metadata.lensShadingMap[srcPlane][index];
//                        if (!std::isfinite(gain) || gain <= 0.0f) {
//                            gain = 1.0f;
//                        } else if (gain > 16.0f) {
//                            gain = 16.0f; // broader but safe upper bound
//                        }
//                    }
//                    gainParams.gain_data.push_back(gain);
//                }
//            }
//        }
//
//        // Only add the gain map if we have valid data size
//        if (gainParams.gain_data.size() == expectedSize) {
//            opcodeList.AddGainMap(gainParams);
//        }
//    }
//    
//    return opcodeList;
//}

std::tuple<std::vector<uint8_t>, std::array<unsigned short, 4>, unsigned short> preprocessData(
    std::vector<uint8_t>& data,
    uint32_t& inOutWidth,
    uint32_t& inOutHeight,
    const CameraFrameMetadata& metadata,
    const CameraConfiguration& cameraConfiguration,
    const std::array<uint8_t, 4>& cfa,
    uint32_t scale,
    bool applyShadingMap,
    bool vignetteOnlyColor,
    bool normaliseShadingMap,
    bool debugShadingMap,
    bool interpretAsQuadBayer,
    std::string cropTarget,
    std::string levels,
    LogTransformMode logTransform,
    QuadBayerMode quadBayerOption,
    bool includeOpcode)
{
    if (scale > 1) scale = (scale / 2) * 2; else scale = 1;
    
    uint32_t newWidth  = (inOutWidth  / scale) & ~3u;
    uint32_t newHeight = (inOutHeight / scale) & ~3u;
    
    const auto& srcBlackLevel = cameraConfiguration.blackLevel;
    const auto  srcWhiteLevel = cameraConfiguration.whiteLevel;
    
    const std::array<float,4> linear = {
        1.f / (srcWhiteLevel - srcBlackLevel[0]),
        1.f / (srcWhiteLevel - srcBlackLevel[1]),
        1.f / (srcWhiteLevel - srcBlackLevel[2]),
        1.f / (srcWhiteLevel - srcBlackLevel[3])
    };
    
    auto   dstBlackLevel = srcBlackLevel;
    float  dstWhiteLevel = srcWhiteLevel;
    
    auto   lensShadingMap = metadata.lensShadingMap;
    if (applyShadingMap) {
        int srcBits = bitsNeeded(static_cast<unsigned short>(cameraConfiguration.whiteLevel));
        int useBits = std::min(16, srcBits + 4);
        
        dstWhiteLevel = std::pow(2.f, useBits) - 1.f;
        for (auto& v : dstBlackLevel) v *= (1 << (useBits - srcBits));
        if(normaliseShadingMap)
            normalizeShadingMap(lensShadingMap);
    }
    
    const int blocksX = newWidth  / 2;
    const int blocksY = newHeight / 2;
    std::vector<std::array<float,4>> shadingLUT;
    if (applyShadingMap)
        shadingLUT.resize(static_cast<size_t>(blocksX * blocksY));
    
    const int fullWidth  = metadata.originalWidth;
    const int fullHeight = metadata.originalHeight;
    const int left       = (fullWidth  - inOutWidth ) / 2;
    const int top        = (fullHeight - inOutHeight) / 2;
    
    const float shadingMapScaleX = 1.f / fullWidth;
    const float shadingMapScaleY = 1.f / fullHeight;
    
    if (applyShadingMap) {
        size_t idx = 0;
        for (int by = 0; by < blocksY; ++by)
            for (int bx = 0; bx < blocksX; ++bx, ++idx)
            {
                const uint32_t srcX = bx * 2 * scale;
                const uint32_t srcY = by * 2 * scale;
                const float sx = (srcX + left) * shadingMapScaleX;
                const float sy = (srcY + top ) * shadingMapScaleY;
                
                shadingLUT[idx] = {
                    getShadingMapValue(sx, sy, 0, lensShadingMap,
                                       metadata.lensShadingMapWidth,
                                       metadata.lensShadingMapHeight),
                    getShadingMapValue(sx, sy, 1, lensShadingMap,
                                       metadata.lensShadingMapWidth,
                                       metadata.lensShadingMapHeight),
                    getShadingMapValue(sx, sy, 2, lensShadingMap,
                                       metadata.lensShadingMapWidth,
                                       metadata.lensShadingMapHeight),
                    getShadingMapValue(sx, sy, 3, lensShadingMap,
                                       metadata.lensShadingMapWidth,
                                       metadata.lensShadingMapHeight)
                };
            }
    }
    
    std::vector<uint8_t> dst(sizeof(uint16_t) * newWidth * newHeight);
    uint16_t*            dstData = reinterpret_cast<uint16_t*>(dst.data());
    uint16_t*            srcData = reinterpret_cast<uint16_t*>(data.data());
    const uint32_t       srcStride = inOutWidth;

    dispatch_apply(blocksY, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^(size_t by) {
        const size_t lutRow  = static_cast<size_t>(by * blocksX);
        const uint32_t dstRow0 = by * 2 * newWidth;
        const uint32_t dstRow1 = dstRow0 + newWidth;
        
        const uint32_t srcRow0 = by * 2 * scale * srcStride;
        const uint32_t srcRow1 = srcRow0 + srcStride * scale;
        
        for (int bx = 0; bx < blocksX; ++bx)
        {
            const size_t lutIdx = lutRow + bx;
            const uint32_t srcCol = bx * 2 * scale;
            
            const uint16_t s0 = srcData[srcRow0 + srcCol];
            const uint16_t s1 = srcData[srcRow0 + srcCol + 1];
            const uint16_t s2 = srcData[srcRow1 + srcCol];
            const uint16_t s3 = srcData[srcRow1 + srcCol + 1];
            
            float shade0 = 1.f, shade1 = 1.f, shade2 = 1.f, shade3 = 1.f;
            if (applyShadingMap) {
                const auto& lut = shadingLUT[lutIdx];
                shade0 = lut[cfa[0]];
                shade1 = lut[cfa[1]];
                shade2 = lut[cfa[2]];
                shade3 = lut[cfa[3]];
            }

            uint16x4_t s     = {s0, s1, s2, s3};
            float32x4_t sf   = vcvtq_f32_u32(vmovl_u16(s));
            
            const float blackArr[4] = {
                srcBlackLevel[0], srcBlackLevel[1],
                srcBlackLevel[2], srcBlackLevel[3]};
            const float linArr[4]   = {linear[0], linear[1], linear[2], linear[3]};
            const float shadeArr[4] = {shade0, shade1, shade2, shade3};
            const float dstBLArr[4] = {
                dstBlackLevel[0], dstBlackLevel[1],
                dstBlackLevel[2], dstBlackLevel[3]};
            const float dstScaleArr[4] = {
                dstWhiteLevel - dstBlackLevel[0],
                dstWhiteLevel - dstBlackLevel[1],
                dstWhiteLevel - dstBlackLevel[2],
                dstWhiteLevel - dstBlackLevel[3]};
            
            float32x4_t vBlack  = vld1q_f32(blackArr);
            float32x4_t vLinear = vld1q_f32(linArr);
            float32x4_t vShade  = vld1q_f32(shadeArr);
            float32x4_t vDstBL  = vld1q_f32(dstBLArr);
            float32x4_t vDstScl = vld1q_f32(dstScaleArr);
            
            float32x4_t v = vmaxq_f32(vdupq_n_f32(0.f),
                                      vmulq_f32(vLinear,
                                                vmulq_f32(vShade,
                                                          vsubq_f32(sf, vBlack))));
            v = vmlaq_f32(vDstBL, v, vDstScl);                 // vDstBL + v * scale
            v = vminq_f32(v, vdupq_n_f32(dstWhiteLevel));       // clamp
            
            uint32x4_t ui = vcvtq_u32_f32(v);
            uint16x4_t us = vmovn_u32(ui);
            
            /* store */
            uint32_t dstOff = bx * 2;
            // us = {d0, d1, d2, d3}
            dstData[dstRow0 + dstOff    ] = vget_lane_u16(us, 0);
            dstData[dstRow0 + dstOff + 1] = vget_lane_u16(us, 1);
            dstData[dstRow1 + dstOff    ] = vget_lane_u16(us, 2);
            dstData[dstRow1 + dstOff + 1] = vget_lane_u16(us, 3);
        }
    });
    
    inOutWidth  = newWidth;
    inOutHeight = newHeight;
    
    std::array<unsigned short, 4> blackLevelResult;
    for (size_t i = 0; i < 4; ++i)
        blackLevelResult[i] =
        static_cast<unsigned short>(std::round(dstBlackLevel[i]));
    
    return { std::move(dst), blackLevelResult,
        static_cast<unsigned short>(dstWhiteLevel) };
}

std::shared_ptr<std::vector<char>> generateDng(
    std::vector<uint8_t>& data,
    const CameraFrameMetadata& metadata,
    const CameraConfiguration& cameraConfiguration,
    float recordingFps,
    int frameNumber,
    double baselineExpValue,
    const RenderSettings& settings)
{
    unsigned int width = metadata.width;
    unsigned int height = metadata.height;

    std::array<uint8_t, 4> cfa;
    std::array<uint8_t, 16> qcfa;

    if(cameraConfiguration.sensorArrangement == "rggb")
        cfa = { 0, 1, 1, 2 };
    else if(cameraConfiguration.sensorArrangement == "bggr")
        cfa = { 2, 1, 1, 0 };
    else if(cameraConfiguration.sensorArrangement == "grbg")
        cfa = { 1, 0, 2, 1 };
    else if(cameraConfiguration.sensorArrangement == "gbrg")
        cfa = { 1, 2, 0, 1 };
    else
        throw std::runtime_error("Invalid sensor arrangement");

    // Scale down if requested
    bool applyShadingMap = settings.options & RENDER_OPT_APPLY_VIGNETTE_CORRECTION;
    bool vignetteOnlyColor = settings.options & RENDER_OPT_VIGNETTE_ONLY_COLOR;
    bool normalizeShadingMap = settings.options & RENDER_OPT_NORMALIZE_SHADING_MAP;
    bool debugShadingMap = settings.options & RENDER_OPT_DEBUG_SHADING_MAP;
    bool normalizeExposure = settings.options & RENDER_OPT_NORMALIZE_EXPOSURE;
    bool useLogCurve = settings.options & RENDER_OPT_LOG_TRANSFORM;
    bool interpretAsQuadBayer = metadata.needRemosaic || settings.options & RENDER_OPT_INTERPRET_AS_QUAD_BAYER;

    std::string cropTarget = settings.cropTarget;
    if(!(settings.options & RENDER_OPT_CROPPING))// || width != metadata.originalWidth || height != metadata.originalHeight)
        cropTarget = "0x0";

    auto [processedData, dstBlackLevel, dstWhiteLevel] = utils::preprocessData(
        data,
        width, height,
        metadata,
        cameraConfiguration,
        cfa,
        settings.draftScale,
        applyShadingMap, vignetteOnlyColor, normalizeShadingMap, debugShadingMap, interpretAsQuadBayer,
        cropTarget,
        settings.levels,
        settings.logTransform,
        settings.quadBayerOption,
        true  // includeOpcode = true to generate lens shading opcode when not applied to image
    );

//    spdlog::debug("New black level {},{},{},{} and white level {}",
//                  dstBlackLevel[0], dstBlackLevel[1], dstBlackLevel[2], dstBlackLevel[3], dstWhiteLevel);

    // Encode to reduce size in container
    auto encodeBits = bitsNeeded(dstWhiteLevel);

    if(encodeBits <= 2) {
        utils::encodeTo2Bit(processedData, width, height);
        encodeBits = 2;
    }
    else if(encodeBits <= 4) {
        utils::encodeTo4Bit(processedData, width, height);
        encodeBits = 4;
    }
    else if(encodeBits <= 6) {
        utils::encodeTo6Bit(processedData, width, height);
        encodeBits = 6;
    }
    else if(encodeBits <= 8) {
        utils::encodeTo8Bit(processedData, width, height);
        encodeBits = 8;
    }
    else if(encodeBits <= 10) {
        utils::encodeTo10Bit(processedData, width, height);
        encodeBits = 10;
    }
    else if(encodeBits <= 12) {
        utils::encodeTo12Bit(processedData, width, height);
        encodeBits = 12;
    }
    else if(encodeBits <= 14) {
        utils::encodeTo14Bit(processedData, width, height);
        encodeBits = 14;
    }
    else {
        encodeBits = 16;
    }

    // Create first frame
    tinydngwriter::DNGImage dng;

    dng.SetBigEndian(false);
    dng.SetDNGVersion(1, 4, 0, 0);
    dng.SetDNGBackwardVersion(1, 1, 0, 0);
    dng.SetImageWidth(width);
    dng.SetImageLength(height);
    dng.SetPlanarConfig(tinydngwriter::PLANARCONFIG_CONTIG);
    dng.SetPhotometric(tinydngwriter::PHOTOMETRIC_CFA);
    dng.SetRowsPerStrip(height);
    dng.SetSamplesPerPixel(1);                                                
    dng.SetXResolution(300);
    dng.SetYResolution(300);

    dng.SetBlackLevelRepeatDim(2, 2);
        
    dng.SetCompression(tinydngwriter::COMPRESSION_NONE);

    dng.SetIso(metadata.iso);
    dng.SetExposureTime(metadata.exposureTime / 1e9);

    float exposureOffset = (settings.cameraModel == "Panasonic" ? -2.0f : 0.0f);

    // Parse float from exposureCompensation string and add to exposureOffset
    if (!settings.exposureCompensation.empty()) {
        try {
            exposureOffset += std::stof(settings.exposureCompensation);
        } catch (const std::exception&) {
            // If parsing fails, keep the original exposureOffset value
        }
    }

//    if (normalizeExposure)
//        dng.SetBaselineExposure(std::log2(baselineExpValue / (metadata.iso * metadata.exposureTime)) + exposureOffset);
//    else
//        dng.SetBaselineExposure(exposureOffset);

    if(interpretAsQuadBayer && settings.draftScale == 1 && settings.quadBayerOption == QuadBayerMode::CorrectQBCFAMetadata) {   //de/remosaic need to be disabled and add ui option. 
        dng.SetCFARepeatPatternDim(4, 4);
        std::array<uint8_t, 4> cfa_pattern_0112 = {0,1,1,2};
        std::array<uint8_t, 4> cfa_pattern_2110 = {2,1,1,0};
        std::array<uint8_t, 4> cfa_pattern_1021 = {1,0,2,1};
        
        if (cfa == cfa_pattern_0112) 
            qcfa = {0,0,1,1,0,0,1,1,1,1,2,2,1,1,2,2};
        else if (cfa == cfa_pattern_2110) 
            qcfa = {2,2,1,1,2,2,1,1,1,1,0,0,1,1,0,0};
        else if (cfa == cfa_pattern_1021) 
            qcfa = {1,1,0,0,1,1,0,0,2,2,1,1,2,2,1,1};
        else 
            qcfa = {1,1,2,2,1,1,2,2,0,0,1,1,0,0,1,1};
        dng.SetCFAPattern(16, qcfa.data());
    } else {
        dng.SetCFARepeatPatternDim(2, 2);
        dng.SetCFAPattern(4, cfa.data());
    }

    // Add orientation tag
    DngOrientation dngOrientation;
    bool isFlipped = cameraConfiguration.extraData.postProcessSettings.flipped;

    switch(metadata.orientation)
    {
    case ScreenOrientation::PORTRAIT:
        dngOrientation = isFlipped ? DngOrientation::kMirror90CW : DngOrientation::kRotate90CW;
        break;

    case ScreenOrientation::REVERSE_PORTRAIT:
        dngOrientation = isFlipped ? DngOrientation::kMirror90CCW : DngOrientation::kRotate90CCW;
        break;

    case ScreenOrientation::REVERSE_LANDSCAPE:
        dngOrientation = isFlipped ? DngOrientation::kMirror180 : DngOrientation::kRotate180;
        break;

    case ScreenOrientation::LANDSCAPE:
        dngOrientation = isFlipped ? DngOrientation::kMirror : DngOrientation::kNormal;
        break;

    default:
        dngOrientation = DngOrientation::kUnknown;
        break;
    }

    dng.SetOrientation(dngOrientation);

    // Time code
    float time = frameNumber / recordingFps;

    int hours = (int) floor(time / 3600);
    int minutes = ((int) floor(time / 60)) % 60;
    int seconds = ((int) floor(time)) % 60;
    int frames = recordingFps > 1 ? (frameNumber % static_cast<int>(std::round(recordingFps))) : 0;

    std::vector<uint8_t> timeCode(8);

    timeCode[0] = ToTimecodeByte(frames) & 0x3F;
    timeCode[1] = ToTimecodeByte(seconds) & 0x7F;
    timeCode[2] = ToTimecodeByte(minutes) & 0x7F;
    timeCode[3] = ToTimecodeByte(hours) & 0x3F;

    dng.SetTimeCode(timeCode.data());
    dng.SetFrameRate(recordingFps);

    // Rectangular
    dng.SetCFALayout(1);

    const uint16_t bps[1] = { encodeBits };
    dng.SetBitsPerSample(1, bps);

    if (!isZeroMatrix(cameraConfiguration.colorMatrix1))
        dng.SetColorMatrix1(3, cameraConfiguration.colorMatrix1.data());
    if (!isZeroMatrix(cameraConfiguration.colorMatrix2))
        dng.SetColorMatrix2(3, cameraConfiguration.colorMatrix2.data());

    if (!isZeroMatrix(cameraConfiguration.forwardMatrix1))
        dng.SetForwardMatrix1(3, cameraConfiguration.forwardMatrix1.data());
    if (!isZeroMatrix(cameraConfiguration.forwardMatrix2))
        dng.SetForwardMatrix2(3, cameraConfiguration.forwardMatrix2.data());

    dng.SetCameraCalibration1(3, IDENTITY_MATRIX);
    dng.SetCameraCalibration2(3, IDENTITY_MATRIX);

    dng.SetAsShotNeutral(3, metadata.asShotNeutral.data());

    dng.SetCalibrationIlluminant1(getColorIlluminant(cameraConfiguration.colorIlluminant1));
    dng.SetCalibrationIlluminant2(getColorIlluminant(cameraConfiguration.colorIlluminant2));

    // Additional information
    const auto software = "MotionCam Tools";

    dng.SetSoftware(software);


    if(settings.cameraModel != ""){
        if (settings.cameraModel == "Blackmagic") {
            dng.SetUniqueCameraModel("Blackmagic Pocket Cinema Camera 4K");
        } else if (settings.cameraModel == "Panasonic") {
            dng.SetUniqueCameraModel("Panasonic Varicam RAW");
        } else if (settings.cameraModel == "Fujifilm" || settings.cameraModel == "Fujifilm X-T5") {
            dng.SetUniqueCameraModel("Fujifilm X-T5");
//            dng.SetMake("Fujifilm");
//            dng.SetCameraModelName("X-T5");
        } else {
            // Generic camera model
            dng.SetUniqueCameraModel(settings.cameraModel);
        }
    } else {
        dng.SetUniqueCameraModel(cameraConfiguration.extraData.postProcessSettings.metadata.buildModel);
    }

//    // Add lens shading map as opcode list 2 if not applied to image data
//    if (!opcodeList2.IsEmpty()) {
//        dng.SetOpcodeList2(opcodeList2);
//    }


    // Set data
    dng.SetSubfileType();

    const uint32_t activeArea[4] = { 0, 0, height, width };
    dng.SetActiveArea(&activeArea[0]);

    // Add linearization table based on actual bit depth

    if (settings.logTransform != LogTransformMode::Disabled && !(settings.logTransform == LogTransformMode::KeepInput && !applyShadingMap)) {
        // Create linearization table sized for the actual stored range
        // The stored values range from 0 to dstWhiteLevel, so we need dstWhiteLevel+1 entries
        const int tableSize = static_cast<int>(dstWhiteLevel) + 1;
        std::vector<unsigned short> linearizationTable(tableSize);
        
        for (int i = 0; i < tableSize; i++) {
            // Convert stored log value back to linear
            // Must match the aggressive log curve: logValue = log2(1 + k*clampedValue) / log2(1 + k)
            // Inverse: clampedValue = (2^(logValue * log2(1 + k)) - 1) / k
            
            float logValue = static_cast<float>(i);
            float normalizedLogValue = logValue / dstWhiteLevel;  // Normalize by dstWhiteLevel to match forward transform
            
            // Reverse the k=30 curve with guaranteed identity preservation
            float linearValue;
            
            if (i == 0) {
                linearValue = 0.0f;  // Exact identity: stored 0 → linear 0
            } else if (i == tableSize - 1) {
                linearValue = 1.0f;  // Force maximum table entry → linear 1 → 65535
            } else {                               
                // Inverse of: logValue = log2(1 + k*clampedValue) / log2(1 + k)
                linearValue = (std::pow(2.0f, normalizedLogValue * std::log2(1.0f + 60.0f)) - 1.0f) / 60.0f;
                linearValue = std::clamp(linearValue, 0.0f, 1.0f);
            }            
            // Scale to 16-bit range            
            linearizationTable[i] = static_cast<unsigned short>(linearValue * 65535.0f);                  
        }        
//        dng.SetLinearizationTable(tableSize, linearizationTable.data());
        std::array<unsigned short, 4> linearBlackLevel = {0, 0, 0, 0};  // Linear black is 0
        dng.SetBlackLevel(4, linearBlackLevel.data());
        dng.SetWhiteLevel(65534);  //idk why
        //displayLevels = std::to_string(static_cast<int>(srcWhiteLevel)) + "/" + std::to_string(static_cast<float>(srcBlackLevel[0])) + " -> " + std::to_string(static_cast<int>(dstWhiteLevel)) + "/0 RAW" + std::to_string(bitsNeeded(dstWhiteLevel)) + " (log)";
    } else {           
        dng.SetBlackLevel(4, dstBlackLevel.data());
        dng.SetWhiteLevel(dstWhiteLevel);
        //displayLevels = std::to_string(static_cast<float>(srcWhiteLevel)) + "/" + std::to_string(static_cast<float>(srcBlackLevel[0])) + 
        //                    ((int) srcWhiteLevel != (int) dstWhiteLevel || (float) srcBlackLevel[0] != (float) dstBlackLevel[0] ? " -> " + std::to_string(static_cast<int>(dstWhiteLevel)) + "/" +  std::to_string(static_cast<float>(dstBlackLevel[0])): "") + 
        //                    " RAW" + std::to_string(bitsNeeded(dstWhiteLevel));    
    }    

    // Write DNG
    std::string err;

    // Save to memory
    auto output = std::make_shared<std::vector<char>>();

    // Reserve enough to fit the data
    output->reserve(width*height*sizeof(uint16_t) + 512*1024);

    utils::vector_ostream stream(*output);

    dng.WriteToFile(stream, &err, reinterpret_cast<const unsigned char*>(processedData.data()), processedData.size());

    return output;
}

int gcd(int a, int b) {
    while (b != 0) {
        int temp = b;
        b = a % b;
        a = temp;
    }
    return a;
}

std::pair<int, int> toFraction(float frameRate, int base) {
    // Handle invalid input
    if (frameRate <= 0) {
        return std::make_pair(0, 1);
    }

    // For frame rates, we want numerator/denominator where denominator is close to base
    // This gives us precise ratios like 30000/1001 for 29.97 fps

    int numerator = static_cast<int>(std::round(frameRate * base));
    int denominator = base;

    // Reduce to lowest terms
    int divisor = gcd(numerator, denominator);
    numerator /= divisor;
    denominator /= divisor;

    return std::make_pair(numerator, denominator);
}

} // namespace utils
} // namespace motioncam