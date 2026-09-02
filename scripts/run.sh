#!/usr/bin/env bash
# Builds and runs `testingbot maestro` from the action inputs, then turns the
# CLI's JSON results into step outputs. Exit codes follow the CLI: 0 passed,
# 2 tests failed, 1 CLI/infrastructure error.
set -euo pipefail

is_true() { [[ "${1:-}" =~ ^([Tt]rue|TRUE|1|yes|on)$ ]]; }

# Splits a multi-line or comma-separated input into lines, trimming blanks.
split_list() {
  printf '%s' "${1:-}" | tr ',' '\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -v '^$' || true
}

# Multi-line KEY=VALUE input → one line per entry (values may contain commas).
split_lines() {
  printf '%s' "${1:-}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -v '^$' || true
}

if [[ -z "${INPUT_APP_FILE:-}" && -z "${INPUT_APP_BINARY_ID:-}" ]]; then
  echo "::error::Either app-file or app-binary-id is required."
  exit 1
fi

RESULTS_FILE="${RUNNER_TEMP:-/tmp}/testingbot-maestro-results.json"
rm -f "$RESULTS_FILE"

args=(maestro)

if [[ -n "${INPUT_APP_BINARY_ID:-}" ]]; then
  args+=(--app-binary-id "$INPUT_APP_BINARY_ID")
else
  args+=(--app "$INPUT_APP_FILE")
fi

# Flows: every non-empty line of `workspace` is a path, directory or glob.
while IFS= read -r flow; do args+=("$flow"); done < <(split_lines "$INPUT_WORKSPACE")

args+=(--api-key "$INPUT_API_KEY" --api-secret "$INPUT_API_SECRET")
args+=(--json-file --json-file-name "$RESULTS_FILE")

# Run name: explicit input, else PR title, else first line of the commit message.
name="${INPUT_NAME:-}"
if [[ -z "$name" && -n "${PR_TITLE:-}" ]]; then name="$PR_TITLE"; fi
if [[ -z "$name" && -n "${COMMIT_MESSAGE:-}" ]]; then name="${COMMIT_MESSAGE%%$'\n'*}"; fi
[[ -n "$name" ]] && args+=(--name "$name")

[[ -n "${INPUT_DEVICE:-}" ]] && args+=(--device "$INPUT_DEVICE")
[[ -n "${INPUT_DEVICE_VERSION:-}" ]] && args+=(--deviceVersion "$INPUT_DEVICE_VERSION")
[[ -n "${INPUT_PLATFORM:-}" ]] && args+=(--platform "$INPUT_PLATFORM")
is_true "${INPUT_REAL_DEVICE:-}" && args+=(--real-device)
is_true "${INPUT_GOOGLE_PLAY:-}" && args+=(--google-play)
[[ -n "${INPUT_DEVICE_LOCALE:-}" ]] && args+=(--device-locale "$INPUT_DEVICE_LOCALE")
[[ -n "${INPUT_TIMEZONE:-}" ]] && args+=(--timezone "$INPUT_TIMEZONE")
[[ -n "${INPUT_ORIENTATION:-}" ]] && args+=(--orientation "$INPUT_ORIENTATION")
[[ -n "${INPUT_INCLUDE_TAGS:-}" ]] && args+=(--include-tags "$INPUT_INCLUDE_TAGS")
[[ -n "${INPUT_EXCLUDE_TAGS:-}" ]] && args+=(--exclude-tags "$INPUT_EXCLUDE_TAGS")
[[ -n "${INPUT_EXCLUDE_FLOWS:-}" ]] && args+=(--exclude-flows "$INPUT_EXCLUDE_FLOWS")
[[ -n "${INPUT_GROUPS:-}" ]] && args+=(--groups "$INPUT_GROUPS")
[[ -n "${INPUT_MAESTRO_VERSION:-}" ]] && args+=(--maestro-version "$INPUT_MAESTRO_VERSION")
[[ -n "${INPUT_SHARD_SPLIT:-}" ]] && args+=(--shard-split "$INPUT_SHARD_SPLIT")
[[ -n "${INPUT_RETRY:-}" && "${INPUT_RETRY}" != "0" ]] && args+=(--retry "$INPUT_RETRY")

while IFS= read -r cell; do args+=(--device-matrix "$cell"); done < <(split_list "${INPUT_DEVICE_MATRIX:-}")
while IFS= read -r kv; do args+=(--env "$kv"); done < <(split_lines "${INPUT_ENV:-}")
while IFS= read -r kv; do args+=(--metadata "$kv"); done < <(split_lines "${INPUT_METADATA:-}")
while IFS= read -r app; do args+=(--other-app "$app"); done < <(split_lines "${INPUT_OTHER_APP:-}")

if [[ -n "${INPUT_REPORT:-}" ]]; then
  args+=(--report "$INPUT_REPORT" --report-output-dir "$INPUT_REPORT_OUTPUT_DIR")
fi
if [[ -n "${INPUT_DOWNLOAD_ARTIFACTS:-}" ]]; then
  args+=(--download-artifacts "$INPUT_DOWNLOAD_ARTIFACTS" --artifacts-output-dir "$INPUT_ARTIFACTS_OUTPUT_DIR")
fi

# CI metadata from the GitHub context. PR events expose the head commit and
# branch on the event payload; pushes use GITHUB_SHA / GITHUB_REF_NAME.
sha="${PR_HEAD_SHA:-${GITHUB_SHA:-}}"
branch="${PR_HEAD_REF:-${GITHUB_REF_NAME:-}}"
repo="${GITHUB_REPOSITORY:-}"
[[ -n "$sha" ]] && args+=(--commit-sha "$sha")
[[ -n "$branch" ]] && args+=(--branch "$branch")
if [[ -n "$repo" ]]; then
  args+=(--repo-owner "${repo%%/*}" --repo-name "${repo##*/}")
fi
[[ -n "${PR_NUMBER:-}" ]] && args+=(--pull-request-id "$PR_NUMBER")
[[ -n "${PR_URL:-}" ]] && args+=(--pr-url "$PR_URL")

is_true "${INPUT_ASYNC:-}" && args+=(--async)
is_true "${INPUT_DRY_RUN:-}" && args+=(--dry-run)

if [[ -n "${INPUT_EXTRA_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  extra=($INPUT_EXTRA_ARGS)
  args+=("${extra[@]}")
fi

# TESTINGBOT_CLI_COMMAND lets the action's own tests run an unpublished CLI build.
cli="${TESTINGBOT_CLI_COMMAND:-npx --yes @testingbot/cli@${INPUT_CLI_VERSION:-latest}}"

# Log the command with credentials redacted (the values after --api-key/--api-secret).
display=()
redact_next=false
for arg in "${args[@]}"; do
  if $redact_next; then display+=("***"); redact_next=false; continue; fi
  [[ "$arg" == "--api-key" || "$arg" == "--api-secret" ]] && redact_next=true
  display+=("$arg")
done
echo "::group::testingbot ${display[*]}"
echo "Node $(node --version)"
echo "::endgroup::"

set +e
if is_true "${INPUT_ASYNC:-}" || is_true "${INPUT_DRY_RUN:-}"; then
  $cli "${args[@]}"
else
  timeout_min="${INPUT_TIMEOUT:-60}"
  if command -v timeout >/dev/null 2>&1; then
    timeout --signal=INT --kill-after=30s "$((timeout_min * 60))s" $cli "${args[@]}"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout --signal=INT --kill-after=30s "$((timeout_min * 60))s" $cli "${args[@]}"
  else
    $cli "${args[@]}"
  fi
fi
cli_exit=$?
set -e

if [[ $cli_exit -eq 124 ]]; then
  echo "::error::Timed out after ${INPUT_TIMEOUT:-60} minutes waiting for results; the runs were cancelled."
  exit 1
fi

if [[ ! -f "$RESULTS_FILE" ]]; then
  echo "::error::The CLI did not write a results file (exit code $cli_exit)."
  exit "${cli_exit:-1}"
fi

echo "results-file=$RESULTS_FILE" >> "$GITHUB_OUTPUT"

# Extract outputs with node (always present on GitHub runners; no jq needed).
node - "$RESULTS_FILE" "$GITHUB_OUTPUT" <<'NODE'
const fs = require('fs');
const [file, out] = process.argv.slice(2);
const doc = JSON.parse(fs.readFileSync(file, 'utf8'));
const flows = [];
for (const run of doc.runs ?? []) {
  for (const flow of run.flows ?? []) {
    flows.push({
      name: flow.name,
      status: flow.status,
      passed: flow.passed,
      attempt: flow.attempt,
      latest: flow.latest,
      runId: run.id,
      device: run.device,
      durationSeconds: flow.durationSeconds ?? null,
      errors: flow.errors ?? [],
      url: run.url ?? null,
    });
  }
}
const lines = [
  `app-id=${doc.appId ?? ''}`,
  `console-url=${doc.url ?? ''}`,
  `outcome=${doc.outcome ?? 'error'}`,
  `flow-results<<TB_EOF\n${JSON.stringify(flows)}\nTB_EOF`,
];
fs.appendFileSync(out, lines.join('\n') + '\n');

const summary = process.env.GITHUB_STEP_SUMMARY;
if (summary) {
  const icon = { passed: '✅', failed: '❌', started: '🚀', 'dry-run': '🧪', error: '⚠️' }[doc.outcome] ?? '❔';
  let md = `### ${icon} TestingBot Maestro: ${doc.outcome}\n\n`;
  if (doc.url) md += `[Open in the TestingBot dashboard](${doc.url})\n\n`;
  if (doc.error) md += `> ${doc.error}\n\n`;
  if (flows.length > 0) {
    md += '| Flow | Device | Result | Duration |\n|---|---|---|---|\n';
    for (const f of flows.filter((f) => f.latest)) {
      const device = f.device ? `${f.device.name}${f.device.version ? ` ${f.device.version}` : ''}` : '';
      const result = f.passed ? '✅ passed' : `❌ ${f.status.toLowerCase()}${f.errors[0] ? `: ${f.errors[0]}` : ''}`;
      md += `| ${f.name} | ${device} | ${result} | ${f.durationSeconds != null ? `${f.durationSeconds}s` : ''} |\n`;
    }
  }
  fs.appendFileSync(summary, md + '\n');
}
NODE

outcome=$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')).outcome ?? 'error')" "$RESULTS_FILE")
case "$outcome" in
  passed|started|dry-run) exit 0 ;;
  failed)
    echo "::error::One or more Maestro flows failed. See the step summary and the TestingBot dashboard."
    exit 2 ;;
  *)
    echo "::error::TestingBot CLI reported an error (exit code $cli_exit)."
    exit 1 ;;
esac
