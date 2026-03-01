{ delib, lib, pkgs, ... }:

# Shell tool group

delib.module {
  name = "tools.shell";

  options = with delib; moduleOptions {
    enable = boolOption false;
    manageSystemShells = boolOption false;
    defaultShell = strOption "zsh";
    extraAliases = attrsOption { };
  };

  home.ifEnabled = { cfg, ... }: {
    home = {
      shellAliases = {
        ll = "ls -la";
        la = "ls -A";
        l = "ls -CF";

        dev = "nix develop";
        build = "nix build";
        run = "nix run";
        search = "nix search";

        gs = "git status";
        ga = "git add";
        gc = "git commit";
        gp = "git push";
        gl = "git log --oneline";
      } // cfg.extraAliases;

      sessionPath = lib.optional pkgs.stdenv.isDarwin "${pkgs.coreutils}/libexec/gnubin";
    };

    xdg.configFile."shell/common.sh" = {
      force = true;
      text = ''
        psgrep() {
          if [[ -z "''${1:-}" ]]; then
            echo "Usage: psgrep <pattern>" >&2
            return 1
          fi

          if command -v rg >/dev/null 2>&1; then
            ps aux | rg -i -- "$1"
          else
            ps aux | grep -i -- "$1" | grep -v "[g]rep"
          fi
        }

        if [[ $- == *i* ]]; then
          if command -v gpgconf >/dev/null 2>&1; then
            gpgAgentSshSocket="$(gpgconf --list-dirs agent-ssh-socket 2>/dev/null || true)"
            if [[ -n "''${gpgAgentSshSocket:-}" ]] && { [[ -z "''${SSH_AUTH_SOCK:-}" ]] || [[ ! -S "''${SSH_AUTH_SOCK}" ]]; }; then
              export SSH_AUTH_SOCK="''${gpgAgentSshSocket}"
            fi
          fi

          gpgTty="$(tty 2>/dev/null || true)"
          if [[ -n "''${gpgTty:-}" ]] && [[ "''${gpgTty}" != "not a tty" ]]; then
            export GPG_TTY="''${gpgTty}"
          fi
        fi

        if [[ $- == *i* ]] && [[ -n "''${IN_NIX_SHELL:-}" ]]; then
          echo "Nix develop environment active"
          if [[ -n "''${DEVENV_PROFILE:-}" ]]; then
            echo "Environment: ''${DEVENV_PROFILE}"
          elif [[ -n "''${NIX_SHELL_NAME:-}" ]]; then
            echo "Environment: ''${NIX_SHELL_NAME}"
          fi
        fi
      '';
    };
  };

  darwin.ifEnabled = { cfg, myconfig, ... }:
    let
      userName = myconfig.facts.user.username or myconfig.constants.username or "";
      shellPackages = {
        zsh = pkgs.zsh;
        bash = pkgs.bashInteractive;
      };
      selectedShell = shellPackages.${cfg.defaultShell} or null;
    in
    {
      assertions =
        if cfg.manageSystemShells then
          [
            {
              assertion = lib.elem cfg.defaultShell (builtins.attrNames shellPackages);
              message = "tools.shell.defaultShell must be one of: zsh, bash.";
            }
            {
              assertion = userName != "";
              message = "tools.shell.manageSystemShells requires facts.user.username.";
            }
          ]
        else
          [ ];

      environment.shells =
        lib.optional cfg.manageSystemShells pkgs.zsh
        ++ lib.optional cfg.manageSystemShells pkgs.bashInteractive;

      users.users = lib.mkIf (cfg.manageSystemShells && userName != "" && selectedShell != null) {
        ${userName}.shell = lib.mkDefault selectedShell;
      };
    };
}
