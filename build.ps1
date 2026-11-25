# build.ps1 - Builds and packages Limit Theory Redux: the PowerShell version
# of build.sh, for Windows without Git Bash. Same flags, same result: the
# binaries copied into the 'bin' directory.
#
#   .\build.ps1                 optimized build (what CI ships)
#   .\build.ps1 --fast          optimized build with thin LTO, for local play-testing
#   .\build.ps1 --debug         debug build
#   .\build.ps1 --run-tests     also run clippy and the tests
#
# Flags can also be written PowerShell style (-fast, -debug, -run-tests).
#
# If Windows refuses to run scripts ("running scripts is disabled on this
# system"), run it as:
#   powershell -ExecutionPolicy Bypass -File .\build.ps1

$ErrorActionPreference = 'Stop'
Set-Location -Path $PSScriptRoot

$runTests = $false
$debug = $false
$fast = $false
$bundle = $false

foreach ($arg in $args) {
    switch -Regex ($arg) {
        '^--?(h|help)$' {
            Write-Output "build.ps1 - Builds and packages Limit Theory Redux."
            Write-Output ""
            Write-Output "options:"
            Write-Output "-h, --help          show brief help"
            Write-Output "    --run-tests     run tests"
            Write-Output "    --debug         build and run tests in debug mode"
            Write-Output "    --fast          optimized build with thin LTO, for local play-testing (not for shipping)"
            Write-Output "    --bundle        assemble an app bundle (macOS only: use build.sh there)"
            exit 0
        }
        '^--?run-tests$' { $runTests = $true; continue }
        '^--?debug$'     { $debug = $true; continue }
        '^--?fast$'      { $fast = $true; continue }
        '^--?bundle$'    { $bundle = $true; continue }
        default {
            Write-Error "Unknown flag $arg"
            exit 1
        }
    }
}

# Windows PowerShell 5.1 has no $IsWindows/$IsMacOS/$IsLinux: it only runs on Windows.
$onWindows = ($PSVersionTable.PSEdition -ne 'Core') -or $IsWindows
$onMacOS = (-not $onWindows) -and $IsMacOS

if ($onWindows) {
    $libPrefix = ''
    $libSuffix = '.dll'
    $binSuffix = '.exe'
} elseif ($onMacOS) {
    # Oldest macOS the binaries run on (see build.sh)
    if (-not $env:MACOSX_DEPLOYMENT_TARGET) { $env:MACOSX_DEPLOYMENT_TARGET = '11.0' }
    $libPrefix = 'lib'
    $libSuffix = '.dylib'
    $binSuffix = ''
} else {
    $libPrefix = 'lib'
    $libSuffix = '.so'
    $binSuffix = ''
}

# Stop on a failed cargo step, like `set -e` in build.sh
function Invoke-Cargo {
    & cargo @args
    if ($LASTEXITCODE -ne 0) {
        Write-Error "cargo $($args -join ' ') failed (exit code $LASTEXITCODE)"
        exit $LASTEXITCODE
    }
}

if ($debug) {
    $targetDir = Join-Path 'target' 'debug'
    Invoke-Cargo build --color auto
} elseif ($fast) {
    $targetDir = Join-Path 'target' 'release-fast'
    Invoke-Cargo build --profile release-fast --color auto
} else {
    $targetDir = Join-Path 'target' 'release'
    Invoke-Cargo build --release --color auto
}

if ($runTests) {
    # Debug builds test in the dev profile. Optimized builds test in the
    # ci-test profile rather than release: test binaries must unwind, and
    # release's fat LTO would make every test build as slow as a shipping one.
    $testProfile = if ($debug) { 'dev' } else { 'ci-test' }
    # '--' quoted: a bare -- is PowerShell's end-of-parameters marker and is dropped
    Invoke-Cargo clippy --profile $testProfile '--' -D warnings
    Invoke-Cargo test --profile $testProfile --no-fail-fast --color auto
}

# Re-populate the 'bin' directory.
if (Test-Path bin) { Remove-Item -Recurse -Force bin }
New-Item -ItemType Directory -Path bin | Out-Null

Copy-Item (Join-Path $targetDir "ltr$binSuffix") (Join-Path 'bin' "ltr$binSuffix")
Copy-Item (Join-Path $targetDir "${libPrefix}phx$libSuffix") (Join-Path 'bin' "${libPrefix}phx$libSuffix")

if ($bundle) {
    if ($onMacOS) {
        Write-Warning "--bundle: use ./build.sh --bundle on macOS (it signs the app bundle); skipped."
    } else {
        Write-Output "--bundle only has an effect on macOS; skipped."
    }
}

Write-Output "Built into .\bin: ltr$binSuffix, ${libPrefix}phx$libSuffix"
