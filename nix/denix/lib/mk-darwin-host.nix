{ delib, lib, dotlib, inputs, ... }:

{ name
, rice
, machineKey
, extraMyconfig ? { }
,
}:

let
  context = dotlib.mkHostContext {
    inherit inputs name machineKey;
    resolveHomeDirectory = { username, user, ... }:
      let
        defaultHomeDirectory = if username != "" then "/Users/${username}" else "";
      in
        user.homeDirectory or defaultHomeDirectory;
    resolvePlatform = { machine, user, ... }:
      let
        machinePlatform = machine.platform or "";
        userPlatform = user.platform or "";
      in
      if machinePlatform != "" then machinePlatform
      else if userPlatform != "" then userPlatform
      else "aarch64-darwin";
  };
  nixPackage = inputs.nixpkgs.legacyPackages.${context.platform}.nix;
in
delib.host {
  inherit name rice;
  type = "desktop";
  homeManagerSystem = context.platform;

  myconfig = lib.recursiveUpdate
    {
      facts = {
        user = context.effectiveUser;
        inherit (context) machine machines;
        binaryCaches = context.facts.binaryCaches or { };
      };
    }
    extraMyconfig;

  home = { ... }: {
    imports = [ inputs.sops-nix.homeManagerModules.sops ];
    nix.package = lib.mkDefault nixPackage;
    home = {
      inherit (context) username homeDirectory;
      stateVersion = context.stateVersion.home or "25.11";
    };
  };

  darwin = { ... }:
    let
      userName = context.username;
      homeDir = context.homeDirectory;
    in
    {
      imports = [ inputs.sops-nix.darwinModules.sops ];
      nix.package = lib.mkDefault nixPackage;
      system.stateVersion = context.stateVersion.darwin or 6;
      nixpkgs.hostPlatform = context.platform;
      system.primaryUser = userName;

      users.users.${userName} = {
        name = userName;
        home = homeDir;
      };
    };
}
