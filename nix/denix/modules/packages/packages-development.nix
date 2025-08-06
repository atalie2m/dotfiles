{ delib, lib, pkgs, ... }:

# Development tools and utilities
delib.module {
  name = "packages.development";

  options.packages.development = with delib.options; {
    enable = boolOption false;
    includeLanguageTools = boolOption true;
    includeVersionControl = boolOption true;
    extraPackages = listOfOption package [];
  };

  home.ifEnabled = { cfg, myconfig, ... }: {
    home.packages = with pkgs; [
      # GitHub CLI and tools
      gh
      git
      git-lfs
      
      # Security and encryption
      gnupg
      pinentry_mac
      
      # AI coding assistants - check if available in nixpkgs
      # claude-code
      
    ] ++ (lib.optionals cfg.includeLanguageTools [
      # Language tools
      nodejs
      python3
      go
      
    ]) ++ (lib.optionals cfg.includeVersionControl [
      # Additional version control
      mercurial
      
    ]) ++ cfg.extraPackages;
  };
}