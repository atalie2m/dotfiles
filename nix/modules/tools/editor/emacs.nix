{ dotmod, config, lib, dotlib, pkgs, repoPaths, ... }:

let
  homebrewOwnership = import (repoPaths.catalog + "/tools/homebrew-ownership.nix");
  homebrewSpec = homebrewOwnership."editor.emacs";
  dotfilesCli = pkgs.callPackage ../../../pkgs/dotfiles-cli { };
  types = lib.types;
  emacsDir = repoPaths.apps + "/emacs";
  emacsConfigDir = emacsDir + "/config";
  iconPath = emacsDir + "/emacs-icon-1.0.icns";
  hasIcon = builtins.pathExists iconPath;
  treeSitterGrammars = with pkgs.tree-sitter-grammars; {
    bash = tree-sitter-bash;
    css = tree-sitter-css;
    html = tree-sitter-html;
    javascript = tree-sitter-javascript;
    json = tree-sitter-json;
    nix = tree-sitter-nix;
    python = tree-sitter-python;
    rust = tree-sitter-rust;
    tsx = tree-sitter-tsx;
    typescript = tree-sitter-typescript;
    yaml = tree-sitter-yaml;
  };
  emacsTreeSitterGrammars =
    let
      linkCommands = lib.concatStringsSep "\n" (lib.mapAttrsToList
        (language: grammar: ''
          ln -s ${grammar}/parser "$grammar_dir/libtree-sitter-${language}.dylib"
        '')
        treeSitterGrammars);
    in
    pkgs.runCommand "emacs-tree-sitter-grammars" { } ''
      grammar_dir="$out/lib/emacs-tree-sitter-grammars"
      mkdir -p "$grammar_dir"
      ${linkCommands}
    '';
  refreshEmacsPlusNativeCompEnv = pkgs.writeShellApplication {
    name = "dotfiles-refresh-emacs-plus-native-comp-env";
    runtimeInputs = with pkgs; [
      coreutils
    ];
    text = builtins.readFile ./refresh-emacs-plus-native-comp-env.sh;
  };
in

# Emacs (GUI via Homebrew) + vanilla user configuration

(dotmod.mkModule { inherit config; }) {
  path = "tools.editor.emacs";

  options = with dotmod; moduleOptions {
    enable = boolOption false;
    sync = {
      enable = boolOption false;
      managedDir = lib.mkOption {
        type = types.nullOr types.path;
        default = null;
      };
      emacsDir = lib.mkOption {
        type = types.nullOr types.str;
        default = null;
      };
    };
    bootstrap = {
      enable = boolOption false;
      emacsDir = lib.mkOption {
        type = types.nullOr types.str;
        default = null;
      };
    };
  };

  myconfigOnEnable = { myconfig, ... }:
    dotlib.ifDarwin myconfig (dotlib.requireHomebrewSpec homebrewSpec);

  homeOnEnable = { ... }:
    let
      emacsRuntimePackages = with pkgs; [
        bash-language-server
        black
        cargo
        cmigemo
        coreutils-prefixed
        diffutils
        direnv
        dotfilesCli
        emacsTreeSitterGrammars
        enchant
        eslint
        fd
        fontconfig
        git
        graphviz
        isort
        jsbeautifier
        multimarkdown
        nil
        nixd
        nixfmt
        pandoc
        pipenv
        prettier
        pyright
        python3Packages.pyflakes
        python3Packages.pytest
        ripgrep
        ruff
        rust-analyzer
        rustc
        rustfmt
        shfmt
        shellcheck
        sqlite
        stylelint
        typescript
        typescript-language-server
        vscode-langservers-extracted
        yaml-language-server
        (aspellWithDicts (dicts: with dicts; [
          en
        ]))
      ];
      emacsFiles = lib.optionalAttrs hasIcon {
        ".config/emacs-plus/build.yml" = {
          force = true;
          text = ''
            icon:
              url: ${iconPath}
              sha256: 0067c716e0129182951559c5ce1cf583f174f6637558fce7cbf58ac69f9a2933
          '';
        };
      };
    in
    {
      home.packages = emacsRuntimePackages;
      home.file = emacsFiles;
      home.sessionVariables.EMACS_TREE_SITTER_GRAMMAR_DIR = "${emacsTreeSitterGrammars}/lib/emacs-tree-sitter-grammars";
    };

  darwinOnEnable = { cfg, ... }:
    let
      runtimePath = lib.makeBinPath [
        pkgs.bash
        pkgs.coreutils
        pkgs.diffutils
        pkgs.fd
        pkgs.git
        pkgs.ripgrep
        dotfilesCli
      ];
      managedDirArg =
        if cfg.sync.managedDir != null
        then toString cfg.sync.managedDir
        else "${emacsConfigDir}";
      emacsDirExpr =
        if cfg.sync.emacsDir != null
        then lib.escapeShellArg cfg.sync.emacsDir
        else if cfg.bootstrap.emacsDir != null
        then lib.escapeShellArg cfg.bootstrap.emacsDir
        else "\"\${EMACSDIR:-$HOME/.emacs.d}\"";
      syncArgs = [
        "${dotfilesCli}/bin/dotfiles"
        "sync"
        "emacs"
        "--managed-dir"
        managedDirArg
        "--apply"
      ];
    in
    {
      home-manager.sharedModules = [
        ({ ... }: {
          home.activation.refreshEmacsPlusNativeCompEnv = lib.mkOrder 880 ''
            ${refreshEmacsPlusNativeCompEnv}/bin/dotfiles-refresh-emacs-plus-native-comp-env
          '';
        })
      ] ++ lib.optional (cfg.sync.enable || cfg.bootstrap.enable) ({ ... }: {
        home.activation.syncEmacsConfig = lib.mkOrder 890 ''
          export PATH="/usr/bin:/bin:${runtimePath}:$PATH"
          if command -v xcrun >/dev/null 2>&1; then
            xcode_as="$(xcrun -find as 2>/dev/null || true)"
            if [ -n "$xcode_as" ]; then
              xcode_as_dir="$(dirname "$xcode_as")"
              export PATH="$xcode_as_dir:$PATH"
            fi
          fi
          emacs_dir=${emacsDirExpr}
          ${lib.escapeShellArgs syncArgs} --emacs-dir "$emacs_dir"
        '';
      });
    };
}
