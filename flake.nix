# This is a routing flake that delegates to the actual flake in the nix/ directory
# This ensures CI and other tools can find a flake.nix at the repository root
# The primary flake remains nix/flake.nix
{
  description = "Router to nix/flake.nix";

  inputs = {
    nixFlake = {
      url = "path:./nix";
    };
  };

  outputs = { nixFlake, ... }: nixFlake;
}
