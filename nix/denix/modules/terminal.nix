{ delib, lib, pkgs, ... }:

delib.module {
  name = "terminal";

  options.terminal = with delib.options; {
    enable = boolOption false;
    rio.enable = boolOption true;
    terminalApp.enable = boolOption true;
  };

  home.ifEnabled = { cfg, ... }: let
    terminalConfigScript = pkgs.writeText "configure-terminal.scpt" ''
      set targetFont to "0xProto Nerd Font"
      set targetSize to 11
      set profileName to "Atalie's dotfiles - Standard"

      tell application "Terminal"
        activate

        -- Create or get profile
        try
          set protoSettings to settings set profileName
        on error
          set newSettings to (default settings)
          set name of newSettings to profileName
          set protoSettings to newSettings
        end try

        -- Apply font settings
        try
          set font name of protoSettings to targetFont
          set font size of protoSettings to targetSize
          set default settings to protoSettings
          set startup settings to protoSettings
        on error
          display dialog "Failed to set font '" & targetFont & "'. Font may not be installed." buttons {"OK"} default button "OK" with icon caution
        end try
      end tell
    '';
  in {
    programs.rio = lib.mkIf cfg.rio.enable {
      enable = true;
      settings = {
        fonts = {
          family = "0xProto Nerd Font";
          size = 11;
        };

        window = {
          opacity = 0.8;
        };
      };
    };

    home.activation.configureTerminal = lib.mkIf cfg.terminalApp.enable (
      lib.mkOrder 600 ''
        $DRY_RUN_CMD /usr/bin/osascript ${terminalConfigScript}
      ''
    );
  };
}
