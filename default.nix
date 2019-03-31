{ nixpkgsFun ? import (builtins.fetchTarball "https://github.com/matthewbauer/nixpkgs/archive/static-nix.tar.gz")
, archs ? [
  "x86_64"
  "aarch64"
  # "armv6l"
  # "armv7l"
  # "i686"
], targetBin ? "nix" }:

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
    }; emulator = nativePkgs.writeScript targetBin ''
      ${pkgs.hostPlatform.emulator nativePkgs} "${pkgs.nix}/bin/${targetBin} $@"
    ''; in nativePkgs.runCommand "${targetBin}-${arch}" {
      nativeBuildInputs = [ nativePkgs.haskellPackages.arx ];
      passthru = { inherit (pkgs) nix; inherit emulator; };
    } ''
      # verify built binaries actually work
      ${emulator} --version > /dev/null

      cp -r ${pkgs.nix}/share share
      chmod -R 755 share
      rm -rf share/nix/sandbox
      chmod 644 share/nix/corepkgs/*

      cp ${pkgs.nix}/bin/${targetBin} ${targetBin}
      chmod 755 ${targetBin}

      tar cfz ${targetBin}.tar.gz ${targetBin} share/

      mkdir -p $out/libexec/
      cp ${pkgs.nix}/bin/${targetBin} $out/libexec/${targetBin}-${arch}

      mkdir -p $out/bin/
      arx tmpx ./${targetBin}.tar.gz -o $out/bin/${targetBin}-${arch} // ${nix-runner} '"$@"'
      chmod +x $out/bin/${targetBin}-${arch}
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
    if [ -x ./${targetBin}-$arch ]; then
      ./${targetBin}-$arch "$@"
    else
      ./${targetBin} "$@"
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

      tar cfz ${targetBin}.tar.gz ${targetBin}-* share/

      mkdir -p $out/bin/
      arx tmpx ./${targetBin}.tar.gz -o $out/bin/${targetBin} // ${nix-runner} '"$@"'
      chmod +x $out/bin/${targetBin}
    '';
  };

in all
