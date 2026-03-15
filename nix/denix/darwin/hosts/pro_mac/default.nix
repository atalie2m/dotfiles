args:

let
  mkDarwinHost = import ../../../lib/mk-darwin-host.nix args;
in
mkDarwinHost {
  name = "pro_mac";
  rice = "pro";
  machineKey = "pro_mac";
  system = "aarch64-darwin";
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
