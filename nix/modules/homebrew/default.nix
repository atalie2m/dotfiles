{ config, pkgs, brew-nix, ... }:

{
  # 1. overlay を明示的に追加
  nixpkgs.overlays = [ brew-nix.overlays.default ];

  # 2. Enable brew-nix
  brew-nix = {
    enable = true;
  };

  # 3. Install applications using brew-nix
  environment.systemPackages = with pkgs; [
    brewCasks.rio    # Rio terminal
    brewCasks.keycue # KeyCue (corrected from keyclu)
  ];
}
