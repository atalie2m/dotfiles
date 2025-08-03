{ pkgs, lib, ... }:

let
  # NSfont object for 0xProto Nerd Font
  fontData = builtins.readFile ./font.data;
in
{
  # Terminal.app font settings - using extracted NSFont blob for 0xProto Nerd Font
  # Font blob extracted from manually configured Terminal.app Basic profile

  home.file."Library/Preferences/com.apple.Terminal.plist".text = ''
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>Default Window Settings</key>
      <string>0xProto</string>
      <key>Startup Window Settings</key>
      <string>0xProto</string>
      <key>Window Settings</key>
      <dict>
        <key>0xProto</key>
        <dict>
          <key>Font</key>
          <data>${fontData}</data>
          <key>FontAntialias</key>
          <true/>
          <key>FontWidthSpacing</key>
          <real>1.004032258064516</real>
          <key>name</key>
          <string>0xProto</string>
          <key>ProfileCurrentVersion</key>
          <real>2.07</real>
          <key>type</key>
          <string>Window Settings</string>
        </dict>
      </dict>
    </dict>
    </plist>
  '';
}
