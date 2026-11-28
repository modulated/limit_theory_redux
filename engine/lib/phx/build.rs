use std::env;

fn main() {
    // `cfg!(target_os = ...)` in a build script describes the machine running
    // the script (the host), not the platform being built for. Cargo passes
    // the target's OS in CARGO_CFG_TARGET_OS, which stays right when
    // cross-compiling (e.g. building Windows binaries on Linux).
    let target_os = env::var("CARGO_CFG_TARGET_OS").expect("CARGO_CFG_TARGET_OS is not set");

    // CI stamps the build number in PHX_VERSION; a local build is the
    // workspace's version (Cargo.toml), marked as a development build.
    let phx_version = env::var("PHX_VERSION")
        .ok()
        .filter(|v| !v.trim().is_empty())
        .unwrap_or_else(|| format!("{}-dev", env!("CARGO_PKG_VERSION")));
    println!("cargo::rustc-env=PHX_VERSION={phx_version}");
    println!("cargo::rerun-if-env-changed=PHX_VERSION");

    // Link dependencies.
    if target_os != "windows" {
        println!("cargo::rustc-link-lib=z");
    }

    // LuaJIT comes from mlua's `vendored` feature, which runs LuaJIT's own
    // msvcbuild.bat: its `static` path compiles without /MD, so cl defaults to
    // /MT and every object asks for the static CRT (LIBCMT) while Rust links
    // the dynamic one (MSVCRT). The linker already resolves everything to
    // MSVCRT and says so as LNK4098; this tells it to ignore the static CRT
    // outright, which is what it was doing anyway, and the warning goes.
    if target_os == "windows" && env::var("CARGO_CFG_TARGET_ENV").unwrap_or_default() == "msvc" {
        println!("cargo::rustc-link-arg=/NODEFAULTLIB:LIBCMT");
    }
    if target_os == "macos" {
        println!("cargo::rustc-link-lib=framework=CoreHaptics");
    }

    // Only for the shipped libphx.dylib: its install name, and DWARF unwind
    // tables instead of compact unwind info. Test and bench binaries keep the
    // default tables, without which a panic cannot unwind on macOS (a failing
    // test aborts the whole test binary).
    if target_os == "macos" {
        println!("cargo::rustc-link-arg-cdylib=-Wl,-no_compact_unwind");
        println!("cargo::rustc-link-arg-cdylib=-Wl,-install_name,@rpath/libphx.dylib");
    }

    // Set rpath correctly for libphx.
    if target_os == "linux" {
        println!("cargo::rustc-link-arg=-Wl,-rpath,$ORIGIN");
        println!("cargo::rustc-link-arg=-Wl,-rpath,$ORIGIN/deps");
    } else if target_os == "macos" {
        println!("cargo::rustc-link-arg=-Wl,-rpath,@executable_path");
        println!("cargo::rustc-link-arg=-Wl,-rpath,@executable_path/deps");
    }

    // If we don't specify rerun-if-changed, then Cargo will always rerun build.rs, causing phx to always be rebuild.
    //
    // Here, we just specify build.rs as the file that should be used to guide if phx's build script needs to be re-run.
    println!("cargo::rerun-if-changed=build.rs");
}
