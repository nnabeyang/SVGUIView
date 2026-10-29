#!/usr/bin/env bash
#
# Builds and runs the package tests in the iOS simulator for CI, and keeps their output and result bundle.
#
#   scripts/test-in-simulator.sh --boot
#   scripts/test-in-simulator.sh --build [xcodebuild arguments...]
#   scripts/test-in-simulator.sh --wait
#   scripts/test-in-simulator.sh <name> [xcodebuild arguments...]
#
# xcodebuild waits for a simulator that is still booting before it builds, and right after it boots, the simulator
# takes minutes to launch the first test runner. So the simulator is booted first, and the tests build while it
# boots:
#
# With --boot, the script starts booting the simulator of the tests and returns without waiting for it.
#
# With --build, the script builds the tests for any simulator, which doesn't wait for one. The arguments are passed
# to xcodebuild before the action, such as `clean` or build settings. The output goes to <results>/build.log.
#
# With --wait, the script waits until the simulator has booted, and boots it if it isn't booting.
#
# With a name, the script runs the tests that --build built. The output goes to <results>/<name>.log and the result
# bundle to <results>/<name>.xcresult. The arguments are passed to xcodebuild before the action, such as
# `-only-testing:`.
#
# <results> is $TEST_RESULTS_DIR.
#
# The simulator sometimes fails to start the test runner, and xcodebuild reports "The test runner hung before
# establishing connection." instead of running a test target. When that is the only failure, the tests run once
# more, as <name>-retry. A test that fails is never run again, so that flaky tests still fail.

set -uo pipefail

device_name="iPhone 17e"
runtime="com.apple.CoreSimulator.SimRuntime.iOS-27-0"
destination="platform=iOS Simulator,name=${device_name},OS=27.0"

# Prints the identifier of the simulator of the tests, or warns and prints nothing if it isn't available.
simulator() {
  local udid
  udid=$(xcrun simctl list devices available --json \
    | jq -r --arg runtime "${runtime}" --arg name "${device_name}" \
      'first(.devices[$runtime][]? | select(.name == $name) | .udid) // empty')
  if [[ -z "${udid}" ]]; then
    echo "::warning title=Simulator not found::${device_name} with ${runtime} isn't available, so it boots with the tests." >&2
  fi
  echo "${udid}"
}

case "${1:-}" in
  --boot)
    udid=$(simulator)
    [[ -z "${udid}" ]] && exit 0
    # A simulator that is already booted fails to boot again, which doesn't matter.
    xcrun simctl boot "${udid}" || true
    exit 0
    ;;
  --wait)
    udid=$(simulator)
    [[ -z "${udid}" ]] && exit 0
    xcrun simctl bootstatus "${udid}" -b
    exit
    ;;
esac

results="${TEST_RESULTS_DIR:?set TEST_RESULTS_DIR to the directory for the results}"
mkdir -p "${results}"

if [[ "${1:-}" == "--build" ]]; then
  shift
  # xcpretty hides the output of Swift Testing, so keep the whole output as well. Without pipefail, the exit status
  # of xcpretty would hide a failing xcodebuild.
  xcodebuild "$@" build-for-testing \
    -scheme SVGUIView-Package \
    -destination "generic/platform=iOS Simulator" \
    | tee "${results}/build.log" \
    | xcpretty
  exit
fi

name="$1"
shift

run_tests() {
  local run="$1"
  shift
  rm -rf "${results}/${run}.xcresult"
  xcodebuild "$@" test-without-building \
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
run_tests "${name}-retry" "$@"
