{ nixpkgsFun ? import (builtins.fetchTarball "https://github.com/matthewbauer/nixpkgs/archive/static-nix.tar.gz")
, archs ? [
  "x86_64"
  "aarch64"
  "armv6l"
  # "armv7l"
  "i686"
] }:

let

  nativePkgs = nixpkgsFun {};
  inherit (nativePkgs) lib;

  nixes = builtins.listToAttrs (map (arch: {
    name = arch;
    value = let pkgs = nixpkgsFun {
      crossOverlays = [ (import "${nativePkgs.path}/pkgs/top-level/static.nix") ];
      crossSystem = {
        # useLLVM = true;
        config = if lib.hasPrefix "armv6l" arch then "${arch}-unknown-linux-musleabi"
                 else if lib.hasPrefix "armv7" arch then "${arch}-unknown-linux-musleabihf"
                 else "${arch}-unknown-linux-musl";
      };
    }; emulator = nativePkgs.writeScript "nix" ''
      ${pkgs.hostPlatform.emulator nativePkgs} ${pkgs.nix}/bin/nix "$@"
    ''; in nativePkgs.runCommand "nix-${arch}" {
      nativeBuildInputs = [ nativePkgs.haskellPackages.arx ];
      passthru = { inherit (pkgs) nix; inherit emulator; };
    } ''
      # verify built binaries actually work
      # ${emulator} show-config > /dpvev/null

      cp -r ${pkgs.nix}/share share
      chmod -R 755 share
      rm -rf share/nix/sandbox
      chmod 644 share/nix/corepkgs/*

      cp ${pkgs.nix}/bin/nix nix
      chmod 755 nix

      cp ${nix-runner} run.sh
      chmod 755 run.sh

      tar cfz nix.tar.gz nix share/ run.sh

      mkdir -p $out/libexec/
      cp ${pkgs.nix}/bin/nix $out/libexec/nix-${arch}

      mkdir -p $out/bin/
      arx tmpx ./nix.tar.gz -o $out/bin/nix-${arch} // ./run.sh
      chmod +x $out/bin/nix-${arch}
    '';
  }) archs);

  nix-runner = nativePkgs.writeScript "nix-runner.sh" ''
    export NIX_DATA_DIR=$PWD/share
    arch=$(uname -m)
    case $arch in
      i*86) arch=i686 ;;
      arm*) arch=armv6l ;;
    esac
    if [ -x ./nix-$arch ]; then
      ./nix-$arch "$@"
    elif [ -x ./nix ]; then
      ./nix "$@"
    else
      >&2 echo Could not find Nix executable for $arch
    fi
  '';

  all = nativePkgs.buildEnv {
    name = "static-nix";
    paths = builtins.attrValues nixes;
    passthru = nixes;
    buildInputs = [ nativePkgs.haskellPackages.arx ];
    postBuild = ''
      cp -r ${nixes.x86_64.nix}/share share
      chmod -R 755 share
      rm -rf share/nix/sandbox
      chmod 644 share/nix/corepkgs/*

      cp $out/libexec/* .

      cp ${nix-runner} run.sh
      chmod 755 run.sh

      tar cfz nix.tar.gz nix-* share/ run.sh

      mkdir -p $out/bin/
      arx tmpx ./nix.tar.gz -o $out/bin/nix // ./run.sh
      chmod +x $out/bin/nix
    '';
  };

in all
