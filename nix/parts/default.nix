# Flake parts - modular flake configuration
{
  imports = [
    ./darwin.nix
    ./home.nix
    ./modules.nix
  ];
}