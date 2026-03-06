{ delib, lib, dotlib, ... }:

# Fish configuration

delib.module {
  name = "tools.shell.fish";

  options = with delib; moduleOptions {
    enable = boolOption false;
    generateCompletions = boolOption true;
  };

  myconfig = {
    always = dotlib.mkEnableDefault "tools.shell.fish.enable";
  };

  home.ifEnabled = { cfg, ... }: {
    programs.fish = {
      enable = true;
      inherit (cfg) generateCompletions;
    };

    # Keep Home Manager generated fish config in a separate immutable layer.
    # The runtime ~/.config/fish/config.fish entrypoint is managed as a writable wrapper.
    xdg.configFile."fish/config.fish".target = lib.mkForce "fish/hm-fish/config.fish";
  };
}
