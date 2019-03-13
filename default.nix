{ nixpkgsFun ? import (builtins.fetchTarball "https://github.com/matthewbauer/nixpkgs/archive/static-nix.tar.gz")
, archs ? [
  "x86_64"
  "aarch64"
  # "armv6l"
  # "armv7l"
  # "i686"
] }:

let

  nativePkgs = nixpkgsFun {};

  nixes = builtins.listToAttrs (map (arch: {
    name = arch;
    value = let pkgs = nixpkgsFun {
      crossOverlays = [ (import "${nativePkgs.path}/pkgs/top-level/static.nix") ];
      crossSystem = {
        # busybox just supports gcc!
        # useLLVM = true;

        config = if arch == "armv6l" || arch == "armv7l" then "${arch}-unknown-linux-musleabi"
                 else "${arch}-unknown-linux-musl";
      };
    }; in nativePkgs.runCommand "nix-${arch}" {
      nativeBuildInputs = [ nativePkgs.haskellPackages.arx ];
      passthru = {
        inherit (pkgs) nix;
        test = nativePkgs.writeScriptBin "nix" ''
          ${pkgs.hostPlatform.emulator nativePkgs} ${pkgs.nix}/bin/nix "$@"
        '';
      };
    } ''
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
      arx tmpx ./nix.tar.gz -o $out/bin/nix-${arch} // ${nix-runner}
      chmod +x $out/bin/nix-${arch}
    '';
  }) archs);

  nix-runner = nativePkgs.writeScript "nix-runner.sh" ''
    export NIX_DATA_DIR=$PWD/share
    arch=$(uname -m)
    case $arch in
      i*86) arch=i686 ;;
      amd64) arch=x86_64 ;;
      armv6|armv7) arch=''${arch}l ;;
    esac
    if [ -x ./nix-$arch ]; then
      ./nix-$arch "$@"
    else
      ./nix "$@"
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

      tar cfz nix.tar.gz nix-* share/

      mkdir -p $out/bin/
      arx tmpx ./nix.tar.gz -o $out/bin/nix // ${nix-runner}
      chmod +x $out/bin/nix
    '';
  };

in all
