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
    ] ++ (lib.optionals cfg.includeLanguageTools [
      nodejs
      python3
      go

    ]) ++ (lib.optionals cfg.includeVersionControl [
      mercurial

    ]) ++ cfg.extraPackages;
  };
}
