{ delib, lib, dotlib, inputs, pkgs, repoPaths, ... }:

let
  homebrewOwnership = import (repoPaths.catalog + "/tools/homebrew-ownership.nix");
  homebrewSpec = homebrewOwnership."editor.emacs";
in

# Emacs (GUI via Homebrew) + Doom user configuration

delib.module {
  name = "tools.editor.emacs";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

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

          if [ ! -e "$doomdir/init.el" ]; then
            printf 'Doom config is missing at %s. Apply dotfiles first.\n' "$doomdir" >&2
            exit 1
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
        ".config/doom/init.el" = {
          force = true;
          source = doomDir + "/init.el";
        };
        ".config/doom/packages.el" = {
          force = true;
          source = doomDir + "/packages.el";
        };
        ".config/doom/config.el" = {
          force = true;
          source = doomDir + "/config.el";
        };
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
}
