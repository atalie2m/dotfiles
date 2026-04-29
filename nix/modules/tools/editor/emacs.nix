{ dotmod, config, lib, dotlib, inputs, pkgs, repoPaths, ... }:

let
  homebrewOwnership = import (repoPaths.catalog + "/tools/homebrew-ownership.nix");
  homebrewSpec = homebrewOwnership."editor.emacs";
  dotfilesCli = pkgs.callPackage ../../../pkgs/dotfiles-cli { };
  types = lib.types;
  emacsDir = repoPaths.apps + "/emacs";
  doomConfigDir = emacsDir + "/doom";
  iconPath = emacsDir + "/emacs-icon-1.0.icns";
  hasIcon = builtins.pathExists iconPath;
  refreshEmacsPlusNativeCompEnv = pkgs.writeShellApplication {
    name = "dotfiles-refresh-emacs-plus-native-comp-env";
    runtimeInputs = with pkgs; [
      coreutils
    ];
    text = builtins.readFile ./refresh-emacs-plus-native-comp-env.sh;
  };
  doomBootstrap = pkgs.writeShellApplication {
    name = "dotfiles-doom";
    runtimeInputs = with pkgs; [
      coreutils
      fd
      git
      ripgrep
    ];
    text = ''
      command="''${1:-sync}"
      emacsdir="''${EMACSDIR:-$HOME/.emacs.d}"
      doomdir="''${DOOMDIR:-$HOME/.config/doom}"

      for path in /usr/bin /bin /opt/homebrew/bin /usr/local/bin /Applications/Emacs.app/Contents/MacOS/bin; do
        if [ -d "$path" ]; then
          export PATH="$path:$PATH"
        fi
      done
      if command -v xcrun >/dev/null 2>&1; then
        xcode_as="$(xcrun -find as 2>/dev/null || true)"
        if [ -n "$xcode_as" ]; then
          xcode_as_dir="$(dirname "$xcode_as")"
          export PATH="$xcode_as_dir:$PATH"
        fi
      fi
      if [ -z "''${EMACS:-}" ]; then
        export EMACS="/Applications/Emacs.app/Contents/MacOS/Emacs"
      fi

      case "$command" in
        bootstrap|install)
          ${dotfilesCli}/bin/dotfiles sync emacs --apply --bootstrap --managed-dir "${doomConfigDir}" --doom-dir "$doomdir" --emacs-dir "$emacsdir"
          ;;
        sync)
          if [ ! -x "$emacsdir/bin/doom" ]; then
            printf 'Doom is not installed at %s. Run: nix run .#dotfiles -- sync emacs --apply --bootstrap\n' "$emacsdir" >&2
            exit 1
          fi
          "$emacsdir/bin/doom" sync
          ;;
        doctor)
          if [ ! -x "$emacsdir/bin/doom" ]; then
            printf 'Doom is not installed at %s. Run: nix run .#dotfiles -- sync emacs --apply --bootstrap\n' "$emacsdir" >&2
            exit 1
          fi
          "$emacsdir/bin/doom" doctor
          ;;
        *)
          printf 'usage: dotfiles-doom [bootstrap|install|sync|doctor]\n' >&2
          exit 64
          ;;
      esac
    '';
  };
in

# Emacs (GUI via Homebrew) + Doom user configuration

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
      doomDir = lib.mkOption {
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
        cmigemo
        diffutils
        dotfilesCli
        doomBootstrap
        enchant
        fd
        git
        ripgrep
        sqlite
        (aspellWithDicts (dicts: with dicts; [
          en
        ]))
      ];
      emacsFiles = {
        ".config/doom/modules/editor/meow" = {
          force = true;
          source = inputs.doom-meow;
          recursive = true;
        };
        ".config/doom/snippets/.keep" = {
          text = "";
        };
      } // lib.optionalAttrs hasIcon {
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
        doomBootstrap
      ];
      managedDirArg =
        if cfg.sync.managedDir != null
        then toString cfg.sync.managedDir
        else "${doomConfigDir}";
      doomDirExpr =
        if cfg.sync.doomDir != null
        then lib.escapeShellArg cfg.sync.doomDir
        else "\"\${DOOMDIR:-$HOME/.config/doom}\"";
      emacsDirExpr =
        if cfg.bootstrap.emacsDir != null
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
        home.activation.syncEmacsDoom = lib.mkOrder 890 ''
          export PATH="/usr/bin:/bin:${runtimePath}:$PATH"
          if command -v xcrun >/dev/null 2>&1; then
            xcode_as="$(xcrun -find as 2>/dev/null || true)"
            if [ -n "$xcode_as" ]; then
              xcode_as_dir="$(dirname "$xcode_as")"
              export PATH="$xcode_as_dir:$PATH"
            fi
          fi
          doom_dir=${doomDirExpr}
          emacs_dir=${emacsDirExpr}
          ${lib.optionalString (cfg.sync.enable && !cfg.bootstrap.enable) ''
            ${lib.escapeShellArgs syncArgs} --doom-dir "$doom_dir" --emacs-dir "$emacs_dir"
          ''}
          ${lib.optionalString cfg.bootstrap.enable ''
            export EMACSDIR="$emacs_dir"
            export DOOMDIR="$doom_dir"
            ${doomBootstrap}/bin/dotfiles-doom bootstrap
          ''}
        '';
      });
    };
}
