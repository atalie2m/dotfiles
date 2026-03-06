{ delib, lib, pkgs, dotlib, ... }:

# Pure prompt configuration

delib.module {
  name = "tools.shell.pure";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = dotlib.mkEnableDefault "tools.shell.pure.enable";
  };

  home.ifEnabled = { myconfig, ... }:
    let
      zshEnabled = (((myconfig.tools or { }).shell or { }).zsh or { }).enable or false;
    in
    lib.mkIf zshEnabled {
      home.packages = [ pkgs.pure-prompt ];

      programs.zsh.initContent = lib.mkOrder 1000 ''
        fpath+=(${pkgs.pure-prompt}/share/zsh/site-functions)
        autoload -Uz promptinit
        promptinit
        prompt pure
      '';
    };
}
