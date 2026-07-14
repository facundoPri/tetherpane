# Child-process spike verdict

Question: can Swift Foundation resolve local stock scrcpy, launch it for one exact authorized USB device with the Responsive/audio-compatible shape, observe useful lifecycle output, and terminate it predictably?

Verdict: yes. On 2026-07-13, the disposable experiment resolved Homebrew scrcpy 4.1, launched it for the live authorized Motorola edge 40 pro, observed the device/Metal renderer/texture/server-push output, and terminated the child after four seconds. scrcpy exited with status `2` and reported `Device disconnected`, which is the expected shutdown observation after terminating the client process rather than an adapter failure.

The result has been absorbed into the durable `AirDroidScrcpy` process-engine slice. The throwaway experiment source and binary were removed. No pairing code or device content was recorded.
