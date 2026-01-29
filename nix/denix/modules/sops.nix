{ delib, pkgs, lib, inputs, ... }:

let
  localSecrets = import (inputs.secrets + "/secrets.nix");
  secretFiles = localSecrets.files or {};
  hasSecrets = secretFiles != {};

  mkTargetPath = homeDir: targetPath:
    if lib.hasPrefix "/" targetPath then targetPath else "${homeDir}/${targetPath}";

  mkSecret = homeDir: name: entry: let
    targetPath = entry.targetPath or ".config/dotfiles/secrets/${name}";
  in {
    sopsFile = entry.sopsFile;
    path = mkTargetPath homeDir targetPath;
    mode = entry.mode or "0600";
  };
in
delib.module {
  name = "sops";

  options.sops = with delib.options; {
    enable = boolOption false;
  };

  home.ifEnabled = { cfg, myconfig, ... }: let
    homeDir = myconfig.facts.user.homeDirectory or myconfig.constants.homeDirectory or "";
    secrets = lib.mapAttrs (name: entry: mkSecret homeDir name entry) secretFiles;
  in {
    home.packages = [ pkgs.sops pkgs.age ];

    sops = lib.mkIf hasSecrets {
      age.keyFile = "${homeDir}/.config/sops/age/keys.txt";
      secrets = secrets;
    };
  };

  darwin.ifEnabled = { cfg, myconfig, ... }: let
    homeDir = myconfig.facts.user.homeDirectory or myconfig.constants.homeDirectory or "";
    userName = myconfig.facts.user.username or myconfig.constants.username or "";
    secrets = lib.mapAttrs (name: entry:
      (mkSecret homeDir name entry)
      // (lib.optionalAttrs (userName != "") { owner = userName; })
    ) secretFiles;
  in {
    environment.systemPackages = [ pkgs.sops pkgs.age ];

    sops = lib.mkIf hasSecrets {
      age.keyFile = "${homeDir}/.config/sops/age/keys.txt";
      secrets = secrets;
    };
  };
}
