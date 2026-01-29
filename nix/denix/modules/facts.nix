{ delib, ... }:

# Local machine facts (sourced from inputs.local/facts.nix)
delib.module {
  name = "facts";

  options.facts = with delib.options; {
    user = {
      username = strOption "";
      fullName = strOption "";
      email = strOption "";
      homeDirectory = strOption "";
      platform = strOption "";
      configDirectory = strOption ".config";
      dotfilesPath = strOption "";
      systemType = strOption "";
      architecture = strOption "";
      stateVersion = {
        home = strOption "25.05";
        darwin = intOption 6;
      };
    };

    machines = attrsOption {};
    machine = attrsOption {};
  };
}
