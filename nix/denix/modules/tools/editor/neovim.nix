{ delib, lib, pkgs, ... }:

# Neovim (plain install)

delib.module {
  name = "tools.editor.neovim";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = { parent, ... }: {
      tools.editor.neovim.enable = lib.mkDefault parent.enable;
    };
  };

  home.ifEnabled = { ... }: {
    home.packages = [ pkgs.neovim ];
  };
}
