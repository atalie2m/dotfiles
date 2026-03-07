{ delib, ... }:

# Local machine facts (sourced from inputs.local/facts.nix)
delib.module {
  name = "facts";

  options.facts = with delib.options; {
    user = {
      # Required
      username = strOption "";

      # Optional identity
      fullName = strOption "";
      email = strOption "";

      # Optional overrides (normally derived)
      homeDirectory = strOption "";
      platform = strOption "";
      configDirectory = strOption ".config";
      systemType = strOption "";
      architecture = strOption "";
      stateVersion = {
        home = strOption "25.11";
        darwin = intOption 6;
        nixos = strOption "25.11";
      };
    };

    machines = attrsOption { };
    machine = attrsOption { };

    # Optional binary cache configuration (Cachix/Attic/etc.)
    binaryCaches = {
      substituters = listOfOption str [ ];
      trustedPublicKeys = listOfOption str [ ];
    };
  };
}
