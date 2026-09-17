# SA Cook Assistant

Shared source for the macOS and Windows SA Cook Assistant apps.

## Set up on another Mac

```bash
git clone https://github.com/belong0205-cmyk/sacook.git
cd sacook
./Scripts/setup-sync.sh
pnpm --dir PresenterAI-Windows install
./Scripts/build-all.sh
```

API keys are intentionally not committed. Enter the OpenAI key in the app on each Mac so macOS can store it securely in that Mac's Keychain.

## Work on two Macs without losing changes

At the start and end of every work session, run:

```bash
./Scripts/sync.sh
```

The command saves local source/data changes, pulls newer work from the other Mac, and pushes the combined history to GitHub. If both Macs edit the same lines, it stops and preserves both versions for conflict resolution instead of overwriting either copy.

You can add a useful note to the sync commit:

```bash
./Scripts/sync.sh "Improve AUTO question detection"
```

Only project source and study data are synchronized. API keys remain in each Mac's Keychain and build/cache folders remain local.

## Build and test

- Build both platforms: `./Scripts/build-all.sh`
- Verify synchronized features: `./Scripts/verify-sync.sh`
- Run macOS tests: `./PresenterAI/Scripts/test.sh`
- Run Windows tests: `pnpm --dir PresenterAI-Windows test`

Shared policies and release metadata live in `Shared/`.
