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
    minimal_mac = {
      name = "minimal_mac";
      defaultProfile = "minimal";
      buildTarget = "minimal_mac";
      inherit supportedProfiles;
      machineKey = "minimal_mac";
      system = "aarch64-darwin";
      extraMyconfig = { };
    };

    pro_mac = {
      name = "pro_mac";
      defaultProfile = "pro";
      buildTarget = "pro_mac";
      inherit supportedProfiles;
      machineKey = "pro_mac";
      system = "aarch64-darwin";
      extraMyconfig = powerUserOverrides;
    };

    ultra_mac = {
      name = "ultra_mac";
      defaultProfile = "ultra";
      buildTarget = "ultra_mac";
      inherit supportedProfiles;
      machineKey = "ultra_mac";
      system = "aarch64-darwin";
      extraMyconfig = powerUserOverrides;
    };
  };
}
