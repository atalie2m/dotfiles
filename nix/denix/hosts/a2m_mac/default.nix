args@{ ... }:

let
  mkDarwinHost = import ../../lib/mk-darwin-host.nix args;
in
mkDarwinHost {
  name = "a2m_mac";
  rice = "full";
  machineKey = "a2m_mac";
  extraMyconfig = {
    tools.terminal.tmux.enable = true;
    tools.system.macAppUtil = {
      enable = true;
      systemService.enable = false;
      homeTrampolines.syncDock = true;
      homeTrampolines.timeoutSeconds = 15;
    };
    tools.editor.vscode.appLaunchers.displayNames = {
      python = "VSC - Python";
      web = "VSC - Web";
      writing = "VSC - Writing";
      native = "VSC - Default";
    };
  };
}
