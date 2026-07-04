{ dotmod, config, lib, dotlib, pkgs, repoPaths, ... }:

let
  homebrewOwnership = import (repoPaths.catalog + "/tools/homebrew-ownership.nix");
  homebrewSpec = homebrewOwnership."network.mosh";
  moshServerWrapper = pkgs.writeShellScriptBin "mosh-server" ''
    set -euo pipefail

    for candidate in /opt/homebrew/bin/mosh-server /usr/local/bin/mosh-server; do
      if [[ -x "$candidate" ]]; then
        exec "$candidate" "$@"
      fi
    done

    echo "dotfiles: Homebrew mosh-server was not found; install the 'mosh' formula or re-run dotfiles apply." >&2
    exit 127
  '';
in
(dotmod.mkModule { inherit config; }) {
  path = "tools.network.mosh";

  options = with dotmod; moduleOptions {
    enable = boolOption false;
  };

  myconfigOnEnable = { myconfig, ... }:
    dotlib.ifDarwin myconfig (dotlib.requireHomebrewSpec homebrewSpec);

  homeOnEnable = { ... }: {
    home.packages =
      lib.optional pkgs.stdenv.isDarwin moshServerWrapper
      ++ lib.optional pkgs.stdenv.isLinux pkgs.mosh;
  };
}
