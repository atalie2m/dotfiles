{ dotmod, config, pkgs, lib, inputs, ... }:

let
  localSecretsFile = inputs.secrets + "/secrets.nix";
  localSecrets =
    if builtins.pathExists localSecretsFile then
      import localSecretsFile
    else
    # Missing secrets.nix is an intentional no-op for public evaluation.
      { };
  secretFiles = localSecrets.files or { };
  hasSecrets = secretFiles != { };

  mkTargetPath = homeDir: targetPath:
    if lib.hasPrefix "/" targetPath then targetPath else "${homeDir}/${targetPath}";

  mkSecret = homeDir: name: entry:
    let
      targetPath = entry.targetPath or ".config/dotfiles/secrets/${name}";
    in
    {
      sopsFile = entry.sopsFile;
      path = mkTargetPath homeDir targetPath;
      mode = entry.mode or "0600";
    };

  getHomeDir = myconfig:
    myconfig.hostContext.user.homeDirectory;

  mkSecrets = { homeDir, userName ? "" }:
    lib.mapAttrs
      (name: entry:
        (mkSecret homeDir name entry)
        // (lib.optionalAttrs (userName != "") { owner = userName; })
      )
      secretFiles;
in
(dotmod.mkModule { inherit config; }) {
  path = "tools.security.sops";

  options = with dotmod; moduleOptions {
    enable = boolOption false;
  };

  homeOnEnable = { myconfig, ... }:
    let
      homeDir = getHomeDir myconfig;
      secrets = mkSecrets { inherit homeDir; };
    in
    {
      home.packages = [ pkgs.sops pkgs.age ];

      sops = lib.mkIf hasSecrets {
        age.keyFile = "${homeDir}/.config/sops/age/keys.txt";
        secrets = secrets;
      };
    };

  darwinOnEnable = { myconfig, ... }:
    let
      homeDir = getHomeDir myconfig;
      userName = myconfig.hostContext.user.username;
      secrets = mkSecrets { inherit homeDir userName; };
    in
    {
      sops = lib.mkIf hasSecrets {
        age.keyFile = "${homeDir}/.config/sops/age/keys.txt";
        secrets = secrets;
      };
    };
}
