{ pkgs, ... }:

{
  home.packages = with pkgs; [
    git
    gnupg
    curl
    wget
    pinentry_mac
    claude-code
    codex
    gemini-cli
  ];
}