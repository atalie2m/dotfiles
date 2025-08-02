{
  flake = {
    nixosModules = {
      darwin = ../modules/darwin;
      home = ../modules/home;
    };

    darwinModules = {
      default = ../modules/darwin;
      homebrew = ../modules/homebrew;
      darwin-base = ../hosts/darwin;
      standard-host = ../hosts/darwin/profiles/standard.nix;
    };

    homeManagerModules = {
      default = ../modules/home;
    };
  };
}
