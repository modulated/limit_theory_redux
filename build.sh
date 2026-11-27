#!/bin/bash
set -e

source ./utils.sh

run_tests=false
debug=false
fast=false
profile_server=false
bundle=false

while test $# -gt 0; do
  case "$1" in
    -h|--help)
      echo "build.sh - Builds and packages Limit Theory Redux."
      echo " "
      echo "options:"
      echo "-h, --help          show brief help"
      echo "    --run-tests     run tests"
      echo "    --debug         build and run tests in debug mode"
      echo "    --fast          optimized build with thin LTO, for local play-testing (not for shipping)"
      echo "    --profile-server  --fast build with the live stats/profiler server compiled in"
      echo "                    (it starts with the game: http://127.0.0.1:8777, or --stats-server <port>)"
      echo "    --bundle        assemble an app bundle (only has an effect on macOS)"
      exit 0
      ;;
    --run-tests)
      run_tests=true
      shift
      ;;
    --debug)
      debug=true
      shift
      ;;
    --fast)
      fast=true
      shift
      ;;
    --profile-server)
      profile_server=true
      fast=true
      shift
      ;;
    --bundle)
      bundle=true
      shift
      ;;
    *)
      echo "Unknown flag $1"
      exit 1
      ;;
  esac
done

if [[ "$OSTYPE" == "darwin"* ]]; then
    # Oldest macOS the binaries run on. Keep in sync with LSMinimumSystemVersion
    # in utils.sh (create_app_bundle reads this variable).
    export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-11.0}"
    libprefix="lib"
    libsuffix=".dylib"
    binsuffix=""
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    libprefix="lib"
    libsuffix=".so"
    binsuffix=""
elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    libprefix=""
    libsuffix=".dll"
    binsuffix=".exe"
else
    echo "Unsupported OSTYPE: '$OSTYPE'"
    exit 1
fi

if [ -z "$PHX_VERSION" ]; then
    export PHX_VERSION
fi

# The stats/profiler server is a cargo feature of ltr (doc/STAT_SERVER.md)
features=()
if [[ $profile_server == true ]]; then
    features=(--features stats-server)
fi

if [[ $debug == true ]]; then
    target_dir="target/debug"
    cargo build "${features[@]}" --color auto
elif [[ $fast == true ]]; then
    target_dir="target/release-fast"
    cargo build --profile release-fast "${features[@]}" --color auto
else
    target_dir="target/release"
    cargo build --release --color auto
fi

if [[ $run_tests == true ]]; then
    # Debug builds test in the dev profile. Optimized builds test in the
    # ci-test profile rather than release: test binaries must unwind, and
    # release's fat LTO would make every test build as slow as a shipping one.
    if [[ $debug == true ]]; then
        test_profile="dev"
    else
        test_profile="ci-test"
    fi
    cargo clippy --profile "$test_profile" -- -D warnings
    cargo test --profile "$test_profile" --no-fail-fast --color auto
fi

# Re-populate the 'bin' directory.
rm -rf bin && mkdir -p bin

cp "${target_dir}/ltr${binsuffix}" "bin/ltr${binsuffix}"
cp "${target_dir}/${libprefix}phx${libsuffix}" "bin/${libprefix}phx${libsuffix}"

if [[ $bundle == true ]]; then
    create_app_bundle bin
fi

if [[ $profile_server == true ]]; then
    echo "Built with the stats server: it starts with the game on http://127.0.0.1:8777"
    echo "(another port: bin/ltr${binsuffix} --stats-server <port>)"
fi
