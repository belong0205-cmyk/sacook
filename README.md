# SA Cook Assistant

Shared source for the macOS and Windows SA Cook Assistant apps.

## Set up on another Mac

```bash
git clone https://github.com/belong0205-cmyk/sacook.git
cd sacook
pnpm --dir PresenterAI-Windows install
./Scripts/build-all.sh
```

API keys are intentionally not committed. Enter the OpenAI key in the app on each Mac so macOS can store it securely in that Mac's Keychain.

## Build and test

- Build both platforms: `./Scripts/build-all.sh`
- Verify synchronized features: `./Scripts/verify-sync.sh`
- Run macOS tests: `./PresenterAI/Scripts/test.sh`
- Run Windows tests: `pnpm --dir PresenterAI-Windows test`

Shared policies and release metadata live in `Shared/`.
