let
  supportedRices = [
    "base"
    "darwin"
    "dev"
    "partial"
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
  inherit supportedRices;

  hosts = {
    minimal_mac = {
      name = "minimal_mac";
      defaultRice = "base";
      buildTarget = "minimal_mac";
      inherit supportedRices;
      machineKey = "minimal_mac";
      system = "aarch64-darwin";
      extraMyconfig = { };
    };

    pro_mac = {
      name = "pro_mac";
      defaultRice = "pro";
      buildTarget = "pro_mac";
      inherit supportedRices;
      machineKey = "pro_mac";
      system = "aarch64-darwin";
      extraMyconfig = powerUserOverrides;
    };

    ultra_mac = {
      name = "ultra_mac";
      defaultRice = "ultra";
      buildTarget = "ultra_mac";
      inherit supportedRices;
      machineKey = "ultra_mac";
      system = "aarch64-darwin";
      extraMyconfig = powerUserOverrides;
    };
  };
}
