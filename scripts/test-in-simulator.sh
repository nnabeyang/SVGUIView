#!/usr/bin/env bash
#
# Runs the package tests in the iOS simulator for CI, and keeps their output and result bundle.
#
#   scripts/test-in-simulator.sh <name> [xcodebuild arguments...]
#
# The output goes to <results>/<name>.log and the result bundle to <results>/<name>.xcresult, where <results> is
# $TEST_RESULTS_DIR. The arguments are passed to xcodebuild before the test action, such as `clean`.
#
# The simulator sometimes fails to start the test runner, and xcodebuild reports "The test runner hung before
# establishing connection." instead of running a test target. When that is the only failure, the tests run once
# more, as <name>-retry. A test that fails is never run again, so that flaky tests still fail.

set -uo pipefail

name="$1"
shift
results="${TEST_RESULTS_DIR:?set TEST_RESULTS_DIR to the directory for the results}"
destination="platform=iOS Simulator,name=iPhone 17e,OS=27.0"
mkdir -p "${results}"

run_tests() {
  local run="$1"
  shift
  rm -rf "${results}/${run}.xcresult"
  # xcpretty hides the output of Swift Testing, so keep the whole output and the result bundle as well. Without
  # pipefail, the exit status of xcpretty would hide a failing xcodebuild.
  xcodebuild "$@" test \
    -scheme SVGUIView-Package \
    -destination "${destination}" \
    -resultBundlePath "${results}/${run}.xcresult" \
    -collect-test-diagnostics never \
    | tee "${results}/${run}.log" \
    | xcpretty
}

# Succeeds when every failure in the result bundle is a test runner that didn't start.
only_runner_failed_to_start() {
  xcrun xcresulttool get test-results summary --path "$1" \
    | jq -e '(.testFailures | length) > 0
      and all(.testFailures[]; .failureText | test("hung before establishing connection"))' \
      > /dev/null
}

run_tests "${name}" "$@"
status=$?
[[ ${status} -eq 0 ]] && exit 0
only_runner_failed_to_start "${results}/${name}.xcresult" || exit "${status}"

echo "::warning title=Tests run again::The test runner didn't start in the simulator, so the tests of ${name} run again."
run_tests "${name}-retry"
