{ delib, lib, dotlib, inputs, pkgs, repoPaths, ... }:

let
  homebrewOwnership = import (repoPaths.catalog + "/tools/homebrew-ownership.nix");
  homebrewSpec = homebrewOwnership."editor.emacs";
  dotfilesCli = pkgs.callPackage ../../../pkgs/dotfiles-cli { };
  types = lib.types;
  emacsDir = repoPaths.apps + "/emacs";
  doomConfigDir = emacsDir + "/doom";
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
          ${dotfilesCli}/bin/dotfiles sync emacs --apply --managed-dir "${doomConfigDir}" --doom-dir "$doomdir"
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
        bootstrap = {
          enable = boolOption false;
          emacsDir = lib.mkOption {
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
        ".emacs.d/early-init.el" = {
          force = true;
          text = ''
            ;;; early-init.el --- Redirect legacy ~/.emacs.d to Doom -*- lexical-binding: t; -*-

            (let* ((doom-emacs-dir
                    (file-name-as-directory
                     (or (getenv "EMACSDIR")
                         (expand-file-name "emacs" (or (getenv "XDG_CONFIG_HOME") "~/.config")))))
                   (doom-early-init-file (expand-file-name "early-init.el" doom-emacs-dir)))
              (setq user-emacs-directory doom-emacs-dir
                    user-init-file (expand-file-name "init.el" doom-emacs-dir))
              (when (file-exists-p doom-early-init-file)
                (load doom-early-init-file nil t)))
          '';
        };
        ".emacs.d/init.el" = {
          force = true;
          text = ''
            ;;; init.el --- Redirect legacy ~/.emacs.d to Doom -*- lexical-binding: t; -*-

            (let ((doom-emacs-dir
                   (file-name-as-directory
                    (or (getenv "EMACSDIR")
                        (expand-file-name "emacs" (or (getenv "XDG_CONFIG_HOME") "~/.config"))))))
              (setq user-emacs-directory doom-emacs-dir
                    user-init-file (expand-file-name "init.el" doom-emacs-dir))
              (if (file-exists-p user-init-file)
                  (load user-init-file nil t)
                (user-error "Doom Emacs is not installed at %s. Run: dotfiles-doom bootstrap" doom-emacs-dir)))
          '';
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

  darwin.ifEnabled = { cfg, ... }:
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
        else "\"\${EMACSDIR:-$HOME/.config/emacs}\"";
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
      home-manager.sharedModules =
        (lib.optional cfg.sync.enable ({ ... }: {
          home.activation.syncEmacsDoom = lib.mkOrder 890 ''
            export PATH="${runtimePath}:$PATH"
            doom_dir=${doomDirExpr}
            ${lib.escapeShellArgs applyArgs} --doom-dir "$doom_dir"
          '';
        }))
        ++ (lib.optional cfg.bootstrap.enable ({ ... }: {
          home.activation.bootstrapDoomEmacs = lib.mkOrder 895 ''
            export PATH="${runtimePath}:$PATH"
            emacs_dir=${emacsDirExpr}
            doom_dir=${doomDirExpr}
            if [[ -x "$emacs_dir/bin/doom" ]]; then
              echo "emacs bootstrap: Doom already installed at $emacs_dir; skipping"
            else
              export EMACSDIR="$emacs_dir"
              export DOOMDIR="$doom_dir"
              ${doomBootstrap}/bin/dotfiles-doom bootstrap
            fi
          '';
        }));
    };
}
