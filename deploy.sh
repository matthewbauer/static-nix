#!/usr/bin/env sh

result=$(nix-build)
dir=$(mktemp -d)

setup() {
  git clone ssh://git@github.com/matthewbauer/matthewbauer.github.io.git $dir
  pushd $dir
}

cleanup() {
  popd
  rm -rf $dir
}

setup
trap cleanup EXIT

cp $result/bin/* .
git add nix-*
git add nix
git commit -m "Update Nix binaries"
git push
