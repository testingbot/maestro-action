# TestingBot Maestro GitHub Action

Run your [Maestro](https://maestro.mobile.dev) flows on [TestingBot](https://testingbot.com) real devices, emulators and simulators from GitHub Actions. A thin wrapper around the [`testingbot` CLI](https://github.com/testingbot/testingbotctl) with inputs that mirror the Maestro Cloud action, so migrating is usually a one-line change.

```yaml
- uses: testingbot/maestro-action@v1
  with:
    api-key: ${{ secrets.TESTINGBOT_KEY }}
    api-secret: ${{ secrets.TESTINGBOT_SECRET }}
    app-file: app/build/outputs/apk/debug/app-debug.apk
    workspace: .maestro
```

The step fails when a flow fails (exit code 2) and on CLI or infrastructure errors (exit code 1). A results table is written to the job summary and every result is available as an output.

## Migrating from Maestro Cloud

```diff
-- uses: mobile-dev-inc/action-maestro-cloud@v2
+- uses: testingbot/maestro-action@v1
   with:
-    api-key: ${{ secrets.MAESTRO_CLOUD_API_KEY }}
-    project-id: proj_01example
+    api-key: ${{ secrets.TESTINGBOT_KEY }}
+    api-secret: ${{ secrets.TESTINGBOT_SECRET }}
     app-file: app.zip
     workspace: .maestro
     include-tags: smoke
     env: |
       USERNAME=demo
```

`app-file`, `app-binary-id`, `workspace`, `name`, `async`, `timeout`, `env`, `include-tags`, `exclude-tags` and `device-locale` keep their meaning. There is no `project-id`; TestingBot authenticates with a key and secret. `MAESTRO_CLOUD_CONSOLE_URL` is `console-url`, `MAESTRO_CLOUD_APP_BINARY_ID` is `app-id`, `MAESTRO_CLOUD_UPLOAD_STATUS` is `outcome` and `MAESTRO_CLOUD_FLOW_RESULTS` is `flow-results`.

## Inputs

| Input | Description | Default |
|---|---|---|
| `api-key` | TestingBot API key. **Required.** | |
| `api-secret` | TestingBot API secret. **Required.** | |
| `app-file` | App under test (`.apk`, `.ipa`, `.app`, `.zip`). Either this or `app-binary-id`. | |
| `app-binary-id` | Project ID of an app uploaded earlier (the `app-id` output); skips the upload. | |
| `workspace` | Flows directory, file or glob. Several entries: one per line. | `.maestro` |
| `name` | Run name in the dashboard. | PR title, else commit message |
| `async` | Submit and return immediately. Never fails on results; `flow-results` is empty. | `false` |
| `timeout` | Minutes to wait for results before cancelling and failing. | `60` |
| `env` | Flow environment variables, one `KEY=VALUE` per line. | |
| `include-tags` / `exclude-tags` | Comma-separated Maestro tags. | |
| `exclude-flows` | Flow files, directories or globs to leave out (comma-separated). | |
| `device` / `device-version` / `platform` | Single device selection, e.g. `Pixel 9` / `14` / `Android`. Platform is detected from the app when omitted. | any device |
| `real-device` | Use a real device instead of an emulator/simulator. | `false` |
| `device-matrix` | Run every flow on each listed device, `<device>[:<version>][:real]`, one per line. Not with `device`. | |
| `device-locale` / `timezone` / `orientation` | Device settings, e.g. `de_DE` / `Europe/London` / `LANDSCAPE`. | |
| `google-play` | Google Play enabled Android emulator. | `false` |
| `other-app` | Companion apps, one path or `tb://` URL per line (max 4). | |
| `retry` | Retry failed flows up to N times (0-2). | `0` |
| `shard-split` | Split flows across N parallel sessions per device. | |
| `maestro-version` | Maestro version to run. | TestingBot default |
| `report` | `junit`, `html`, `html-detailed` or `allure`, saved to `report-output-dir`. | |
| `report-output-dir` | Where reports go. | `testingbot-reports` |
| `download-artifacts` | `all` or `failed`: logs, screenshots, video as a zip in `artifacts-output-dir`. | |
| `artifacts-output-dir` | Where the artifacts zip goes. | `testingbot-artifacts` |
| `metadata` | Extra `KEY=VALUE` metadata shown on the run, one per line. | |
| `groups` | Dashboard groups (comma-separated). | |
| `cli-version` | `@testingbot/cli` version to use. | `latest` |
| `dry-run` | Validate and print the request without running anything. | `false` |
| `extra-args` | Raw extra arguments for `testingbot maestro`. | |

Branch, commit SHA, repository and pull request number/URL are filled in from the GitHub context automatically and shown on the run in the dashboard.

## Outputs

| Output | Description |
|---|---|
| `app-id` | TestingBot project ID. Pass it as `app-binary-id` in later steps or jobs to skip the upload. |
| `console-url` | Link to the results in the TestingBot dashboard. |
| `outcome` | `passed`, `failed`, `started` (async), `dry-run` or `error`. |
| `flow-results` | JSON array of per-flow results: `name`, `status`, `passed`, `attempt`, `latest`, `runId`, `device`, `durationSeconds`, `errors`, `url`. |
| `results-file` | Path to the full JSON document written by the CLI. |

## Examples

**Upload once, run two suites on different devices**

```yaml
- id: smoke
  uses: testingbot/maestro-action@v1
  with:
    api-key: ${{ secrets.TESTINGBOT_KEY }}
    api-secret: ${{ secrets.TESTINGBOT_SECRET }}
    app-file: app.apk
    workspace: .maestro/smoke
    device: Pixel 9

- uses: testingbot/maestro-action@v1
  with:
    api-key: ${{ secrets.TESTINGBOT_KEY }}
    api-secret: ${{ secrets.TESTINGBOT_SECRET }}
    app-binary-id: ${{ steps.smoke.outputs.app-id }}
    workspace: .maestro/regression
    device-matrix: |
      Pixel 9:14
      Samsung Galaxy S24:14:real
```

**JUnit report and artifacts on failure**

```yaml
- uses: testingbot/maestro-action@v1
  with:
    api-key: ${{ secrets.TESTINGBOT_KEY }}
    api-secret: ${{ secrets.TESTINGBOT_SECRET }}
    app-file: app.ipa
    report: junit
    download-artifacts: failed
- uses: actions/upload-artifact@v4
  if: always()
  with:
    name: maestro-results
    path: |
      testingbot-reports
      testingbot-artifacts
```

**Fire and forget on pull requests**

```yaml
- uses: testingbot/maestro-action@v1
  with:
    api-key: ${{ secrets.TESTINGBOT_KEY }}
    api-secret: ${{ secrets.TESTINGBOT_SECRET }}
    app-file: app.apk
    async: true
```

Check on it later with `testingbot status --id <app-id> --wait` or in the dashboard.

## Requirements

Node.js 20 or newer on the runner (present on all GitHub-hosted runners) and `@testingbot/cli` 1.2.0 or newer, which the action installs with `npx`.

## License

MIT
