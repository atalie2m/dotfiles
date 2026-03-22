{ delib, lib, pkgs, repoPaths, ... }:

# Shell tool group

delib.module {
  name = "tools.shell";

  options = with delib; moduleOptions {
    enable = boolOption false;
    manageSystemShells = boolOption false;
    defaultShell = strOption "zsh";
    extraAliases = attrsOption { };
  };

  home.ifEnabled = { cfg, ... }:
    let
      commonShellPath = repoPaths.apps + "/shell/common.sh";
    in
    {
      home = {
        shellAliases = {
          ll = "ls -la";
          la = "ls -A";
          l = "ls -CF";

          dev = "nix develop --command zsh";
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
        source = commonShellPath;
      };
    };

  darwin.ifEnabled = { cfg, myconfig, ... }:
    let
      userName = myconfig.hostContext.user.username;
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
              message = "tools.shell.manageSystemShells requires myconfig.hostContext.user.username.";
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
