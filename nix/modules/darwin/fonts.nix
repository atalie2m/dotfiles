{ pkgs, ... }:

{
  fonts.packages = with pkgs; [
    # Nerd Fonts (for terminal and code editors)
    nerd-fonts.jetbrains-mono
    nerd-fonts._0xproto

    # Google Fonts
    roboto
    roboto-mono
  ];
}