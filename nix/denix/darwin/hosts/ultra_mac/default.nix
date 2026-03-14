args:

let
  mkDarwinHost = import ../../../lib/mk-darwin-host.nix args;
in
mkDarwinHost {
  name = "ultra_mac";
  rice = "ultra";
  machineKey = "ultra_mac";
  extraMyconfig = {
    tools.terminal.tmux.enable = true;
    tools.system.macAppUtil = {
      enable = true;
      systemService.enable = false;
      homeTrampolines.syncDock = true;
      homeTrampolines.timeoutSeconds = 15;
    };
  };
}
