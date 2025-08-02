# Flake parts - modular flake configuration
{
  imports = [
    ../hosts/darwin/configurations.nix
    ./home.nix
    ./modules.nix
  ];
}