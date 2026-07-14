# TetherPane Control Center

This context describes how the Mac control center refers to Android phones, their ADB connections, and stock scrcpy sessions without conflating identity with transport.

## Language

**Physical Phone**:
An Android handset as a real-world device. The control center claims that two connections belong to one Physical Phone only when it has explicit association evidence.
_Avoid_: Device when the distinction from an ADB Endpoint matters

**ADB Endpoint**:
One exact serial accepted by ADB and passed to stock scrcpy. A Physical Phone can expose multiple ADB Endpoints at the same time.
_Avoid_: Phone, transport row

**ADB Network Endpoint**:
A typed host-and-port address used to pair or connect ADB. It may become an ADB Endpoint only after stock ADB reports an exact authorized serial.
_Avoid_: Physical Phone, device identity

**Connection Route**:
The user-meaningful way an ADB Endpoint became available: direct USB, secure Wireless Debugging, USB-assisted Wi-Fi until restart, or unclassified wireless.
_Avoid_: Transport when describing security or lifetime

**Connection Provenance**:
The evidence that establishes a Connection Route, such as a USB observation, a secure mDNS service, or an app-initiated USB-to-wireless transition.
_Avoid_: Serial pattern, port suffix

**Mirroring Session**:
One running stock scrcpy process targeted at one exact ADB Endpoint.
_Avoid_: Connection

**Saved Device**:
A local device-list record anchored to one stable USB serial or one explicitly observed secure mDNS service. It does not prove that separate records belong to the same Physical Phone.
_Avoid_: Paired phone, remembered endpoint

**Device Presence**:
The Saved Device's current control-center state: connected, waiting for USB authorization, disconnected on this Mac, or offline.
_Avoid_: ADB state when describing the user-facing list

**Disconnect on This Mac**:
Ends and locally suppresses the exact wireless ADB connection while retaining its Saved Device. Android may continue remembering this Mac's Wireless Debugging authorization.
_Avoid_: Forget, revoke, turn off Wireless Debugging

**Turn Off USB-assisted Wi-Fi**:
Closes the phone's app-opened unencrypted legacy listener and removes the exact host connection. It is a safety action, not an ordinary disconnect.
_Avoid_: Disconnect

**Forget from List**:
Removes an offline Saved Device from the local control center. It does not revoke Android's Wireless Debugging authorization.
_Avoid_: Unpair, revoke authorization
