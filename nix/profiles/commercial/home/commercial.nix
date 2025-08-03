{ pkgs, lib, ... }:
let
  standardPackages = import ../../../packages/standard.nix { inherit pkgs; };
  banned = with pkgs; [ claude-code codex gemini-cli ];
in {
  home.packages = lib.subtractLists banned standardPackages;
}
