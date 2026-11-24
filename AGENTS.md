# List of Lists

To install on someone's iPhone, follow the [direct install guide](docs/install-iphone.md). Use the checked-in `ListOfLists.xcodeproj` and the `ListOfLists` scheme.

- Run `make doctor` to check Xcode, `make setup` for a simulator build, and `make wizard` to discover physical iPhones and signing teams.
- Use the owner's selected iPhone, development team and unique bundle ID. Run `make preflight`, then `make install-iphone`. The owner handles Apple sign-in, unlocking and trust prompts.
- Report the installed bundle ID and the running PID from the phone. If launch is blocked, report the last verified step and retry with `make verify-iphone`.
