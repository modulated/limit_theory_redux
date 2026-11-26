# Create a macOS app bundle in the 'bin' directory.
function create_app_bundle {
    echo "Creating app bundle './bin/Limit Theory Redux.app'"

    local destination
    destination="bin"

    mkdir "$destination/Limit Theory Redux.app/"
    mkdir "$destination/Limit Theory Redux.app/Contents/"
    mkdir "$destination/Limit Theory Redux.app/Contents/Resources/"
    mkdir "$destination/Limit Theory Redux.app/Contents/MacOS/"
    cp "res/images/LTR-Icon.icns" "$destination/Limit Theory Redux.app/Contents/Resources/ltr.icns"

    cat > "$destination/Limit Theory Redux.app/Contents/Info.plist" << EOF
    {
        CFBundleName = "Limit Theory Redux";
        CFBundleDisplayName = "Limit Theory Redux";
        CFBundleIdentifier = "org.LimitTheoryRedux.LimitTheoryRedux";
        CFBundleVersion = "$PHX_VERSION";
        CFBundleShortVersionString = "$PHX_VERSION";
        CFBundleInfoDictionaryVersion = "6.0";
        CFBundlePackageType = APPL;
        CFBundleSignature = ltrr;
        CFBundleExecutable = ltr;
        CFBundleIconFile = "ltr.icns";
        LSMinimumSystemVersion = "$MACOSX_DEPLOYMENT_TARGET";
        NSHighResolutionCapable = YES;
    }
EOF

    echo "Copying data files..."
    rsync -Ca ./res "$destination/Limit Theory Redux.app/Contents/"
    rsync -Ca ./script "$destination/Limit Theory Redux.app/Contents/"
    mkdir -p "$destination/Limit Theory Redux.app/Contents/engine/lib/phx"
    rsync -Ca ./engine/lib/phx/script "$destination/Limit Theory Redux.app/Contents/engine/lib/phx"

    echo "Copying binary..."
    cp -a "${target_dir}/ltr${binsuffix}" "$destination/Limit Theory Redux.app/Contents/MacOS/ltr"

    echo "Copying dynamic libraries..."
    cp "${target_dir}/${libprefix}phx${libsuffix}" "$destination/Limit Theory Redux.app/Contents/MacOS/${libprefix}phx${libsuffix}"

    # No separate strip step: the release profile already strips symbols, and
    # editing a linked arm64 binary afterwards can invalidate the ad-hoc
    # signature the linker gave it; Apple Silicon refuses to run unsigned code.
    #
    # Sign the whole bundle ad hoc (no developer identity) so the executable,
    # libphx.dylib and the bundle's resources form one valid signature.
    echo "Signing app bundle (ad hoc)..."
    codesign --force --deep --sign - "$destination/Limit Theory Redux.app"
}
