{
  lib,
  stdenv,
  godot,
  makeWrapper,
  installShellFiles,
}:
let
  version = lib.head (lib.match ".*config/version=\"([^\"]*)\".*" (builtins.readFile ../app/project.godot));
in
stdenv.mkDerivation {
  pname = "anchorage";
  inherit version;

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../app
      ../data
      ../spec
      ../scripts/test.sh
    ];
  };

  nativeBuildInputs = [
    godot
    makeWrapper
  ];

  postPatch = "patchShebangs scripts";

  # The game is a .pck run by nixpkgs' own godot, which is patched for Wayland, Vulkan
  # and audio. An export template binary would need patching for each of those.
  buildPhase = ''
    runHook preBuild
    export HOME=$TMPDIR
    godot --headless --path app --import
    godot --headless --path app --export-pack Linux $PWD/anchorage.pck
    runHook postBuild
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    scripts/test.sh
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 anchorage.pck $out/share/anchorage/anchorage.pck
    makeWrapper ${lib.getExe godot} $out/bin/anchorage \
      --add-flags "--main-pack $out/share/anchorage/anchorage.pck"
    install -Dm644 data/io.github.DisposableSoftware.Anchorage.desktop -t $out/share/applications
    install -Dm644 data/io.github.DisposableSoftware.Anchorage.svg -t $out/share/icons/hicolor/scalable/apps
    install -Dm644 data/io.github.DisposableSoftware.Anchorage.metainfo.xml -t $out/share/metainfo
    install -Dm644 app/data/config.example.ini app/data/keybindings.example.ini -t $out/share/doc/anchorage
    runHook postInstall
  '';

  meta = {
    description = "Install, update and launch the HarbourMasters game ports from Steam OS game mode";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "anchorage";
  };
}
