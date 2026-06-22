{
  lib,
  stdenv,
  stdenvNoCC,
  bun,
  fetchFromGitHub,
  makeWrapper,
  writableTmpDirAsHomeHook,
  testers,
  nix-update-script,
  nodejs,
}:
let
  bunTarget = {
    "aarch64-darwin" = "bun-darwin-arm64";
    "aarch64-linux" = "bun-linux-arm64";
    "x86_64-darwin" = "bun-darwin-x64";
    "x86_64-linux" = "bun-linux-x64";
  };

  version = "0.79.10";

  src = fetchFromGitHub {
    owner = "earendil-works";
    repo = "pi";
    rev = "v${version}";
    hash = "sha256-UMRkOzJpA1XcEHzRwHxgBg6idEmpVJzBKlrXZaVf4MQ=";
  };

  bunLock = ./package-src.bun.lock;

  node_modules = stdenvNoCC.mkDerivation {
    pname = "pi-node_modules";
    inherit version src;

    nativeBuildInputs = [
      bun
      writableTmpDirAsHomeHook
    ];

    dontConfigure = true;

    postPatch = ''
      cp ${bunLock} bun.lock
    '';

    buildPhase = ''
      runHook preBuild
      bun install --frozen-lockfile --ignore-scripts --no-progress --linker hoisted
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
    outputHash = "sha256-Ux7I27dMt7QARGoLp8IhwCCkDJTJuksYMCHoK1Ev3ek=";
  };
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "pi-coding-agent";
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
      ./packages/coding-agent/src/cli.ts \
      ./packages/coding-agent/src/utils/image-resize-worker.ts
    runHook postBuild
  '';

  dontStrip = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/pi $out/bin

    install -Dm755 pi $out/lib/pi/pi
    cp node_modules/@silvia-odwyer/photon-node/photon_rs_bg.wasm $out/lib/pi/

    cd packages/coding-agent
    install -Dm644 -t $out/lib/pi/ package.json
    install -Dm644 -t $out/lib/pi/assets/ src/modes/interactive/assets/*.png
    install -Dm644 -t $out/lib/pi/theme/ src/modes/interactive/theme/*.json
    install -Dm644 -t $out/lib/pi/export-html/ src/core/export-html/template.*
    install -Dm644 -t $out/lib/pi/export-html/vendor/ src/core/export-html/vendor/*.js

    makeWrapper $out/lib/pi/pi $out/bin/pi \
      --set-default PI_DATA_DIR "$HOME/.local/share/pi" \
      --set-default PI_PACKAGE_DIR "$out/lib/pi" \
      --prefix PATH : ${lib.makeBinPath [ nodejs ]} \

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
    updateScript = nix-update-script {
      extraArgs = [
        "--subpackage"
        "node_modules"
      ];
    };
  };

  meta = {
    description = "Terminal-based AI coding agent";
    homepage = "https://github.com/earendil-works/pi";
    license = lib.licenses.mit;
    mainProgram = "pi";
    platforms = lib.platforms.unix;
  };
})
