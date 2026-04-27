let
  supportedProfiles = [
    "minimal"
    "lite"
    "pro"
    "ultra"
  ];

  powerUserOverrides = {
    tools.terminal.tmux.enable = true;
    tools.system.macAppUtil = {
      enable = true;
      systemService.enable = false;
      homeTrampolines.timeoutSeconds = 15;
    };
  };
in
{
  inherit supportedProfiles;

  hosts = {
    own_mac = {
      name = "own_mac";
      defaultProfile = "pro";
      buildTarget = "own_mac";
      inherit supportedProfiles;
      machineKey = "own_mac";
      system = "aarch64-darwin";
      extraMyconfig = powerUserOverrides;
    };

    work_mac = {
      name = "work_mac";
      defaultProfile = "pro";
      buildTarget = "work_mac";
      inherit supportedProfiles;
      machineKey = "work_mac";
      system = "aarch64-darwin";
      extraMyconfig = powerUserOverrides;
    };
  };
}
