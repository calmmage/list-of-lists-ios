.DEFAULT_GOAL := help
.PHONY: help doctor setup wizard preflight install-iphone verify-iphone

export DEVICE_ID TEAM_ID BUNDLE_ID

help:
	@echo 'make doctor         Check the local Xcode installation and iOS SDK'
	@echo 'make setup          Build the app for iPhone Simulator'
	@echo 'make wizard         Find physical iPhones and local signing teams'
	@echo 'make preflight      Check DEVICE_ID, TEAM_ID and BUNDLE_ID before signing'
	@echo 'make install-iphone Build, install and open on the selected iPhone'
	@echo 'make verify-iphone  Find and reopen the installed app (DEVICE_ID, BUNDLE_ID)'
	@echo 'First install? Read docs/install-iphone.md.'

doctor:
	@/usr/bin/python3 scripts/iphone.py doctor

setup: doctor
	@/usr/bin/python3 scripts/iphone.py setup

wizard: doctor
	@/usr/bin/python3 scripts/iphone.py wizard

preflight install-iphone verify-iphone:
	@/usr/bin/python3 scripts/iphone.py $@
