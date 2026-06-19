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
      hash = "sha256-c4uH02bU5D9i5jMacTku53oi4Bnc280jp9rP+Fb67o8=";
    };
    "aarch64-linux" = {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-linux-arm64.tar.gz";
      hash = "sha256-Z+xto1fTdI/6+lt/Zdi/q3njYBS0pbIaVHi4++WorYE=";
    };
    "x86_64-darwin" = {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-darwin-x64.tar.gz";
      hash = "sha256-KaGj/mPfM2qEhwQlnIAcr1Xv854XWQWy+zCGsigO3iA=";
    };
    "aarch64-darwin" = {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-darwin-arm64.tar.gz";
      hash = "sha256-mw2iQyEKT6rZtKu2QcrFGc4tnSjqxrABub8kob+E9YU=";
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
