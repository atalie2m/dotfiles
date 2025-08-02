# Module exports for reusability
{
  flake = {
    # Module exports for reusability
    nixosModules = {
      darwin = ../modules/darwin;
      home = ../modules/home;
    };

    darwinModules = {
      default = ../modules/darwin;
      homebrew = ../modules/homebrew;
      darwin-base = ../hosts/darwin;
      standard-host = ../hosts/darwin/standard;
    };

    homeManagerModules = {
      default = ../modules/home;
    };
  };
}