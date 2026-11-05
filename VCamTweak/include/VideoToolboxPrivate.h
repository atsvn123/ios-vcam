#pragma once
#include <stdint.h>
#include <CoreFoundation/CoreFoundation.h>
#include <CoreVideo/CoreVideo.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct OpaqueVTPixelTransferSession *VTPixelTransferSessionRef;
typedef struct OpaqueVTImageRotationSession *VTImageRotationSessionRef;

extern int32_t VTPixelTransferSessionCreate(
    CFAllocatorRef allocator,
    VTPixelTransferSessionRef *pixelTransferSessionOut);

extern void VTPixelTransferSessionInvalidate(VTPixelTransferSessionRef session);

extern int32_t VTPixelTransferSessionTransferImage(
    VTPixelTransferSessionRef session,
    CVImageBufferRef sourceBuffer,
    CVImageBufferRef destinationBuffer);

extern int32_t VTImageRotationSessionCreate(
    CFAllocatorRef allocator,
    int rotationDegrees,
    VTImageRotationSessionRef *imageRotationSessionOut);

extern int32_t VTImageRotationSessionTransferImage(
    VTImageRotationSessionRef session,
    CVImageBufferRef sourceBuffer,
    CVImageBufferRef destinationBuffer);

extern const CFStringRef kVTPixelTransferPropertyKey_EnableGPUAcceleratedTransfer;
extern const CFStringRef kVTImageRotationPropertyKey_EnableHighSpeedTransfer;

#ifdef __cplusplus
}
#endif
