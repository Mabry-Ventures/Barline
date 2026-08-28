#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${BARLINE_SOAK_MODE:-smoke}"
ITERATIONS="${BARLINE_SOAK_ITERATIONS:-10}"
DURATION_SECONDS="${BARLINE_SOAK_DURATION_SECONDS:-1800}"
SAMPLE_INTERVAL_SECONDS="${BARLINE_SOAK_SAMPLE_INTERVAL_SECONDS:-15}"
RSS_GROWTH_LIMIT_KB="${BARLINE_SOAK_RSS_GROWTH_LIMIT_KB:-131072}"
CACHE_GROWTH_LIMIT_KB="${BARLINE_SOAK_CACHE_GROWTH_LIMIT_KB:-65536}"
HARNESS_VALIDATION="${BARLINE_SOAK_HARNESS_VALIDATION:-0}"

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
PREFERENCE_DOMAIN="com.mabryventures.Barline"
PREFERENCE_KEY="UseBarlineShelf"
ORIGINAL_PREFERENCE="__missing__"
CYCLES=0
XPC_CYCLES=0
PERFORMANCE_CYCLES=0

mkdir -p "$ARTIFACT_DIR"
printf 'timestamp_utc,elapsed_seconds,cycle,app_pid,helper_pid,app_rss_kb,helper_rss_kb,total_rss_kb,app_cpu_percent,helper_cpu_percent,cache_kb\n' > "$CSV"
: > "$CORE_LOG"
: > "$XPC_LOG"
: > "$PERFORMANCE_LOG"

if ORIGINAL_PREFERENCE_VALUE="$(/usr/bin/defaults read "$PREFERENCE_DOMAIN" "$PREFERENCE_KEY" 2>/dev/null)"; then
    ORIGINAL_PREFERENCE="$ORIGINAL_PREFERENCE_VALUE"
fi

CACHE_ROOT="$(xcrun swift -e 'import Foundation; print(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].path)' 2>/dev/null)"

cache_size_kb() {
    local total=0 path size
    for path in "$CACHE_ROOT/com.mabryventures.Barline" "$CACHE_ROOT/Barline"; do
        if [[ -d "$path" ]]; then
            size="$(/usr/bin/du -sk "$path" 2>/dev/null | /usr/bin/awk '{print $1}')"
            total=$((total + ${size:-0}))
        fi
    done
    printf '%d\n' "$total"
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
    RSS_LIMIT_VALUE="$RSS_GROWTH_LIMIT_KB" CACHE_LIMIT_VALUE="$CACHE_GROWTH_LIMIT_KB" CSV_VALUE="$CSV" \
    CORE_LOG_VALUE="$CORE_LOG" XPC_LOG_VALUE="$XPC_LOG" PERFORMANCE_LOG_VALUE="$PERFORMANCE_LOG" \
    SUMMARY_VALUE="$SUMMARY" ARTIFACT_VALUE="$ARTIFACT_DIR" \
    ruby -rcsv -rjson -e '
      rows = CSV.read(ENV.fetch("CSV_VALUE"), headers: true)
      integers = ->(name) { rows.map { |row| row[name].to_i } }
      rss = integers.call("total_rss_kb")
      cache = integers.call("cache_kb")
      app_cpu = rows.map { |row| row["app_cpu_percent"].to_f }
      helper_cpu = rows.map { |row| row["helper_cpu_percent"].to_f }
      initial_rss = rss.first || 0
      final_rss = rss.last || 0
      initial_cache = cache.first || 0
      final_cache = cache.last || 0
      rss_growth = final_rss - initial_rss
      cache_growth = final_cache - initial_cache
      exact = ENV.fetch("SHA_VALUE") == ENV.fetch("END_SHA_VALUE") && ENV.fetch("DIRTY_VALUE") == "false"
      harness = ENV.fetch("HARNESS_VALUE") == "1"
      actual_duration = rows.empty? ? 0 : rows[-1]["elapsed_seconds"].to_i
      complete_duration = ENV.fetch("DURATION_VALUE").to_i == 1800 && actual_duration >= 1800
      performance_results = File.read(ENV.fetch("PERFORMANCE_LOG_VALUE")).scan(
        /RESULT samples=(\d+) timeouts=(\d+) median_ms=([0-9.]+) p95_ms=([0-9.]+) max_ms=([0-9.]+).*verdict=(\w+)/
      )
      cycle_counts = ["CYCLES_VALUE", "XPC_VALUE", "PERFORMANCE_VALUE"].map { |name| ENV.fetch(name).to_i }
      shelf_workload_passed = performance_results.length == ENV.fetch("PERFORMANCE_VALUE").to_i &&
        performance_results.all? { |result| result[0].to_i == 5 && result[1].to_i == 0 && result[5] == "PASS" }
      guards = {
        exact_candidate: exact,
        workload_cycles_completed: cycle_counts.all?(&:positive?) && cycle_counts.uniq.length == 1,
        shelf_workload_passed: shelf_workload_passed,
        rss_growth_within_limit: rss_growth <= ENV.fetch("RSS_LIMIT_VALUE").to_i,
        cache_growth_within_limit: cache_growth <= ENV.fetch("CACHE_LIMIT_VALUE").to_i,
        sufficient_samples: rows.length >= (complete_duration ? 10 : 2)
      }
      operational = ENV.fetch("EXIT_VALUE").to_i == 0 && guards.reject { |name, _| name == :exact_candidate }.values.all?
      candidate_pass = operational && guards[:exact_candidate] && complete_duration && !harness
      document = {
        schema_version: 1,
        mode: "release",
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
        cycles: {core: ENV.fetch("CYCLES_VALUE").to_i, xpc_restart: ENV.fetch("XPC_VALUE").to_i, shelf: ENV.fetch("PERFORMANCE_VALUE").to_i},
        resources: {
          samples: rows.length,
          rss_kb: {initial: initial_rss, final: final_rss, minimum: rss.min || 0, maximum: rss.max || 0, growth: rss_growth, growth_limit: ENV.fetch("RSS_LIMIT_VALUE").to_i},
          cache_kb: {initial: initial_cache, final: final_cache, minimum: cache.min || 0, maximum: cache.max || 0, growth: cache_growth, growth_limit: ENV.fetch("CACHE_LIMIT_VALUE").to_i},
          cpu_percent: {
            app_average: app_cpu.empty? ? 0 : app_cpu.sum / app_cpu.length,
            app_maximum: app_cpu.max || 0,
            helper_average: helper_cpu.empty? ? 0 : helper_cpu.sum / helper_cpu.length,
            helper_maximum: helper_cpu.max || 0
          }
        },
        shelf_performance: {
          runs: performance_results.length,
          samples: performance_results.sum { |result| result[0].to_i },
          timeouts: performance_results.sum { |result| result[1].to_i },
          maximum_p95_ms: performance_results.map { |result| result[3].to_f }.max || 0,
          maximum_latency_ms: performance_results.map { |result| result[4].to_f }.max || 0,
          all_passed: performance_results.all? { |result| result[5] == "PASS" }
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
    /usr/bin/pkill -x Barline >/dev/null 2>&1 || true
    /usr/bin/pkill -x BarlineMenuService >/dev/null 2>&1 || true
    restore_preference
    if ! write_summary "$exit_code"; then
        exit_code=1
    fi
    printf 'Release soak evidence: %s\n' "$SUMMARY"
    return "$exit_code"
}
trap finish EXIT

# Warm dependencies and build outside the timed interval.
swift build --package-path BarlineCore >/dev/null
/usr/bin/defaults write "$PREFERENCE_DOMAIN" "$PREFERENCE_KEY" -bool true
BARLINE_RUNTIME_SMOKE=1 "$ROOT/script/build_and_run.sh" --verify

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
DEADLINE=$((START_EPOCH + DURATION_SECONDS))
sample_resources

while (( $(date +%s) < DEADLINE )); do
    cycle_started="$(date +%s)"
    CYCLES=$((CYCLES + 1))
    printf 'Release soak cycle %d\n' "$CYCLES" | tee -a "$CORE_LOG"
    run_core_cycle 2>&1 | tee -a "$CORE_LOG"
    ./script/test-xpc-interruption.sh --reuse-running 2>&1 | tee -a "$XPC_LOG"
    XPC_CYCLES=$((XPC_CYCLES + 1))
    BARLINE_PERFORMANCE_CYCLES=5 BARLINE_PERFORMANCE_WARMUPS=1 \
        ./script/test-performance-smoke.sh --reuse-running --output "$PERFORMANCE_LOG"
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

printf 'PASS: release soak completed %d Core, %d XPC restart, and %d shelf cycles\n' \
    "$CYCLES" "$XPC_CYCLES" "$PERFORMANCE_CYCLES"
