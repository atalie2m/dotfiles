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
      ] ++ lib.optionals cfg.sync.enable [
        pkgs.black
        pkgs.cargo
        pkgs.clippy
        pkgs.fish
        pkgs.fzf
        pkgs.ghostscript
        pkgs.imagemagick
        pkgs.lazygit
        pkgs.lua-language-server
        pkgs.marksman
        pkgs.mermaid-cli
        pkgs.nixfmt
        pkgs.prettier
        pkgs.prettierd
        pkgs.pyright
        pkgs.ruff
        pkgs.rust-analyzer
        pkgs.rustc
        pkgs.rustfmt
        pkgs.shfmt
        pkgs.stylua
        pkgs.tectonic
        pkgs.tree-sitter
        pkgs.vscode-langservers-extracted
        pkgs.vtsls
        pkgs.yaml-language-server
      ];

      xdg.configFile."nvim" = lib.mkIf cfg.sync.enable {
        force = true;
        source = neovimConfigDir;
        recursive = true;
      };
    };
}
