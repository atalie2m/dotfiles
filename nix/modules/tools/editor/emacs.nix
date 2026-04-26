{ delib, lib, dotlib, inputs, pkgs, repoPaths, ... }:

let
  homebrewOwnership = import (repoPaths.catalog + "/tools/homebrew-ownership.nix");
  homebrewSpec = homebrewOwnership."editor.emacs";
  dotfilesCli = pkgs.callPackage ../../../pkgs/dotfiles-cli { };
  types = lib.types;
in

# Emacs (GUI via Homebrew) + Doom user configuration

delib.module {
  name = "tools.editor.emacs";

  options = with delib; args:
    (moduleOptions
      {
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
      }
      args)
  ;

  myconfig.ifEnabled = { myconfig, ... }:
    dotlib.ifDarwin myconfig (dotlib.requireHomebrewSpec homebrewSpec);

  home.ifEnabled = { ... }:
    let
      emacsDir = repoPaths.apps + "/emacs";
      doomDir = emacsDir + "/doom";
      iconPath = emacsDir + "/emacs-icon-1.0.icns";
      hasIcon = builtins.pathExists iconPath;
      doomBootstrap = pkgs.writeShellApplication {
        name = "dotfiles-doom";
        runtimeInputs = with pkgs; [
          fd
          git
          ripgrep
        ];
        text = ''
          command="''${1:-sync}"
          emacsdir="''${EMACSDIR:-$HOME/.config/emacs}"
          doomdir="''${DOOMDIR:-$HOME/.config/doom}"

          ensure_doom_config() {
            if [ ! -e "$doomdir/init.el" ]; then
              ${dotfilesCli}/bin/dotfiles sync emacs --apply --managed-dir "${doomDir}" --doom-dir "$doomdir"
            fi
          }

          if [ ! -e "$doomdir/init.el" ]; then
            case "$command" in
              bootstrap|install)
                ensure_doom_config
                ;;
              *)
                printf 'Doom config is missing at %s. Run: dotfiles sync emacs --apply\n' "$doomdir" >&2
                exit 1
                ;;
            esac
          fi

          case "$command" in
            bootstrap|install)
              if [ ! -x "$emacsdir/bin/doom" ]; then
                if [ -e "$emacsdir" ]; then
                  printf '%s exists but does not look like a Doom Emacs checkout.\n' "$emacsdir" >&2
                  exit 1
                fi
                git clone --depth 1 https://github.com/doomemacs/doomemacs "$emacsdir"
                "$emacsdir/bin/doom" install
              else
                "$emacsdir/bin/doom" sync
              fi
              ;;
            sync)
              if [ ! -x "$emacsdir/bin/doom" ]; then
                printf 'Doom is not installed at %s. Run: dotfiles-doom bootstrap\n' "$emacsdir" >&2
                exit 1
              fi
              "$emacsdir/bin/doom" sync
              ;;
            doctor)
              if [ ! -x "$emacsdir/bin/doom" ]; then
                printf 'Doom is not installed at %s. Run: dotfiles-doom bootstrap\n' "$emacsdir" >&2
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

  darwin.ifEnabled = { cfg, ... }:
    let
      runtimePath = lib.makeBinPath [
        pkgs.bash
        pkgs.coreutils
        pkgs.diffutils
        dotfilesCli
      ];
      managedDirArg =
        if cfg.sync.managedDir != null
        then toString cfg.sync.managedDir
        else "${repoPaths.apps}/emacs/doom";
      doomDirExpr =
        if cfg.sync.doomDir != null
        then lib.escapeShellArg cfg.sync.doomDir
        else "\"\${DOOMDIR:-$HOME/.config/doom}\"";
      applyArgs = [
        "${dotfilesCli}/bin/dotfiles"
        "sync"
        "emacs"
        "--managed-dir"
        managedDirArg
        "--apply"
      ];
    in
    {
      home-manager.sharedModules = lib.optional cfg.sync.enable ({ ... }: {
        home.activation.syncEmacsDoom = lib.mkOrder 890 ''
          export PATH="${runtimePath}:$PATH"
          doom_dir=${doomDirExpr}
          ${lib.escapeShellArgs applyArgs} --doom-dir "$doom_dir"
        '';
      });
    };
}
