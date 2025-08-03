{ pkgs, lib, ... }:

let
  terminalConfigScript = pkgs.writeScript "configure-terminal" ''
    #!/usr/bin/osascript

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
  # Terminal.app font configuration using AppleScript
  # More maintainable than direct plist manipulation

  home.activation.configureTerminal = lib.hm.dag.entryAfter ["writeBoundary"] ''
    $DRY_RUN_CMD ${terminalConfigScript}
  '';
}
