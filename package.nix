{
  lib,
  stdenv,
  stdenvNoCC,
  makeWrapper,
  fetchurl,
  nodejs,
}:

let
  version = "0.79.3";

  srcs = {
    "x86_64-linux" = {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-linux-x64.tar.gz";
      hash = "sha256-Lmh3K76qzXNIh1EJgZOHU4lja4BYkQBgmimSHe1xyYQ=";
    };
    "aarch64-linux" = {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-linux-arm64.tar.gz";
      hash = "sha256-Bxns9QpCyuefTG8NSmLgjo1EIXiMzQUNCKW781yI7fY=";
    };
    "x86_64-darwin" = {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-darwin-x64.tar.gz";
      hash = "sha256-1La2Kgw0wPLkyxbub9TwCGuGrXDgSI/T2qkjEhbYTis=";
    };
    "aarch64-darwin" = {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-darwin-arm64.tar.gz";
      hash = "sha256-x9Elu969hj+nbZInRFi6DrQF5c3jnbNNsfSfdn7Z8d0=";
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
