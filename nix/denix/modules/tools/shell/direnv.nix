{ delib, lib, pkgs, ... }:

# direnv + nix-direnv shell integration

delib.module {
  name = "tools.shell.direnv";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  home.ifEnabled = { myconfig, ... }:
    let
      zshEnabled = (((myconfig.tools or { }).shell or { }).zsh or { }).enable or false;
    in
    lib.mkIf zshEnabled {
      programs.direnv = {
        enable = true;
        enableBashIntegration = false;
        enableNushellIntegration = false;
        enableZshIntegration = false;
        silent = true;
        nix-direnv.enable = true;
      };

      programs.zsh.initContent = lib.mkOrder 930 ''
        eval "$(${lib.getExe pkgs.direnv} hook zsh)"
      '';
    };
}
