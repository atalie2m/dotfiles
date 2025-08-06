{ delib, ... }:

# System-level Nix configuration
delib.module {
  name = "system.nix";

  options.system.nix = with delib.options; {
    enable = boolOption false;
    enableFlakes = boolOption true;
    enableNixCommand = boolOption true;
    extraExperimentalFeatures = listOfOption str [];
  };

  darwin.ifEnabled = { cfg, ... }: {
    nix.settings = {
      # Enable experimental features
      experimental-features = [
        "nix-command"
        "flakes"
      ] ++ cfg.extraExperimentalFeatures;
      
      # Trusted users for Nix daemon
      trusted-users = [ "@admin" ];
    };
    
    # Enable garbage collection and optimization
    nix.gc = {
      automatic = true;
      interval = { Weekday = 0; Hour = 2; Minute = 0; }; # Sunday at 2 AM
      options = "--delete-older-than 30d";
    };
    
    # Auto-optimize store (modern way)
    nix.optimise.automatic = true;
  };

  home.ifEnabled = { cfg, ... }: {
    # Home Manager Nix settings
    nix.settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ] ++ cfg.extraExperimentalFeatures;
    };
  };
}