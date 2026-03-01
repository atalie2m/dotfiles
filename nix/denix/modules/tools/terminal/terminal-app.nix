{ delib, lib, pkgs, ... }:

# macOS Terminal.app configuration

delib.module {
  name = "tools.terminal.terminalApp";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = { parent, ... }: {
      tools.terminal.terminalApp.enable = lib.mkDefault parent.enable;
    };
  };

  home.ifEnabled = { ... }:
    let
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
    in
    {
      home.activation.configureTerminal = lib.mkIf true (
        lib.mkOrder 600 ''
          $DRY_RUN_CMD /usr/bin/osascript ${terminalConfigScript}
        ''
      );
    };
}
