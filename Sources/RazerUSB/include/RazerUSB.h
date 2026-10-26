#ifndef RAZER_USB_H
#define RAZER_USB_H

#include <stdint.h>
#include <IOKit/IOReturn.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Sends a HID class request on the default control pipe of the USB device identified by
/// vendor, product and location ID. This mirrors OpenRazer's usb_control_msg path and works
/// without opening the HID interface, so it does not need Input Monitoring permission.
///
/// requestType/request/value/index/length follow the USB setup packet. For OUT requests
/// `data` is read; for IN requests it is written and `transferred` receives the byte count.
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
    uint32_t *transferred);

/// Returns 1 when a USB device with this vendor, product and location ID is present.
int rz_usb_device_present(uint16_t vendorId, uint16_t productId, uint32_t locationId);

#ifdef __cplusplus
}
#endif

#endif
