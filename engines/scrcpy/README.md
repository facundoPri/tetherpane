# scrcpy pin

This spike targets the locally installed stock `scrcpy` **4.1** executable. It is resolved at runtime in this order: `SCRCPY_PATH`, Homebrew's Apple-silicon path, then `PATH`.

It is neither bundled nor redistributed. The SwiftUI app controls a separate stock SDL mirror window and does not embed or reimplement the internal, version-matched scrcpy protocol.

The disposable Swift child-process spike passed on an authorized USB device; see [process-spike-verdict.md](process-spike-verdict.md). Its implementation was removed after recording the result.
