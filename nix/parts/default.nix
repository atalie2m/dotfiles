# Flake parts
{
  imports = [
    ../hosts/darwin/configurations.nix
    ./home.nix
    ./modules.nix
  ];
}
