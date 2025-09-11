{ delib, pkgs, inputs, ... }:

let
  env = import ../../env.nix;
  keyFilePath = "${env.homeDirectory}/${env.configDirectory}/sops/age/keys.txt";
in
delib.module {
  name = "sops";

  options.sops = with delib.options; {
    enable = boolOption false;
    # Install only sops/age CLIs without configuring sops-nix
    cliOnly = boolOption false;

    age = {
      # Where the local age key is stored
      keyFile = strOption keyFilePath;
      # Auto-generate a key on first switch if missing
      generateKey = boolOption true;
    };
  };

  # Home Manager integration (for user-scoped secrets usage)
  # Install CLIs when either cliOnly or enable is set
  home.when = { cfg, ... }: cfg.cliOnly || cfg.enable; { pkgs, ... }: {
    home.packages = [ pkgs.sops pkgs.age ];
  };

  home.ifEnabled = { cfg, ... }: {
    # Import sops-nix Home Manager module
    imports = [ inputs.sops-nix.homeManagerModules.sops ];

    sops.age = {
      keyFile = cfg.age.keyFile;
      generateKey = cfg.age.generateKey;
    };
  };

  # nix-darwin integration (for system-scoped secrets if needed)
  darwin.when = { cfg, ... }: cfg.cliOnly || cfg.enable; { pkgs, ... }: {
    environment.systemPackages = [ pkgs.sops pkgs.age ];
  };

  darwin.ifEnabled = { cfg, ... }: {
    # Import sops-nix darwin module
    imports = [ inputs.sops-nix.darwinModules.sops ];

    sops.age = {
      keyFile = cfg.age.keyFile;
      generateKey = cfg.age.generateKey;
    };
  };
}
