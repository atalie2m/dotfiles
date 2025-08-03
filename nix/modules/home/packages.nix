{ pkgs, ... }:

{
  home.packages = with pkgs; [
    # shell utilities
    zsh
    fish
    starship

    # development tools
    gh
    git
    gnupg
    curl
    wget

    # coding agents
    pinentry_mac
    claude-code
    codex
    gemini-cli
  ];
}
