{ delib, lib, pkgs, ... }:

# Rio terminal configuration

delib.module {
  name = "tools.terminal.rio";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = { parent, ... }: {
      tools.terminal.rio.enable = lib.mkDefault parent.enable;
    };
    ifEnabled = { myconfig, ... }:
      lib.mkIf (lib.hasSuffix "-darwin" (myconfig.facts.user.platform or "")) {
        tools.system.homebrewNative.enable = lib.mkDefault true;
        tools.system.homebrewNative.casks = lib.mkAfter [ "rio" ];
      };
  };

  home.ifEnabled = { ... }:
    let
      rioSettings = {
        fonts = {
          family = "0xProto Nerd Font";
          size = 11;
        };

        window = {
          opacity = 0.8;
        };
      };
      tomlFormat = pkgs.formats.toml { };
    in
    {
      xdg.configFile = {
        "rio/config.toml".source = tomlFormat.generate "rio.toml" rioSettings;
      };
    };
}
