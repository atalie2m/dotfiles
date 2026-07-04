{ dotmod, config, lib, pkgs, ... }:

# direnv + nix-direnv shell integration

(dotmod.mkModule { inherit config; }) {
  path = "tools.shell.direnv";

  options = with dotmod; moduleOptions {
    enable = boolOption false;
  };

  homeOnEnable = { myconfig, ... }:
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
        export PATH="${lib.makeBinPath [ pkgs.direnv ]}:$PATH"
        eval "$(${lib.getExe pkgs.direnv} hook zsh)"
      '';
    };
}
