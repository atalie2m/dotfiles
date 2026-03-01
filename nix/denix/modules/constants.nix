{ delib, config, lib, ... }:

let
  user = config.facts.user or { };
  username = user.username or "";
  platform = user.platform or "";
  defaultHomeDirectory =
    if username == "" then ""
    else if lib.hasSuffix "-darwin" platform then "/Users/${username}"
    else "/home/${username}";
in
# Global constants and user information shared across all modules
delib.module {
  name = "constants";

  options.constants = with delib.options; {
    # User identification
    username = readOnly (strOption (user.username or ""));
    fullName = readOnly (strOption (user.fullName or ""));
    email = readOnly (strOption (user.email or ""));

    # System paths
    homeDirectory = readOnly (strOption (user.homeDirectory or defaultHomeDirectory));
    platform = readOnly (strOption platform);
    configDirectory = readOnly (strOption (user.configDirectory or ".config"));

    # System information
    systemType = readOnly (strOption (user.systemType or ""));
    architecture = readOnly (strOption (user.architecture or ""));
  };
}
