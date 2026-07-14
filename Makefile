SHELL := /bin/bash

.PHONY: doctor bootstrap test macos-build macos-test macos-run android-build android-test android-install android-qa android-emulator

doctor:
	./script/doctor.sh

bootstrap:
	./script/bootstrap.sh

test: macos-test android-test

macos-build:
	swift build

macos-test:
	swift run AirDroidMacSeamTests

macos-run:
	./script/build_and_run.sh

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
