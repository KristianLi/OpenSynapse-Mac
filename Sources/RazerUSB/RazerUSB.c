#include "RazerUSB.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>

static int read_number(io_service_t service, CFStringRef key, int64_t *out) {
    CFTypeRef value = IORegistryEntryCreateCFProperty(service, key, kCFAllocatorDefault, 0);
    if (value == NULL) {
        return 0;
    }
    int ok = 0;
    if (CFGetTypeID(value) == CFNumberGetTypeID()) {
        ok = CFNumberGetValue((CFNumberRef)value, kCFNumberSInt64Type, out) ? 1 : 0;
    }
    CFRelease(value);
    return ok;
}

/// Finds the IOUSBHostDevice service. Callers release the returned object.
static io_service_t find_device(uint16_t vendorId, uint16_t productId, uint32_t locationId) {
    const char *classNames[] = {"IOUSBHostDevice", kIOUSBDeviceClassName};
    for (size_t c = 0; c < sizeof(classNames) / sizeof(classNames[0]); c++) {
        CFMutableDictionaryRef matching = IOServiceMatching(classNames[c]);
        if (matching == NULL) {
            continue;
        }
        int32_t vid = vendorId;
        int32_t pid = productId;
        CFNumberRef vidRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &vid);
        CFNumberRef pidRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &pid);
        CFDictionarySetValue(matching, CFSTR(kUSBVendorID), vidRef);
        CFDictionarySetValue(matching, CFSTR(kUSBProductID), pidRef);
        CFRelease(vidRef);
        CFRelease(pidRef);

        io_iterator_t iterator = IO_OBJECT_NULL;
        // IOServiceGetMatchingServices consumes the matching dictionary.
        if (IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) != KERN_SUCCESS) {
            continue;
        }
        io_service_t found = IO_OBJECT_NULL;
        io_service_t service;
        while ((service = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
            int64_t location = 0;
            if (found == IO_OBJECT_NULL &&
                (locationId == 0 ||
                 (read_number(service, CFSTR(kUSBDevicePropertyLocationID), &location) &&
                  (uint32_t)location == locationId))) {
                found = service;
            } else {
                IOObjectRelease(service);
            }
        }
        IOObjectRelease(iterator);
        if (found != IO_OBJECT_NULL) {
            return found;
        }
    }
    return IO_OBJECT_NULL;
}

int rz_usb_device_present(uint16_t vendorId, uint16_t productId, uint32_t locationId) {
    io_service_t service = find_device(vendorId, productId, locationId);
    if (service == IO_OBJECT_NULL) {
        return 0;
    }
    IOObjectRelease(service);
    return 1;
}

IOReturn rz_usb_control_request(
    uint16_t vendorId,
    uint16_t productId,
    uint32_t locationId,
    uint8_t requestType,
    uint8_t request,
    uint16_t value,
    uint16_t index,
    uint8_t *data,
    uint16_t length,
    uint32_t *transferred) {
    if (transferred != NULL) {
        *transferred = 0;
    }
    io_service_t service = find_device(vendorId, productId, locationId);
    if (service == IO_OBJECT_NULL) {
        return kIOReturnNoDevice;
    }

    IOCFPlugInInterface **plugin = NULL;
    SInt32 score = 0;
    kern_return_t kr = IOCreatePlugInInterfaceForService(
        service, kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID, &plugin, &score);
    IOObjectRelease(service);
    if (kr != KERN_SUCCESS || plugin == NULL) {
        return kr == KERN_SUCCESS ? kIOReturnError : kr;
    }

    IOUSBDeviceInterface **device = NULL;
    HRESULT result = (*plugin)->QueryInterface(
        plugin, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID), (LPVOID *)&device);
    IODestroyPlugInInterface(plugin);
    if (result != S_OK || device == NULL) {
        return kIOReturnUnsupported;
    }

    // Class requests addressed to an interface do not change device state, so the device
    // does not have to be opened (the HID driver keeps owning it).
    IOUSBDevRequest setup;
    setup.bmRequestType = requestType;
    setup.bRequest = request;
    setup.wValue = value;
    setup.wIndex = index;
    setup.wLength = length;
    setup.pData = data;
    setup.wLenDone = 0;
    IOReturn status = (*device)->DeviceRequest(device, &setup);
    if (transferred != NULL) {
        *transferred = setup.wLenDone;
    }
    (*device)->Release(device);
    return status;
}
