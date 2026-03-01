{ delib, lib, dotlib, pkgs, ... }:

# Neovim (plain install)

delib.module {
  name = "tools.editor.neovim";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = dotlib.mkEnableDefault "tools.editor.neovim.enable";
  };

  home.ifEnabled = { ... }: {
    home.packages = [ pkgs.neovim ];
  };
}
