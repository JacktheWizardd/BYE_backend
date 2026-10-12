# Local Mac testing workflow

- After completing native Mac app changes, run `./scripts/build-test-app.sh` to update `test/BYE Test.app` with the latest source.
- The user opens the visible `test` folder to test development builds. Use this stable app location when sharing the latest build.
- Relaunch the updated test app after finishing Mac development so the user can test immediately. Close an older running BYE development instance first.
- Keep generated test apps out of Git. This workflow is local testing; publishing requires a separate user request.
