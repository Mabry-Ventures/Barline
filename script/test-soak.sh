#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=script/lib/identity.sh
source "$ROOT/script/lib/identity.sh"
MODE="${BARLINE_SOAK_MODE:-smoke}"
ITERATIONS="${BARLINE_SOAK_ITERATIONS:-10}"
DURATION_SECONDS="${BARLINE_SOAK_DURATION_SECONDS:-1800}"
SAMPLE_INTERVAL_SECONDS="${BARLINE_SOAK_SAMPLE_INTERVAL_SECONDS:-15}"
RSS_GROWTH_LIMIT_KB="${BARLINE_SOAK_RSS_GROWTH_LIMIT_KB:-131072}"
CACHE_GROWTH_LIMIT_KB="${BARLINE_SOAK_CACHE_GROWTH_LIMIT_KB:-65536}"
HARNESS_VALIDATION="${BARLINE_SOAK_HARNESS_VALIDATION:-0}"
PERFORMANCE_SAMPLES_PER_RUN=20

usage() {
    cat <<'EOF'
Usage: ./script/test-soak.sh [--smoke|--release]

Smoke mode is the short development gate. Release mode defaults to 1,800
seconds and writes exact-candidate resource evidence under .artifacts/soak/.
For harness validation only, BARLINE_SOAK_DURATION_SECONDS may reduce the run;
the resulting JSON records the requested duration and is not 30-minute proof.
EOF
}

while (($#)); do
    case "$1" in
        --smoke) MODE=smoke ;;
        --release) MODE=release ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
    shift
done

[[ "$MODE" == smoke || "$MODE" == release ]] || {
    printf 'error: BARLINE_SOAK_MODE must be smoke or release\n' >&2
    exit 2
}
[[ "$ITERATIONS" =~ ^[1-9][0-9]*$ ]] || {
    printf 'error: BARLINE_SOAK_ITERATIONS must be a positive integer\n' >&2
    exit 2
}
for numeric in "$DURATION_SECONDS" "$SAMPLE_INTERVAL_SECONDS" "$RSS_GROWTH_LIMIT_KB" "$CACHE_GROWTH_LIMIT_KB"; do
    [[ "$numeric" =~ ^[1-9][0-9]*$ ]] || {
        printf 'error: release soak duration, interval, and growth limits must be positive integers\n' >&2
        exit 2
    }
done
((DURATION_SECONDS <= 1800)) || {
    printf 'error: release soak is bounded to at most 1,800 seconds\n' >&2
    exit 2
}
[[ "$HARNESS_VALIDATION" == 0 || "$HARNESS_VALIDATION" == 1 ]] || {
    printf 'error: BARLINE_SOAK_HARNESS_VALIDATION must be 0 or 1\n' >&2
    exit 2
}
if [[ "$HARNESS_VALIDATION" == 1 && "$DURATION_SECONDS" == 1800 ]]; then
    printf 'error: harness validation must use a reduced duration and cannot produce release evidence\n' >&2
    exit 2
fi

cd "$ROOT"

run_core_cycle() {
    swift test --package-path BarlineCore \
        --filter 'BarlineCoreTests\.(StateCoordinatorTests|ProfileTests|DeterministicSearchIndexTests|SnapshotValidationTests)/'
}

if [[ "$MODE" == smoke ]]; then
    for ((iteration = 1; iteration <= ITERATIONS; iteration++)); do
        printf 'Soak smoke iteration %d/%d\n' "$iteration" "$ITERATIONS"
        run_core_cycle
    done
    ./script/test-xpc-interruption.sh
    ./script/test-performance-smoke.sh
    printf 'PASS: %d state/profile/search/snapshot cycles plus helper interruption and responsiveness probes completed\n' "$ITERATIONS"
    exit 0
fi

SHA="$(git rev-parse HEAD)"
if [[ "$HARNESS_VALIDATION" != 1 && -n "$(git status --porcelain=v1)" ]]; then
    printf 'error: release soak requires a clean exact candidate\n' >&2
    exit 1
fi

STARTED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
START_EPOCH="$(date +%s)"
STAMP="${STARTED_AT//:/-}"
ARTIFACT_DIR="$ROOT/.artifacts/soak/$SHA/release-$STAMP"
CSV="$ARTIFACT_DIR/resources.csv"
CORE_LOG="$ARTIFACT_DIR/core-cycles.log"
XPC_LOG="$ARTIFACT_DIR/xpc-cycles.log"
PERFORMANCE_LOG="$ARTIFACT_DIR/performance-cycles.log"
SUMMARY="$ARTIFACT_DIR/summary.json"
PREFERENCE_DOMAIN=""
PREFERENCE_KEY="UseBarlineShelf"
ORIGINAL_PREFERENCE="__missing__"
CYCLES=0
XPC_CYCLES=0
PERFORMANCE_CYCLES=0
BUILD_CONFIGURATION=Release
PRODUCTION_PROBE=apple-event-reopen
XPC_RECOVERY_STRATEGY=same-process-apple-event-reopen
BASELINE_APP_PID=""

mkdir -p "$ARTIFACT_DIR"
PREFERENCE_DOMAIN="$(barline_resolve_app_bundle_identifier "$ROOT" Release)"
export BARLINE_APP_BUNDLE_IDENTIFIER="$PREFERENCE_DOMAIN"
export BARLINE_BUILD_CONFIGURATION=Release
CACHE_ROOT="$(xcrun swift -e 'import Foundation; print(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].path)' 2>/dev/null)"
[[ -n "$CACHE_ROOT" && "$CACHE_ROOT" == /* ]] || {
    printf 'error: user cache root is unavailable or invalid\n' >&2
    exit 1
}
APP_CACHE_DIR="$CACHE_ROOT/$PREFERENCE_DOMAIN"
printf 'timestamp_utc,elapsed_seconds,cycle,app_pid,helper_pid,app_rss_kb,helper_rss_kb,total_rss_kb,app_cpu_percent,helper_cpu_percent,cache_kb\n' > "$CSV"
: > "$CORE_LOG"
: > "$XPC_LOG"
: > "$PERFORMANCE_LOG"

if ORIGINAL_PREFERENCE_VALUE="$(/usr/bin/defaults read "$PREFERENCE_DOMAIN" "$PREFERENCE_KEY" 2>/dev/null)"; then
    ORIGINAL_PREFERENCE="$ORIGINAL_PREFERENCE_VALUE"
fi

cache_size_kb() {
    local size=0
    if [[ -d "$APP_CACHE_DIR" ]]; then
        size="$(/usr/bin/du -sk "$APP_CACHE_DIR" 2>/dev/null | /usr/bin/awk '{print $1}')"
    fi
    printf '%d\n' "${size:-0}"
}

process_value() {
    local pid="$1" field="$2"
    if [[ -z "$pid" ]]; then
        printf '0\n'
        return
    fi
    /bin/ps -p "$pid" -o "$field"= 2>/dev/null | /usr/bin/awk '{$1=$1; print}' | /usr/bin/head -1
}

sample_resources() {
    local now elapsed app_pid helper_pid app_rss helper_rss app_cpu helper_cpu cache
    now="$(date +%s)"
    elapsed=$((now - START_EPOCH))
    app_pid="$(/usr/bin/pgrep -x Barline | /usr/bin/head -1 || true)"
    helper_pid="$(/usr/bin/pgrep -x BarlineMenuService | /usr/bin/head -1 || true)"
    [[ -n "$app_pid" ]] || {
        printf 'error: Barline exited during release soak\n' >&2
        return 1
    }
    if [[ -n "$BASELINE_APP_PID" && "$app_pid" != "$BASELINE_APP_PID" ]]; then
        printf 'error: Barline app PID changed during release soak; RSS continuity is invalid\n' >&2
        return 1
    fi
    app_rss="$(process_value "$app_pid" rss)"
    helper_rss="$(process_value "$helper_pid" rss)"
    app_cpu="$(process_value "$app_pid" %cpu)"
    helper_cpu="$(process_value "$helper_pid" %cpu)"
    cache="$(cache_size_kb)"
    printf '%s,%d,%d,%s,%s,%s,%s,%d,%s,%s,%d\n' \
        "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$elapsed" "$CYCLES" "$app_pid" "${helper_pid:-0}" \
        "${app_rss:-0}" "${helper_rss:-0}" "$(( ${app_rss:-0} + ${helper_rss:-0} ))" \
        "${app_cpu:-0}" "${helper_cpu:-0}" "$cache" >> "$CSV"
}

restore_preference() {
    if [[ "$ORIGINAL_PREFERENCE" == __missing__ ]]; then
        /usr/bin/defaults delete "$PREFERENCE_DOMAIN" "$PREFERENCE_KEY" >/dev/null 2>&1 || true
    elif [[ "$ORIGINAL_PREFERENCE" == 1 ]]; then
        /usr/bin/defaults write "$PREFERENCE_DOMAIN" "$PREFERENCE_KEY" -bool true
    else
        /usr/bin/defaults write "$PREFERENCE_DOMAIN" "$PREFERENCE_KEY" -bool false
    fi
}

write_summary() {
    local exit_code="$1" ended_at end_sha dirty
    ended_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    end_sha="$(git rev-parse HEAD)"
    dirty=false
    [[ -z "$(git status --porcelain=v1)" ]] || dirty=true
    # Ruby code intentionally owns interpolation.
    # shellcheck disable=SC2016
    SHA_VALUE="$SHA" END_SHA_VALUE="$end_sha" DIRTY_VALUE="$dirty" HARNESS_VALUE="$HARNESS_VALIDATION" START_VALUE="$STARTED_AT" END_VALUE="$ended_at" \
    DURATION_VALUE="$DURATION_SECONDS" INTERVAL_VALUE="$SAMPLE_INTERVAL_SECONDS" CYCLES_VALUE="$CYCLES" \
    XPC_VALUE="$XPC_CYCLES" PERFORMANCE_VALUE="$PERFORMANCE_CYCLES" EXIT_VALUE="$exit_code" \
    PERFORMANCE_SAMPLES_VALUE="$PERFORMANCE_SAMPLES_PER_RUN" \
    RSS_LIMIT_VALUE="$RSS_GROWTH_LIMIT_KB" CACHE_LIMIT_VALUE="$CACHE_GROWTH_LIMIT_KB" CSV_VALUE="$CSV" \
    CORE_LOG_VALUE="$CORE_LOG" XPC_LOG_VALUE="$XPC_LOG" PERFORMANCE_LOG_VALUE="$PERFORMANCE_LOG" \
    SUMMARY_VALUE="$SUMMARY" ARTIFACT_VALUE="$ARTIFACT_DIR" \
    BUNDLE_ID_VALUE="$PREFERENCE_DOMAIN" CACHE_SCOPE_VALUE="user-caches/$PREFERENCE_DOMAIN" \
    CONFIGURATION_VALUE="$BUILD_CONFIGURATION" PROBE_VALUE="$PRODUCTION_PROBE" XPC_STRATEGY_VALUE="$XPC_RECOVERY_STRATEGY" \
    ruby -rcsv -rjson -e '
      rows = CSV.read(ENV.fetch("CSV_VALUE"), headers: true)
      integers = ->(name) { rows.map { |row| row[name].to_i } }
      app_rss = integers.call("app_rss_kb")
      helper_rss = integers.call("helper_rss_kb")
      total_rss = integers.call("total_rss_kb")
      helper_generations = rows.map { |row| row["helper_pid"].to_i }.reject(&:zero?).uniq.length
      cache = integers.call("cache_kb")
      app_cpu = rows.map { |row| row["app_cpu_percent"].to_f }
      helper_cpu = rows.map { |row| row["helper_cpu_percent"].to_f }
      initial_app_rss = app_rss.first || 0
      final_app_rss = app_rss.last || 0
      initial_cache = cache.first || 0
      final_cache = cache.last || 0
      app_rss_growth = final_app_rss - initial_app_rss
      cache_growth = final_cache - initial_cache
      exact = ENV.fetch("SHA_VALUE") == ENV.fetch("END_SHA_VALUE") && ENV.fetch("DIRTY_VALUE") == "false"
      harness = ENV.fetch("HARNESS_VALUE") == "1"
      actual_duration = rows.empty? ? 0 : rows[-1]["elapsed_seconds"].to_i
      complete_duration = ENV.fetch("DURATION_VALUE").to_i == 1800 && actual_duration >= 1800
      performance_results = File.read(ENV.fetch("PERFORMANCE_LOG_VALUE")).scan(
        /RESULT samples=(\d+) timeouts=(\d+) median_ms=([0-9.]+) p95_ms=([0-9.]+) max_ms=([0-9.]+) recovery_p95_ms=([0-9.]+) recovery_max_ms=([0-9.]+) recovery_succeeded=(true|false).*verdict=(\w+)/
      )
      performance_samples = File.read(ENV.fetch("PERFORMANCE_LOG_VALUE")).scan(
        /^cycle=\d+ status=OK latency_ms=([0-9.]+) recovery_ms=([0-9.]+)$/
      )
      presentation_latencies = performance_samples.map { |sample| sample[0].to_f }.sort
      recovery_latencies = performance_samples.map { |sample| sample[1].to_f }.sort
      percentile = lambda do |values, fraction|
        next 0 if values.empty?
        rank = [(fraction * values.length).ceil, 1].max
        values[[rank - 1, values.length - 1].min]
      end
      presentation_aggregate_p95 = percentile.call(presentation_latencies, 0.95)
      recovery_aggregate_p95 = percentile.call(recovery_latencies, 0.95)
      expected_performance_samples = ENV.fetch("PERFORMANCE_VALUE").to_i *
        ENV.fetch("PERFORMANCE_SAMPLES_VALUE").to_i
      cycle_counts = ["CYCLES_VALUE", "XPC_VALUE", "PERFORMANCE_VALUE"].map { |name| ENV.fetch(name).to_i }
      shelf_workload_passed = performance_results.length == ENV.fetch("PERFORMANCE_VALUE").to_i &&
        performance_results.all? do |result|
          result[0].to_i == ENV.fetch("PERFORMANCE_SAMPLES_VALUE").to_i &&
            result[1].to_i == 0 &&
            result[7] == "true" &&
            result[8] == "PASS"
        end && presentation_latencies.length == expected_performance_samples &&
        recovery_latencies.length == expected_performance_samples &&
        presentation_aggregate_p95 <= 250 &&
        recovery_latencies.all? { |latency| latency <= 5_000 }
      guards = {
        exact_candidate: exact,
        workload_cycles_completed: cycle_counts.all?(&:positive?) && cycle_counts.uniq.length == 1,
        production_probe_passed: shelf_workload_passed,
        release_execution_path: ENV.fetch("CONFIGURATION_VALUE") == "Release" &&
          ENV.fetch("PROBE_VALUE") == "apple-event-reopen" &&
          ENV.fetch("XPC_STRATEGY_VALUE") == "same-process-apple-event-reopen",
        app_rss_growth_within_limit: app_rss_growth <= ENV.fetch("RSS_LIMIT_VALUE").to_i,
        cache_growth_within_limit: cache_growth <= ENV.fetch("CACHE_LIMIT_VALUE").to_i,
        sufficient_samples: rows.length >= (complete_duration ? 10 : 2)
      }
      operational = ENV.fetch("EXIT_VALUE").to_i == 0 && guards.reject { |name, _| name == :exact_candidate }.values.all?
      candidate_pass = operational && guards[:exact_candidate] && complete_duration && !harness
      document = {
        schema_version: 3,
        mode: "release",
        build_configuration: ENV.fetch("CONFIGURATION_VALUE"),
        production_probe: ENV.fetch("PROBE_VALUE"),
        xpc_recovery_strategy: ENV.fetch("XPC_STRATEGY_VALUE"),
        app_bundle_identifier: ENV.fetch("BUNDLE_ID_VALUE"),
        sampled_cache_scope: ENV.fetch("CACHE_SCOPE_VALUE"),
        commit_sha: ENV.fetch("SHA_VALUE"),
        end_commit_sha: ENV.fetch("END_SHA_VALUE"),
        clean_at_end: ENV.fetch("DIRTY_VALUE") == "false",
        started_at: ENV.fetch("START_VALUE"), ended_at: ENV.fetch("END_VALUE"),
        requested_duration_seconds: ENV.fetch("DURATION_VALUE").to_i,
        actual_duration_seconds: actual_duration,
        release_duration_complete: complete_duration,
        harness_validation: harness,
        candidate_evidence: candidate_pass,
        sample_interval_seconds: ENV.fetch("INTERVAL_VALUE").to_i,
        performance_samples_per_run: ENV.fetch("PERFORMANCE_SAMPLES_VALUE").to_i,
        cycles: {core: ENV.fetch("CYCLES_VALUE").to_i, xpc_restart: ENV.fetch("XPC_VALUE").to_i, production_probe: ENV.fetch("PERFORMANCE_VALUE").to_i},
        app_process_continuity: true,
        app_rss_growth_guard_enforced: true,
        resources: {
          samples: rows.length,
          app_rss_kb: {initial: initial_app_rss, final: final_app_rss, minimum: app_rss.min || 0, maximum: app_rss.max || 0, growth: app_rss_growth, growth_limit: ENV.fetch("RSS_LIMIT_VALUE").to_i, continuity_eligible: true},
          helper_rss_kb: {minimum: helper_rss.min || 0, maximum: helper_rss.max || 0, process_generations: helper_generations, continuity_eligible: false, growth_guard_enforced: false, note: "helper process is intentionally replaced during XPC recovery cycles"},
          total_rss_kb: {minimum: total_rss.min || 0, maximum: total_rss.max || 0, continuity_eligible: false, growth_guard_enforced: false},
          cache_kb: {initial: initial_cache, final: final_cache, minimum: cache.min || 0, maximum: cache.max || 0, growth: cache_growth, growth_limit: ENV.fetch("CACHE_LIMIT_VALUE").to_i},
          cpu_percent: {
            app_average: app_cpu.empty? ? 0 : app_cpu.sum / app_cpu.length,
            app_maximum: app_cpu.max || 0,
            helper_average: helper_cpu.empty? ? 0 : helper_cpu.sum / helper_cpu.length,
            helper_maximum: helper_cpu.max || 0
          }
        },
        production_probe_performance: {
          runs: performance_results.length,
          samples: performance_results.sum { |result| result[0].to_i },
          timeouts: performance_results.sum { |result| result[1].to_i },
          presentation: {
            aggregate_p95_ms: presentation_aggregate_p95,
            maximum_window_p95_ms: performance_results.map { |result| result[3].to_f }.max || 0,
            maximum_latency_ms: presentation_latencies.max || 0,
            feedback_budget_ms: 250
          },
          recovery: {
            aggregate_p95_ms: recovery_aggregate_p95,
            maximum_window_p95_ms: performance_results.map { |result| result[5].to_f }.max || 0,
            maximum_latency_ms: recovery_latencies.max || 0,
            timeout_ms: 5_000,
            all_succeeded: performance_results.all? { |result| result[7] == "true" }
          },
          all_passed: shelf_workload_passed
        },
        host: {
          macos: `sw_vers -productVersion`.strip,
          macos_build: `sw_vers -buildVersion`.strip,
          architecture: `uname -m`.strip,
          hardware_model: `sysctl -n hw.model`.strip
        },
        toolchain: {
          xcode: `xcodebuild -version`.lines.map(&:strip).join(" "),
          swift: `xcrun swift --version 2>&1`.lines.first.to_s.strip
        },
        guards: guards,
        command_exit_code: ENV.fetch("EXIT_VALUE").to_i,
        verdict: candidate_pass ? "PASS" : (operational && harness ? "HARNESS_PASS" : "FAIL"),
        command: "./script/ci.sh soak --release",
        artifacts: {
          resources_csv: ENV.fetch("CSV_VALUE"),
          core_log: ENV.fetch("CORE_LOG_VALUE"),
          xpc_log: ENV.fetch("XPC_LOG_VALUE"),
          performance_log: ENV.fetch("PERFORMANCE_LOG_VALUE"),
          directory: ENV.fetch("ARTIFACT_VALUE")
        }
      }
      File.write(ENV.fetch("SUMMARY_VALUE"), JSON.pretty_generate(document) + "\n")
      exit(["PASS", "HARNESS_PASS"].include?(document[:verdict]) ? 0 : 1)
    '
}

finish() {
    local exit_code=$?
    trap - EXIT
    /usr/bin/pkill -x Barline >/dev/null 2>&1 || true
    /usr/bin/pkill -x BarlineMenuService >/dev/null 2>&1 || true
    restore_preference
    if ! write_summary "$exit_code"; then
        exit_code=1
    fi
    printf 'Release soak evidence: %s\n' "$SUMMARY"
    exit "$exit_code"
}
trap finish EXIT

# Warm dependencies and build outside the timed interval.
swift build --package-path BarlineCore --configuration release >/dev/null
/usr/bin/defaults write "$PREFERENCE_DOMAIN" "$PREFERENCE_KEY" -bool true
"$ROOT/script/build_and_run.sh" --release --verify

runtime_ready=false
for _ in {1..80}; do
    ready_app_pid="$(/usr/bin/pgrep -x Barline | /usr/bin/head -1 || true)"
    ready_helper_pid="$(/usr/bin/pgrep -x BarlineMenuService | /usr/bin/head -1 || true)"
    ready_app_rss="$(process_value "$ready_app_pid" rss)"
    if [[ -n "$ready_helper_pid" && "${ready_app_rss:-0}" =~ ^[0-9]+$ ]] && ((ready_app_rss >= 10 * 1024)); then
        runtime_ready=true
        break
    fi
    /bin/sleep 0.25
done
"$runtime_ready" || {
    printf 'error: Barline and its helper did not reach a measurable steady-state baseline\n' >&2
    exit 1
}

START_EPOCH="$(date +%s)"
BASELINE_APP_PID="$ready_app_pid"
DEADLINE=$((START_EPOCH + DURATION_SECONDS))
sample_resources

while (( $(date +%s) < DEADLINE )); do
    cycle_started="$(date +%s)"
    CYCLES=$((CYCLES + 1))
    printf 'Release soak cycle %d\n' "$CYCLES" | tee -a "$CORE_LOG"
    swift test --package-path BarlineCore --configuration release \
        --filter 'BarlineCoreTests\.(StateCoordinatorTests|ProfileTests|DeterministicSearchIndexTests|SnapshotValidationTests)/' \
        2>&1 | tee -a "$CORE_LOG"
    ./script/test-xpc-interruption.sh --reuse-running --recovery-probe apple-event-reopen 2>&1 | tee -a "$XPC_LOG"
    XPC_CYCLES=$((XPC_CYCLES + 1))
    BARLINE_PERFORMANCE_CYCLES="$PERFORMANCE_SAMPLES_PER_RUN" BARLINE_PERFORMANCE_WARMUPS=1 \
        BARLINE_PERFORMANCE_ENFORCE_BUDGET=0 \
        ./script/test-performance-smoke.sh --reuse-running --probe apple-event-reopen --output "$PERFORMANCE_LOG"
    PERFORMANCE_CYCLES=$((PERFORMANCE_CYCLES + 1))
    sample_resources
    now="$(date +%s)"
    next_sample=$((cycle_started + SAMPLE_INTERVAL_SECONDS))
    if ((now < next_sample && next_sample < DEADLINE)); then
        /bin/sleep $((next_sample - now))
    fi
done

sample_resources
[[ "$(git rev-parse HEAD)" == "$SHA" ]] || {
    printf 'error: candidate changed during release soak\n' >&2
    exit 1
}
if [[ "$HARNESS_VALIDATION" != 1 && -n "$(git status --porcelain=v1)" ]]; then
    printf 'error: release candidate became dirty during soak\n' >&2
    exit 1
fi

printf 'PASS: release soak completed %d Core, %d same-process XPC recovery, and %d production reopen-response cycles\n' \
    "$CYCLES" "$XPC_CYCLES" "$PERFORMANCE_CYCLES"
