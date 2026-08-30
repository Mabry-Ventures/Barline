#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=script/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

MODE="${1:-}"
[[ -n "$MODE" ]] || barline_die "usage: ./script/ci.sh {fast|nonfocus|full|release|xcode27|soak} [--release] [--publish-status] [--xcode PATH]"
shift

PUBLISH_STATUS=false
XCODE_PATH=""
RELEASE_SOAK=false
while (($#)); do
    case "$1" in
        --publish-status) PUBLISH_STATUS=true ;;
        --release) RELEASE_SOAK=true ;;
        --xcode)
            (($# >= 2)) || barline_die "--xcode requires a path"
            XCODE_PATH="$2"
            shift
            ;;
        *) barline_die "unknown option: $1" ;;
    esac
    shift
done

if "$RELEASE_SOAK" && [[ "$MODE" != soak ]]; then
    barline_die "--release is supported only with soak mode"
fi

case "$MODE" in
    fast|nonfocus|full|release|xcode27|soak) ;;
    *) barline_die "unknown CI mode: $MODE" ;;
esac

ROOT="$(barline_repo_root)"
cd "$ROOT"
barline_require_command git
barline_require_command ruby

SHA="$(git rev-parse HEAD)"
DIRTY=false
[[ -z "$(git status --porcelain=v1)" ]] || DIRTY=true
STARTED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
ARTIFACT_DIR="$ROOT/.artifacts/ci/$SHA/$MODE-$STARTED_AT"
ARTIFACT_DIR="${ARTIFACT_DIR//:/-}"
mkdir -p "$ARTIFACT_DIR/logs" "$ARTIFACT_DIR/results"
# Keep runtime builds isolated to this exact CI invocation and outside the
# synchronized workspace, whose File Provider metadata is invalid signing
# input. Interactive gates intentionally reuse this root within the run.
BARLINE_RUN_ROOT="/private/tmp/barline-ci-$(id -u)-$SHA-$MODE-${STARTED_AT//:/-}"
export BARLINE_RUN_ROOT
COMMANDS_FILE="$ARTIFACT_DIR/commands.tsv"
FAILURES_FILE="$ARTIFACT_DIR/failures.txt"
: > "$COMMANDS_FILE"
: > "$FAILURES_FILE"
FAILURES=0
STATUS_CONTEXT="local/macos-arm64"
[[ "$MODE" == xcode27 ]] && STATUS_CONTEXT="local/macos27-beta"

DEVELOPER_PATH=""
if [[ "$MODE" != fast || -n "$XCODE_PATH" ]]; then
    [[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || barline_die "$MODE requires an Apple Silicon macOS host"
    DEVELOPER_PATH="$(barline_xcode_developer_dir "$XCODE_PATH")"
fi

command_string() {
    printf '%q ' "$@"
}

run_step() {
    local name="$1"
    shift
    local command_text log_file status
    command_text="$(command_string "$@")"
    log_file="$ARTIFACT_DIR/logs/${name//[^A-Za-z0-9_.-]/_}.log"
    printf '%s\t%s\n' "$name" "$command_text" >> "$COMMANDS_FILE"
    printf '\n==> %s\n' "$name"
    set +e
    "$@" > >(tee "$log_file") 2>&1
    status=$?
    set -e
    if ((status != 0)); then
        printf '%s (exit %d)\n' "$name" "$status" | tee -a "$FAILURES_FILE" >&2
        FAILURES=$((FAILURES + 1))
    fi
}

require_gate_script() {
    local path="$1"
    if [[ ! -x "$path" ]]; then
        printf 'required gate absent or not executable: %s\n' "$path" | tee -a "$FAILURES_FILE" >&2
        FAILURES=$((FAILURES + 1))
        return
    fi
    run_step "$(basename "$path" .sh)" "$path"
}

report_developer_tools_block() {
    printf 'BLOCKED: Xcode test-plan execution requires Developer Tools automation mode. Enabling it requires administrator authorization.\n' >&2
    return 2
}

publish_commit_status() {
    local state="$1" description="$2"
    gh api --method POST "repos/{owner}/{repo}/statuses/$SHA" \
        -f state="$state" \
        -f context="$STATUS_CONTEXT" \
        -f description="$description" >/dev/null
}

write_summary() {
    local ended_at macos_version hardware_model xcode_version swift_version coverage_path
    ended_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    macos_version="$(sw_vers -productVersion 2>/dev/null || printf unavailable) ($(sw_vers -buildVersion 2>/dev/null || printf unavailable))"
    hardware_model="$(sysctl -n hw.model 2>/dev/null || printf unavailable)"
    if [[ -n "$DEVELOPER_PATH" ]]; then
        xcode_version="$(DEVELOPER_DIR="$DEVELOPER_PATH" xcodebuild -version 2>/dev/null | tr '\n' ' ')"
        swift_version="$(DEVELOPER_DIR="$DEVELOPER_PATH" xcrun swift --version 2>/dev/null | head -1)"
    else
        xcode_version="$(xcodebuild -version 2>/dev/null | tr '\n' ' ' || printf unavailable)"
        swift_version="$(swift --version 2>/dev/null | head -1 || printf unavailable)"
    fi
    coverage_path="$(swift test --package-path BarlineCore --show-codecov-path 2>/dev/null || true)"
    STARTED_AT_VALUE="$STARTED_AT" ENDED_AT_VALUE="$ended_at" SHA_VALUE="$SHA" DIRTY_VALUE="$DIRTY" \
    MODE_VALUE="$MODE" MACOS_VALUE="$macos_version" ARCH_VALUE="$(uname -m)" MODEL_VALUE="$hardware_model" \
    XCODE_VALUE="$xcode_version" SWIFT_VALUE="$swift_version" ARTIFACT_VALUE="$ARTIFACT_DIR" \
    COMMANDS_VALUE="$COMMANDS_FILE" FAILURES_VALUE="$FAILURES_FILE" COVERAGE_VALUE="$coverage_path" \
    ruby -rjson -e '
      commands = File.readlines(ENV.fetch("COMMANDS_VALUE"), chomp: true).map do |line|
        name, command = line.split("\t", 2)
        {name: name, command: command}
      end
      failures = File.readlines(ENV.fetch("FAILURES_VALUE"), chomp: true)
      coverage_path = ENV.fetch("COVERAGE_VALUE")
      coverage = {status: "unavailable", report: coverage_path}
      if !coverage_path.empty? && File.file?(coverage_path)
        begin
          totals = JSON.parse(File.read(coverage_path)).dig("data", 0, "totals") || {}
          coverage = {status: "measured", report: coverage_path, lines_percent: totals.dig("lines", "percent"), functions_percent: totals.dig("functions", "percent")}
        rescue JSON::ParserError
          coverage = {status: "invalid-report", report: coverage_path}
        end
      end
      test_counts = {}
      Dir.glob(File.join(ENV.fetch("ARTIFACT_VALUE"), "logs", "*.log")).each do |path|
        matches = File.read(path).scan(/(?:Executed|Test run with)\s+(\d+)\s+tests?/)
        test_counts[File.basename(path)] = matches.flatten.map(&:to_i).max if matches.any?
      end
      summary = {
        commit_sha: ENV.fetch("SHA_VALUE"), dirty: ENV.fetch("DIRTY_VALUE") == "true",
        mode: ENV.fetch("MODE_VALUE"), started_at: ENV.fetch("STARTED_AT_VALUE"), ended_at: ENV.fetch("ENDED_AT_VALUE"),
        host: {macos: ENV.fetch("MACOS_VALUE"), architecture: ENV.fetch("ARCH_VALUE"), model: ENV.fetch("MODEL_VALUE")},
        toolchain: {xcode: ENV.fetch("XCODE_VALUE"), swift: ENV.fetch("SWIFT_VALUE")},
        commands: commands, test_counts: test_counts, failures: failures, coverage: coverage,
        artifact_paths: [ENV.fetch("ARTIFACT_VALUE")]
      }
      File.write(File.join(ENV.fetch("ARTIFACT_VALUE"), "summary.json"), JSON.pretty_generate(summary) + "\n")
    '
}

trap write_summary EXIT

if "$PUBLISH_STATUS"; then
    [[ "$MODE" == full || "$MODE" == xcode27 ]] || barline_die "--publish-status is supported only for full and xcode27"
    [[ "$DIRTY" == false ]] || barline_die "status publishing requires a clean working tree"
    barline_require_command gh
    gh auth status >/dev/null
    publish_commit_status pending "$MODE local validation started"
fi

run_fast() {
    barline_require_command swiftformat
    barline_require_command swiftlint
    run_step "dependency-resolution" swift package --package-path BarlineCore resolve
    run_step "dependency-lock-clean" git diff --exit-code -- \
        Barline.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved \
        BarlineCore/Package.resolved
    changed_swift=()
    while IFS= read -r -d '' file; do changed_swift+=("$file"); done < <(
        git diff --name-only -z --diff-filter=ACMR HEAD -- '*.swift'
        git ls-files --others --exclude-standard -z -- '*.swift'
    )
    if ((${#changed_swift[@]})); then
        run_step "swiftformat" swiftformat --lint --swift-version 6.0 "${changed_swift[@]}"
    else
        printf 'Format check: no changed Swift files.\n'
    fi
    run_step "swiftlint" swiftlint lint --strict --config .swiftlint.yml
    run_step "core-build" swift build --package-path BarlineCore
    run_step "core-tests" swift test --package-path BarlineCore --enable-code-coverage
    run_step "repository-hygiene" ./script/ci/repo_hygiene.sh
    if [[ "$(uname -s)" == Darwin ]]; then
        run_step "project-resolution" env DEVELOPER_DIR="${DEVELOPER_PATH:-$(xcode-select -p)}" xcodebuild \
            -resolvePackageDependencies -project Barline.xcodeproj -scheme Barline
        run_step "project-list" env DEVELOPER_DIR="${DEVELOPER_PATH:-$(xcode-select -p)}" xcodebuild \
            -list -json -project Barline.xcodeproj
        plist_files=()
        while IFS= read -r -d '' file; do plist_files+=("$file"); done < <(
            find Barline BarlineMenuService BarlineIntents -name '*.plist' -print0
        )
        run_step "plist-validation" plutil -lint "${plist_files[@]}"
    fi
}

run_full() {
    run_nonfocus
    require_gate_script ./script/test-xpc-interruption.sh
    require_gate_script ./script/test-ui-smoke.sh
    require_gate_script ./script/test-performance-smoke.sh
    require_gate_script ./script/test-reopen-burst.sh
}

run_nonfocus() {
    run_fast
    run_step "architecture-firewall" ./script/ci/architecture_firewall.sh
    run_step "debug-build" env DEVELOPER_DIR="$DEVELOPER_PATH" xcodebuild \
        -project Barline.xcodeproj -scheme Barline -configuration Debug \
        -destination 'platform=macOS,arch=arm64' -resultBundlePath "$ARTIFACT_DIR/results/debug.xcresult" \
        CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
    run_step "release-build" env DEVELOPER_DIR="$DEVELOPER_PATH" xcodebuild \
        -project Barline.xcodeproj -scheme Barline -configuration Release \
        -destination 'platform=macOS,arch=arm64' -resultBundlePath "$ARTIFACT_DIR/results/release.xcresult" \
        CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
    run_step "static-analysis" env DEVELOPER_DIR="$DEVELOPER_PATH" xcodebuild \
        -project Barline.xcodeproj -scheme Barline -configuration Debug \
        -destination 'platform=macOS,arch=arm64' -resultBundlePath "$ARTIFACT_DIR/results/analyze.xcresult" \
        CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO analyze
    run_step "test-plan-build" env DEVELOPER_DIR="$DEVELOPER_PATH" xcodebuild \
        -project Barline.xcodeproj -scheme Barline -testPlan Barline \
        -configuration Debug -destination 'platform=macOS,arch=arm64' \
        -derivedDataPath "$ARTIFACT_DIR/test-derived" \
        CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build-for-testing
    if /usr/sbin/DevToolsSecurity -status 2>&1 | /usr/bin/grep -qi 'enabled'; then
        run_step "test-plan-core" env DEVELOPER_DIR="$DEVELOPER_PATH" xcodebuild \
            -project Barline.xcodeproj -scheme Barline -testPlan Barline \
            -configuration Debug -destination 'platform=macOS,arch=arm64' \
            -derivedDataPath "$ARTIFACT_DIR/test-derived" \
            -resultBundlePath "$ARTIFACT_DIR/results/tests.xcresult" \
            -only-testing:BarlineTests -only-testing:BarlineIntegrationTests \
            CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO test-without-building
    else
        run_step "test-plan-core" report_developer_tools_block
    fi
    require_gate_script ./script/test-menu-bar-recovery.sh
    require_gate_script ./script/test-notch-overflow.sh
    require_gate_script ./script/test-fixtures.sh
    require_gate_script ./script/test-xcode-ui.sh
    require_gate_script ./script/test-accessibility.sh
    require_gate_script ./script/test-support-bundle-privacy.sh
}

case "$MODE" in
    fast)
        run_fast
        ;;
    nonfocus)
        run_nonfocus
        ;;
    full)
        run_full
        ;;
    release)
        run_full
        require_gate_script ./script/release.sh
        ;;
    xcode27)
        [[ -n "$XCODE_PATH" ]] || barline_die "xcode27 requires --xcode with an explicit Xcode 27 path"
        xcode_output="$(DEVELOPER_DIR="$DEVELOPER_PATH" xcodebuild -version)"
        [[ "$xcode_output" == Xcode\ 27* ]] || barline_die "selected toolchain is not Xcode 27: $xcode_output"
        run_full
        if [[ "$(sw_vers -productVersion)" != 27.* ]]; then
            printf 'macOS 27 runtime support NOT VERIFIED: this host is %s.\n' "$(sw_vers -productVersion)" | tee "$ARTIFACT_DIR/macos27-runtime-status.txt"
        fi
        ;;
    soak)
        if "$RELEASE_SOAK"; then
            run_step "test-soak-release" ./script/test-soak.sh --release
        else
            require_gate_script ./script/test-soak.sh
        fi
        ;;
esac

if "$PUBLISH_STATUS"; then
    if [[ "$(git rev-parse HEAD)" != "$SHA" ]]; then
        printf 'HEAD changed during validation; refusing success status\n' | tee -a "$FAILURES_FILE" >&2
        FAILURES=$((FAILURES + 1))
    fi
    if ((FAILURES)); then
        publish_commit_status failure "$MODE failed with $FAILURES gate failure(s)"
    else
        publish_commit_status success "$MODE passed on $(sw_vers -productVersion), $(xcodebuild -version | head -1)"
    fi
fi

if ((FAILURES)); then
    printf '\nCI %s failed with %d gate failure(s). Evidence: %s\n' "$MODE" "$FAILURES" "$ARTIFACT_DIR" >&2
    exit 1
fi

printf '\nCI %s passed. Evidence: %s\n' "$MODE" "$ARTIFACT_DIR"
