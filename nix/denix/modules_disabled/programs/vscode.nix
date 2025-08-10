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

    # Load lockfile with sha256 for marketplace extensions if present
    readLock = path:
      if builtins.pathExists path
      then builtins.fromJSON (builtins.readFile path)
      else [];

    # Convert extensions-min.json (id, version) + lock (sha256) to marketplace spec
    mkMarketplaceList = profile: let
      minPath  = ../../../../apps/vscode/${profile}/extensions-min.json;
      lockPath = ../../../../apps/vscode/${profile}/extensions.lock.json;
      minList  = if builtins.pathExists minPath then builtins.fromJSON (builtins.readFile minPath) else [];
      lockList = readLock lockPath;
      lockById = builtins.listToAttrs (map (e: { name = e.id; value = e; }) lockList);
    in
      builtins.filter (x: x != null)
        (map (e: let
          parts = lib.splitString "." e.id;
          publisher = builtins.elemAt parts 0;
          name = builtins.elemAt parts 1;
          lock = lockById.${e.id} or null;
        in if lock == null then null else {
          inherit name publisher;
          inherit (e) version;
          inherit (lock) sha256;
        }) minList);
  in {
    programs.vscode = lib.mkIf cfg.enable {
      enable  = true;
      package = pkgs.vscode;
      profiles = {
        default = {
          enableUpdateCheck          = true;
          enableExtensionUpdateCheck = true;
          userSettings               = builtins.fromJSON settingsDefault;
          extensions                 = [];
        };
        # Additional profiles sourced from apps/vscode/*
        web = {
          userSettings = builtins.fromJSON settingsWeb;
          extensions   = pkgs.vscode-utils.extensionsFromVscodeMarketplace (mkMarketplaceList "web");
        };
        writing = {
          userSettings = builtins.fromJSON settingsWriting;
          extensions   = pkgs.vscode-utils.extensionsFromVscodeMarketplace (mkMarketplaceList "writing");
        };
        rust = {
          userSettings = {};
          extensions   = pkgs.vscode-utils.extensionsFromVscodeMarketplace (mkMarketplaceList "rust");
        };
      };
    };

    # Note: We intentionally do not link classic User/settings.json; VSCode Profiles
    # reads settings from profiles/Default/settings.json in recent versions and Home
    # Manager manages that file directly.
  };
}


