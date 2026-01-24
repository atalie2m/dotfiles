{ delib, pkgs, lib, ... }:

delib.module {
  name = "sops";

  options.sops = with delib.options; {
    # Enable installs sops/age CLIs only (no sops-nix integration here)
    enable = boolOption false;
  };

  # Home Manager: only install CLI tools
  home.ifEnabled = { cfg, ... }: {
    home.packages = [ pkgs.sops pkgs.age ];
  };

  # nix-darwin: only install CLI tools
  darwin.ifEnabled = { cfg, ... }: {
    environment.systemPackages = [ pkgs.sops pkgs.age ];
  };
}
