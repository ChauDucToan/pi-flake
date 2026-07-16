{
  lib,
  stdenv,
  stdenvNoCC,
  makeWrapper,
  fetchurl,
  nodejs,
}:

let
  version = "0.80.7";

  srcs = {
    "x86_64-linux" = {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-linux-x64.tar.gz";
      hash = "sha256-xfWpp3o45o/LCJ3U41Bau2TJjRlZW1WBjJYb53mIlxk=";
    };
    "aarch64-linux" = {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-linux-arm64.tar.gz";
      hash = "sha256-vYv0mzbaAPr0G5XIMtr1OFIoFsCVBhkckAvmBoaLtTE=";
    };
    "x86_64-darwin" = {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-darwin-x64.tar.gz";
      hash = "sha256-PnGsOqS6bNkvf4xwTgYoK0QThCh352cLLc47G/QiMY0=";
    };
    "aarch64-darwin" = {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-darwin-arm64.tar.gz";
      hash = "sha256-DxV3HvduzWmwPij+zwxRJZP/biR3rPOeNbwsikBW0eM=";
    };
  };

  system = stdenvNoCC.hostPlatform.system;
in
stdenvNoCC.mkDerivation {
  pname = "pi-coding-agent";
  inherit version;

  src = fetchurl srcs.${system};

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/pi $out/bin
    cp -r . $out/lib/pi/
    chmod +x $out/lib/pi/pi

    makeWrapper $out/lib/pi/pi $out/bin/pi \
      --set-default PI_DATA_DIR "$HOME/.local/share/pi" \
      --set-default PI_PACKAGE_DIR "$out/lib/pi" \
      --prefix PATH : ${lib.makeBinPath [ nodejs ]}

    runHook postInstall
  '';

  postFixup = lib.optionalString stdenv.isLinux ''
    wrapProgram $out/bin/pi \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ stdenv.cc.cc.lib ]}
  '';

  meta = {
    description = "Terminal-based AI coding agent (pre-built)";
    homepage = "https://github.com/earendil-works/pi";
    license = lib.licenses.mit;
    mainProgram = "pi";
    platforms = lib.platforms.unix;
  };
}
