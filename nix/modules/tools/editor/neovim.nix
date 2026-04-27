{ dotmod, config, lib, pkgs, repoPaths, ... }:

# Neovim (plugin-managed config via lazy.nvim)

(dotmod.mkModule { inherit config; }) {
  path = "tools.editor.neovim";

  options = with dotmod; moduleOptions {
    enable = boolOption false;
    sync.enable = boolOption false;
  };

  homeOnEnable = { cfg, ... }:
    let
      neovimConfigDir = repoPaths.apps + "/neovim";
    in
    {
      home.packages = [
        pkgs.neovim
        pkgs.fd
        pkgs.ripgrep
      ];

      xdg.configFile."nvim" = lib.mkIf cfg.sync.enable {
        force = true;
        source = neovimConfigDir;
        recursive = true;
      };
    };
}
