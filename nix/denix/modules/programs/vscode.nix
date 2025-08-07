{ delib, lib, pkgs, ... }:

delib.module {
  name = "vscode";

  # Enable VSCode through Home Manager using apps/vscode/_default
  options.vscode = with delib.options; {
    enable = boolOption false;
  };

  home.ifEnabled = { cfg, ... }: let
    settings   = builtins.readFile ../../../../apps/vscode/_default/settings.json;
    extensionsTxt = builtins.readFile ../../../../apps/vscode/_default/extensions.txt;
  in {
    programs.vscode = lib.mkIf cfg.enable {
      enable                = true;
      package               = pkgs.vscode;
      mutableExtensionsDir  = true;
      profiles.Default = {
        enableUpdateCheck          = true;
        enableExtensionUpdateCheck = true;
        userSettings               = builtins.fromJSON settings;
        extensions                 = lib.filter (s: s != "") (lib.strings.splitString "\n" extensionsTxt);
      };
    };
  };
}