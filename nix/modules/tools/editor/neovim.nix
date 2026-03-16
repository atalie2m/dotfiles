{ delib, pkgs, repoPaths, ... }:

# Neovim (plugin-managed config via lazy.nvim)

delib.module {
  name = "tools.editor.neovim";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  home.ifEnabled = { ... }:
    let
      neovimConfigDir = repoPaths.apps + "/neovim";
    in
    {
      home.packages = [
        pkgs.neovim
        pkgs.fd
        pkgs.ripgrep
      ];

      xdg.configFile."nvim" = {
        force = true;
        source = neovimConfigDir;
        recursive = true;
      };
    };
}
