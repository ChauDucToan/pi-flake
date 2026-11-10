{
  lib,
  stdenvNoCC,
  makeWrapper,
  patchelf,
  fetchurl,
  gitMinimal,
  glibc,
  libxcb,
  nodejs,
}:

let
  version = "1.5.2";

  srcs = {
    "x86_64-linux" = {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-linux-x64.tar.gz";
      hash = "sha256-gRxvLJ56ruJStUBCUuVW+3E6ognB9/kkImqnfU73DLU=";
    };
    "aarch64-linux" = {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-linux-arm64.tar.gz";
      hash = "sha256-QoBc1WFZUvy7/JxWsE+P64Q5UTSVLhaabNyNdnaXVmY=";
    };
    "x86_64-darwin" = {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-darwin-x64.tar.gz";
      hash = "sha256-+ZegiGE1FKyX2ROu6nZCCU2E/m1GhU/35k4sEuU23FA=";
    };
    "aarch64-darwin" = {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-darwin-arm64.tar.gz";
      hash = "sha256-VrXhlNSFztVVZnuLoydhV6gnLp7N6eAB5CivgJhb3Zs=";
    };
  };

  system = stdenvNoCC.hostPlatform.system;

  runtimePath = lib.makeBinPath [
    nodejs
    gitMinimal
  ];
in
stdenvNoCC.mkDerivation {
  pname = "pi-coding-agent";
  inherit version;

  src = fetchurl srcs.${system};

  nativeBuildInputs = [
    makeWrapper
    patchelf
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/pi $out/bin
    cp -r . $out/lib/pi/
    chmod +x $out/lib/pi/pi

    makeWrapper $out/lib/pi/pi $out/bin/pi \
      --set-default PI_PACKAGE_DIR "$out/lib/pi" \
      --prefix PATH : ${runtimePath}

    runHook postInstall
  '';

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

  # Exposed so a caller that wraps the ELF directly (e.g. the module's
  # `extraEnv` wrapper) keeps the same runtime tools on PATH.
  passthru.runtimePath = runtimePath;

  meta = {
    description = "Terminal-based AI coding agent (pre-built)";
    homepage = "https://github.com/earendil-works/pi";
    license = lib.licenses.mit;
    mainProgram = "pi";
    platforms = lib.platforms.unix;
  };
}
