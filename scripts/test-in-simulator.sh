#!/usr/bin/env bash
#
# Runs the package tests in the iOS simulator for CI, and keeps their output and result bundle.
#
#   scripts/test-in-simulator.sh <name> [xcodebuild arguments...]
#   scripts/test-in-simulator.sh --boot
#
# The output goes to <results>/<name>.log and the result bundle to <results>/<name>.xcresult, where <results> is
# $TEST_RESULTS_DIR. The arguments are passed to xcodebuild before the test action, such as `clean`.
#
# The simulator sometimes fails to start the test runner, and xcodebuild reports "The test runner hung before
# establishing connection." instead of running a test target. When that is the only failure, the tests run once
# more, as <name>-retry. A test that fails is never run again, so that flaky tests still fail.
#
# With --boot, the script starts booting the simulator of the tests and returns without waiting for it, so that it
# boots while the tests build. Right after it boots, the simulator takes minutes to launch the first test runner, so
# it's better booted early. xcodebuild waits for a simulator that is still booting.

set -uo pipefail

device_name="iPhone 17e"
runtime="com.apple.CoreSimulator.SimRuntime.iOS-27-0"
destination="platform=iOS Simulator,name=${device_name},OS=27.0"

if [[ "${1:-}" == "--boot" ]]; then
  udid=$(xcrun simctl list devices available --json \
    | jq -r --arg runtime "${runtime}" --arg name "${device_name}" \
      'first(.devices[$runtime][]? | select(.name == $name) | .udid) // empty')
  if [[ -z "${udid}" ]]; then
    echo "::warning title=Simulator not found::${device_name} with ${runtime} isn't available, so it boots with the tests."
    exit 0
  fi
  # A simulator that is already booted fails to boot again, which doesn't matter.
  xcrun simctl boot "${udid}" || true
  exit 0
fi

name="$1"
shift
results="${TEST_RESULTS_DIR:?set TEST_RESULTS_DIR to the directory for the results}"
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
