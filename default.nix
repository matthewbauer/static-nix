{ nixpkgsFun ? import (builtins.fetchTarball "https://github.com/matthewbauer/nixpkgs/archive/static-nix.tar.gz")
, archs ? [
  "x86_64"
  "aarch64"
  "armv6l"
  # "armv7l"
  # "armv7a"
  "powerpc64le"
  # "mipsel"
  "i686"
  "i486"
] }:

let

  nativePkgs = nixpkgsFun {};
  inherit (nativePkgs) lib;
  haskellLib = nativePkgs.haskell.lib;

  arx = haskellLib.overrideCabal nativePkgs.haskellPackages.arx (o: {
    patches = (o.patches or []) ++ [./arx.patch];
  });

  nixes = builtins.listToAttrs (map (arch: {
    name = arch;
    value = let pkgs = nixpkgsFun {
      crossOverlays = [ (import "${nativePkgs.path}/pkgs/top-level/static.nix") ];
      crossSystem = {
        # useLLVM = true;
        config = if lib.hasPrefix "armv6" arch then "${arch}-unknown-linux-musleabi"
                 else if lib.hasPrefix "armv7" arch then "${arch}-unknown-linux-musleabihf"
                 else "${arch}-unknown-linux-musl";
      };
    }; emulator = nativePkgs.writeScript "nix-${arch}" ''
      ${pkgs.hostPlatform.emulator nativePkgs} ${pkgs.nix}/bin/nix "$@"
    ''; in nativePkgs.runCommand "nix-${arch}" {
      nativeBuildInputs = [ arx nativePkgs.hexdump ];
      passthru = { inherit (pkgs) nix; inherit emulator; };
    } (lib.optionalString (!(lib.elem arch ["i486" "armv6l"])) ''
      ${emulator} show-config | grep 'system ='
      ${emulator} show-config | grep 'system = ${arch}'
    '' + ''
      cp -r ${pkgs.nix}/share share
      chmod -R 755 share
      rm -rf share/nix/sandbox
      chmod 644 share/nix/corepkgs/*

      cp ${pkgs.nix}/bin/nix nix
      chmod 755 nix

      tar cfz nix.tar.gz nix share/

      mkdir -p $out/libexec/
      cp ${pkgs.nix}/bin/nix $out/libexec/nix-${arch}

      mkdir -p $out/bin/
      arx tmpx ./nix.tar.gz -o $out/bin/nix-${arch} // '${nix-runner}'
      chmod +x $out/bin/nix-${arch}
    '' + lib.optionalString ("${arch}-linux" == builtins.currentSystem) ''
      $out/bin/nix-${arch} show-config | grep 'system = ${arch}'
    '');
  }) archs);

  nix-runner = ''
    export NIX_DATA_DIR=$PWD/share
    arch=$(uname -m)
    case $arch in
      i*86) arch=i686 ;;
      arm*) arch=armv6l ;;
    esac
    if [ -x ./nix-$arch ]; then
      exec -a "$0" ./nix-$arch "$@"
    elif [ -x ./nix ]; then
      exec -a "$0" ./nix "$@"
    else
      >&2 echo Could not find Nix executable for $arch
    fi
  '';

  all = nativePkgs.buildEnv {
    name = "static-nix";
    paths = builtins.attrValues nixes;
    passthru = nixes;
    buildInputs = with nativePkgs; [ arx nativePkgs.hexdump ];
    postBuild = ''
      cp -r ${nixes.x86_64.nix}/share share
      chmod -R 755 share
      rm -rf share/nix/sandbox
      chmod 644 share/nix/corepkgs/*

      cp $out/libexec/* .

      tar cfz nix.tar.gz nix-x86_64 nix-i686 nix-armv6l nix-aarch64 share/

      mkdir -p $out/bin/
      arx tmpx ./nix.tar.gz -o $out/bin/nix // '${nix-runner}'
      chmod +x $out/bin/nix

      $out/bin/nix show-config | grep 'system = ${builtins.currentSystem}'
      cat $out/bin/nix | sh -s show-config | grep 'system = ${builtins.currentSystem}'
    '';
  };

in all
