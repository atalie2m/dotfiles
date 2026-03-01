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
