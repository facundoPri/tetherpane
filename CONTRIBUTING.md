# Contributing

Thanks for helping improve the macOS control center.

## Before opening a pull request

1. Read `CONTEXT.md` and preserve its distinction between a Physical Phone, an exact ADB Endpoint, a Connection Route, and a Saved Device.
2. Keep exact-device safety: every ADB and scrcpy action must target the endpoint the user selected. Never infer that two ambiguous endpoints are one phone.
3. Do not add hidden Android settings writes, an Android companion requirement, an embedded scrcpy renderer, or bundled third-party binaries without an explicit design and license review.
4. Keep secrets, signing certificates, App Store Connect keys, device dumps, recordings, and generated release artifacts out of Git.

Run the relevant checks before submitting:

```bash
make macos-build
make macos-test
make xcode-project-test
make macos-release-test
bash -n script/*.sh
```

If you change the optional Android experiment, also run:

```bash
make android-test
```

Describe automated checks, visible UI outcomes, physical-device checks, and checks not run separately in the pull request.
