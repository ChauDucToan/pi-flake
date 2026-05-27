{ lib
, stdenv
, stdenvNoCC
, bun
, cacert
, fetchFromGitHub
, makeWrapper
, writableTmpDirAsHomeHook
, testers
, nix-update-script
}:

let
    bunTarget = {
        "aarch64-darwin" = "bun-darwin-arm64";
        "aarch64-linux"  = "bun-linux-arm64";
        "x86_64-darwin"  = "bun-darwin-x64";
        "x86_64-linux"   = "bun-linux-x64";
    };

    version = "0.75.5";

    src = fetchFromGitHub {
        owner = "earendil-works";
        repo  = "pi";
        rev   = "v${version}";
        hash  = "sha256-RNQ4ospdohOA8hyegCMziJHHbmFGdk/QtkjzJmS/PZc=";
    };

    node_modules = stdenvNoCC.mkDerivation {
        pname = "pi-node_modules";
        inherit version src;

        nativeBuildInputs = [ 
            bun
            writableTmpDirAsHomeHook
        ];

        dontConfigure = true;

        buildPhase = ''
            runHook preBuild
            bun install --ignore-scripts --no-progress
            runHook postBuild
        '';

        installPhase = ''
            runHook preInstall
            mkdir -p $out
            cp -R node_modules $out/
            runHook postInstall
        '';

        dontFixup = true;

        outputHashMode = "recursive";
        outputHashAlgo = "sha256";
        outputHash = "sha256-q0OixtpP/ZyENCUCjSbxXEWd9pCcbVQ92f8LpplJp4M=";
    };
in stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "pi";
    inherit version src;

    nativeBuildInputs = [
        bun
        makeWrapper
        writableTmpDirAsHomeHook
    ];

    configurePhase = ''
        runHook preConfigure
        cp -R ${node_modules}/node_modules .
        runHook postConfigure
    '';

    buildPhase = ''
        runHook preBuild
        bun build \
            --compile \
            --target=${bunTarget.${stdenvNoCC.hostPlatform.system}} \
            --outfile=pi \
            ./packages/coding-agent/src/cli.ts
        runHook postBuild
    '';

    dontStrip = true;

    installPhase = ''
        runHook preInstall

        mkdir -p $out/lib/pi/assets
        mkdir -p $out/lib/pi/export-html/vendor
        mkdir -p $out/lib/pi/theme
        mkdir -p $out/lib/pi/docs
        mkdir -p $out/lib/pi/examples

        cp pi $out/lib/pi/pi
        chmod +x $out/lib/pi/pi

        cp node_modules/@silvia-odwyer/photon-node/photon_rs_bg.wasm $out/lib/pi/
        cd packages/coding-agent
        cp package.json $out/lib/pi/

        cp src/modes/interactive/assets/*.png \
            $out/lib/pi/assets/
        cp src/core/export-html/template.* \
            $out/lib/pi/export-html/
        cp src/core/export-html/vendor/*.js \
            $out/lib/pi/export-html/vendor/
        cp src/modes/interactive/theme/*.json \
            $out/lib/pi/theme/
        cp -r docs/* $out/lib/pi/docs/
        cp -r examples/* $out/lib/pi/examples/
        cp README.md CHANGELOG.md $out/lib/pi/

        mkdir -p $out/bin
        makeWrapper $out/lib/pi/pi $out/bin/pi \
            --set-default PI_DATA_DIR "$HOME/.local/share/pi" \
            --set-default PI_PACKAGE_DIR "$out/lib/pi" \
            --set SSL_CERT_FILE "${cacert}/etc/ssl/certs/ca-bundle.crt" \
            --set NODE_EXTRA_CA_CERTS "${cacert}/etc/ssl/certs/ca-bundle.crt"

        runHook postInstall
    '';

    postFixup = lib.optionalString stdenv.isLinux ''
        wrapProgram $out/bin/pi \
            --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ stdenv.cc.cc.lib ]}
    '';
    
    passthru = {
        tests = {
            version = testers.testVersion {
                package = finalAttrs.finalPackage;
                command = "HOME=$(mktemp -d) $out/bin/pi --version";
            };
        };
        updateScript = nix-update-script { };
    };

    meta = {
        description = "Terminal-based AI coding agent";
        homepage    = "https://github.com/earendil-works/pi";
        license     = lib.licenses.mit;
        mainProgram = "pi";
        platforms   = lib.platforms.unix;
    };
})
