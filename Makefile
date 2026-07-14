SHELL := /bin/bash

VERSION ?= 0.1.0
BUILD_NUMBER ?= 1
ARCHITECTURE ?= native
BUILD_SYSTEM ?= auto
SIGNING_IDENTITY ?= -
NOTARY_PROFILE ?=

.PHONY: doctor bootstrap runtime-dependencies test macos-build macos-test macos-run macos-release macos-release-test xcode-project-test android-build android-test android-install android-qa android-emulator

doctor:
	./script/doctor.sh

bootstrap:
	./script/bootstrap.sh

runtime-dependencies:
	brew bundle --file Brewfile

test: macos-test android-test

macos-build:
	swift build

macos-test:
	swift run AirDroidMacSeamTests

macos-run:
	./script/build_and_run.sh

macos-release:
	./script/package_macos.sh \
		--version "$(VERSION)" \
		--build-number "$(BUILD_NUMBER)" \
		--architecture "$(ARCHITECTURE)" \
		--build-system "$(BUILD_SYSTEM)" \
		--sign "$(SIGNING_IDENTITY)" \
		$(if $(NOTARY_PROFILE),--notarize-profile "$(NOTARY_PROFILE)")

macos-release-test:
	ARCHITECTURE="$(ARCHITECTURE)" ./script/test_macos_release_contract.sh

xcode-project-test:
	./script/test_xcode_project_contract.sh

android-build:
	./script/android_gradle.sh :app:assembleDebug --console=plain

android-test:
	./script/android_gradle.sh :app:testDebugUnitTest --console=plain

android-install:
	./script/android_install.sh $(if $(SERIAL),--serial $(SERIAL))

android-qa:
	./script/android_qa.sh $(if $(SERIAL),--serial $(SERIAL))

android-emulator:
	./script/android_emulator.sh
