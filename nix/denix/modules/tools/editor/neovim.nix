{ delib, lib, pkgs, ... }:

# Neovim (plain install)

let
  mkEnableDefault = import ../../../../lib/mk-enable-default.nix { inherit lib; };
in

delib.module {
  name = "tools.editor.neovim";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = mkEnableDefault "tools.editor.neovim.enable";
  };

  home.ifEnabled = { ... }: {
    home.packages = [ pkgs.neovim ];
  };
}
