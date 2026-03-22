{ delib, lib, pkgs, ... }:

# zoxide directory jumping

delib.module {
  name = "tools.shell.zoxide";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  home.ifEnabled = { myconfig, ... }:
    let
      zshEnabled = (((myconfig.tools or { }).shell or { }).zsh or { }).enable or false;
    in
    lib.mkIf zshEnabled {
      programs.zoxide = {
        enable = true;
        enableBashIntegration = false;
        enableFishIntegration = false;
        enableNushellIntegration = false;
        enableZshIntegration = false;
      };

      programs.zsh.initContent = lib.mkOrder 1080 ''
        eval "$(${lib.getExe pkgs.zoxide} init zsh)"
      '';
    };
}
