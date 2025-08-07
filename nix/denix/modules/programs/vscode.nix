{ delib, lib, pkgs, ... }:

delib.module {
  name = "vscode";

  # Enable VSCode through Home Manager using apps/vscode/_default
  options.vscode = with delib.options; {
    enable = boolOption false;
  };

  home.ifEnabled = { cfg, ... }: let
    settingsDefault = builtins.readFile ../../../../apps/vscode/_default/settings.json;
    settingsWeb     = builtins.readFile ../../../../apps/vscode/web/settings.json;
    settingsWriting = builtins.readFile ../../../../apps/vscode/writing/settings.json;
  in {
    programs.vscode = lib.mkIf cfg.enable {
      enable                = true;
      package               = pkgs.vscode;
      profiles.default = {
        enableUpdateCheck          = true;
        enableExtensionUpdateCheck = true;
        userSettings               = builtins.fromJSON settingsDefault;
        extensions                 = [];
      };

      # Additional profiles sourced from apps/vscode/*
      profiles.web = {
        userSettings               = builtins.fromJSON settingsWeb;
        extensions                 = [];
      };

      profiles.writing = {
        userSettings               = builtins.fromJSON settingsWriting;
        extensions                 = [];
      };

      profiles.rust = {
        userSettings               = {};
        extensions                 = [];
      };
    };

    # Note: We intentionally do not link classic User/settings.json; VSCode Profiles
    # reads settings from profiles/Default/settings.json in recent versions and Home
    # Manager manages that file directly.
  };
}
