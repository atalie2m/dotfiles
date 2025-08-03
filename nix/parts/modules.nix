{
  flake = {
    nixosModules = {
      darwin = ../modules/darwin;
      home = ../modules/home;
    };

    darwinModules = {
      default = ../modules/darwin;
      homebrew = ../modules/homebrew;
      darwin-base = ../hosts;
      standard-host = ../profiles/standard/darwin/standard.nix;
      commercial-host = ../profiles/commercial/darwin/commercial.nix;
    };

    homeManagerModules = {
      default = ../modules/home;
    };
  };
}
