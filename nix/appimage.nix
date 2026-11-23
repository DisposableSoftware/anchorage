# INT-25, INT-26: a self-contained AppImage for SteamOS and other x86_64 glibc Linux.
#
# The binary inside is the official prebuilt Godot release template for the same engine
# version as nixpkgs' `godot` (its hash is pinned in nixpkgs). It is never patched: no
# autoPatchelf, no RPATH into /nix, so it runs on a system without Nix. `dontFixup` also
# keeps the stdenv from stripping or patching the finished AppImage.
{
  lib,
  stdenvNoCC,
  fetchurl,
  godot,
  squashfsTools,
  librsvg,
  desktop-file-utils,
  appstream,
  binutils,
}:
let
  version = lib.head (lib.match ".*config/version=\"([^\"]*)\".*" (builtins.readFile ../app/project.godot));
  appId = "io.github.DisposableSoftware.Anchorage";
  templates = godot.export-templates-bin;

  # A dated release, not the rolling "continuous" one, so the hash stays valid. This
  # static runtime mounts the image through FUSE 2 and also runs with
  # `--appimage-extract-and-run`, which needs no FUSE at all.
  runtime = fetchurl {
    url = "https://github.com/AppImage/type2-runtime/releases/download/20251108/runtime-x86_64";
    hash = "sha256-L8qLRDySUQ8Ug6iD9gBhrQm0a5eLJjHIB82HOkfsJg0=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "anchorage-appimage";
  inherit version;

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../app
      ../data
      ./AppRun
    ];
  };

  nativeBuildInputs = [
    godot
    squashfsTools
    librsvg
    desktop-file-utils
    appstream
    binutils
  ];

  dontFixup = true;

  buildPhase = ''
    runHook preBuild
    export HOME=$TMPDIR
    # Godot looks for templates in $XDG_DATA_HOME/godot/export_templates/<version>.
    export XDG_DATA_HOME=$TMPDIR/xdg
    mkdir -p $XDG_DATA_HOME
    ln -s ${templates}/share/godot $XDG_DATA_HOME/godot

    godot --headless --path app --import
    mkdir -p build
    godot --headless --path app --export-release AppImage $PWD/build/anchorage

    AppDir=build/AppDir
    install -Dm755 build/anchorage $AppDir/usr/bin/anchorage
    install -Dm644 data/${appId}.desktop -t $AppDir/usr/share/applications
    install -Dm644 data/${appId}.svg -t $AppDir/usr/share/icons/hicolor/scalable/apps
    install -Dm644 data/${appId}.metainfo.xml -t $AppDir/usr/share/metainfo
    install -Dm644 app/data/config.example.ini app/data/keybindings.example.ini -t $AppDir/usr/share/doc/anchorage

    # The AppImage spec wants the desktop entry and icon at the top of the AppDir.
    install -m755 nix/AppRun $AppDir/AppRun
    cp data/${appId}.desktop data/${appId}.svg $AppDir/
    rsvg-convert -w 256 -h 256 data/${appId}.svg -o $AppDir/.DirIcon

    desktop-file-validate $AppDir/${appId}.desktop
    appstreamcli validate --no-net $AppDir/usr/share/metainfo/${appId}.metainfo.xml

    # Release template: no Nix store paths, no RPATH, a stock interpreter.
    if readelf -d $AppDir/usr/bin/anchorage | grep -q -e RPATH -e RUNPATH; then
      echo "the binary has an RPATH" >&2; exit 1
    fi
    if readelf -l $AppDir/usr/bin/anchorage | grep -q /nix/store; then
      echo "the binary has a Nix interpreter" >&2; exit 1
    fi
    if grep -aq /nix/store $AppDir/usr/bin/anchorage; then
      echo "the binary mentions /nix/store" >&2; exit 1
    fi

    mksquashfs $AppDir build/anchorage.squashfs -root-owned -noappend -no-xattrs \
      -comp zstd -Xcompression-level 19 -b 256K
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cat ${runtime} build/anchorage.squashfs > $out/Anchorage-${version}-x86_64.AppImage
    chmod +x $out/Anchorage-${version}-x86_64.AppImage
    runHook postInstall
  '';

  meta = {
    description = "Anchorage as a self-contained AppImage for SteamOS";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
}
