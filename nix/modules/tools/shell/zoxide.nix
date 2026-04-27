{ dotmod, config, lib, pkgs, ... }:

# zoxide directory jumping

(dotmod.mkModule { inherit config; }) {
  path = "tools.shell.zoxide";

  options = with dotmod; moduleOptions {
    enable = boolOption false;
  };

  homeOnEnable = { myconfig, ... }:
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
        export PATH="${lib.makeBinPath [ pkgs.zoxide ]}:$PATH"
        eval "$(${lib.getExe pkgs.zoxide} init zsh)"
      '';
    };
}
