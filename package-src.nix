{
  lib,
  stdenvNoCC,
  bun,
  fetchFromGitHub,
  fetchurl,
  gitMinimal,
  glibc,
  makeWrapper,
  libxcb,
  patchelf,
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

  version = "1.5.2";

  src = fetchFromGitHub {
    owner = "earendil-works";
    repo = "pi";
    rev = "v${version}";
    hash = "sha256-0dKtABQqfvCLF0WOydu5rpycMqC+N8Pc9Ex4BWKElyw=";
  };

  aiData = fetchurl {
    url = "https://registry.npmjs.org/@earendil-works/pi-ai/-/pi-ai-${version}.tgz";
    hash = "sha256-1XFe+oNMI7/fEKBCtJ307hacyZAAvxbXmY+rLVM7Rfg=";
  };

  bunLock = ./package-src.bun.lock;

  runtimePath = lib.makeBinPath [
    nodejs
    gitMinimal
  ];

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
    outputHash = "sha256-iURx6I+HdkEMLsfsra9tlLh2nQtQtpz2rt5mBW6C1GM=";
  };
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "pi-coding-agent";
  inherit version src;

  nativeBuildInputs = [
    bun
    makeWrapper
    patchelf
    writableTmpDirAsHomeHook
  ];

  postPatch = ''
    if tar -tzf ${aiData} package/dist/providers/data >/dev/null 2>&1; then
      tar -xzf ${aiData} --strip-components=3 -C packages/ai/src/providers package/dist/providers/data
    fi
  '';

  configurePhase = ''
    runHook preConfigure
    cp -R ${node_modules}/node_modules .
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    # Keep this in sync with upstream `build:binary` in
    # packages/coding-agent/package.json. The extra entrypoints and the two
    # --no-compile-autoload flags are required: codemode's worker is resolved
    # from an embedded $bunfs path, and autoloaded bunfig.toml/.env from cwd
    # must not be picked up by the compiled binary.
    bun build \
      --compile \
      --target=${bunTarget.${stdenvNoCC.hostPlatform.system}} \
      --no-compile-autoload-bunfig \
      --no-compile-autoload-dotenv \
      --outfile=pi \
      ./packages/coding-agent/src/bun/cli.ts \
      ./packages/coding-agent/src/utils/image-resize-worker.ts \
      ./packages/coding-agent/src/extensions/codemode/worker.ts
    runHook postBuild
  '';

  dontStrip = true;

  # The main `pi` executable is a Bun self-extracting binary. Everything is
  # mandatory here and order matters:
  #  - the interpreter must be patched, or the binary cannot start inside a Nix
  #    build sandbox (no /lib64/ld-linux-x86-64.so.2 there);
  #  - autoPatchelfHook must NOT be used: besides the interpreter it also adds an
  #    RPATH, and rewriting that part of the ELF shifts the offsets of the
  #    embedded filesystem, after which `--version` reports the wrong release;
  #  - pi-tui's prebuilt helper needs its own RPATH for a distro libxcb, and the
  #    native tree also ships Windows (PE) and macOS (Mach-O) builds that
  #    patchelf rejects, so only ELF helpers are patched.
  postFixup = lib.optionalString stdenvNoCC.hostPlatform.isLinux ''
        patchelf --set-interpreter ${glibc}/lib/ld-linux-x86-64.so.2 \
          $out/lib/pi/pi

        while IFS= read -r helper; do
          if [ "$(head -c4 "$helper" | od -An -c | tr -d ' \n')" = "177ELF" ]; then
            patchelf --set-rpath ${lib.makeLibraryPath [ libxcb ]} "$helper"
          fi
        done <<EOF
    $(find $out/lib/pi/native -name '*.node' -type f)
    EOF
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/pi $out/bin

    install -Dm755 pi $out/lib/pi/pi
    cp node_modules/@silvia-odwyer/photon-node/photon_rs_bg.wasm $out/lib/pi/
    # pi-tui loads these from `dirname(execPath)/native/<platform>/prebuilds/`
    # (packages/tui/src/native-module-path.ts). They are optional at runtime,
    # but their absence silently drops the native clipboard/platform helpers.
    cp -R node_modules/@earendil-works/pi-tui/native $out/lib/pi/native

    cd packages/coding-agent
    install -Dm644 -t $out/lib/pi/ package.json README.md CHANGELOG.md
    # Pi's system prompt points the agent at these three paths
    # (src/core/system-prompt.ts: getReadmePath/getDocsPath/getExamplesPath),
    # so a missing directory silently loses the agent's documentation lookup.
    cp -R docs examples $out/lib/pi/
    install -Dm644 -t $out/lib/pi/assets/ src/modes/interactive/assets/*.png
    install -Dm644 -t $out/lib/pi/theme/ src/modes/interactive/theme/*.json
    install -Dm644 -t $out/lib/pi/export-html/ src/core/export-html/template.*
    install -Dm644 -t $out/lib/pi/export-html/vendor/ src/core/export-html/vendor/*.js

    makeWrapper $out/lib/pi/pi $out/bin/pi \
      --set-default PI_PACKAGE_DIR "$out/lib/pi" \
      --prefix PATH : ${runtimePath}

    runHook postInstall
  '';

  passthru = {
    inherit runtimePath;
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
