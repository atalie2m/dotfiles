rec {
  allowedGroups = [
    "core"
    "shell"
    "shellUx"
    "filesNavigation"
    "viewersPreview"
    "searchText"
    "gitPersonal"
    "nixOperator"
    "network"
    "xorg"
    "httpApiPersonal"
    "downloadArchive"
    "tuiWorkspace"
    "dataPersonal"
    "containerK8sPersonal"
    "securityPersonal"
    "passwordSecrets"
    "dev"
    "editor"
    "system"
    "terminal"
    "security"
  ];

  deniedTools = [
    "aiLlm.*"
    "aiCodingAgent.*"
    "modelHfPersonal.*"
    "backupRecovery.*"
    "observability.*"
    "securityPersonal.*"
    "terminalVisual.*"

    "editor.emacs"
    "editor.goneovim"

    "terminal.alacritty"
    "terminal.ghostty"
    "terminal.rio"
    "terminal.wezterm"

    "network.bandwhich"
    "network.mosh"
    "network.rustscan"
    "network.sniffnet"
    "network.termshark"

    "downloadArchive.ffmpeg"
    "downloadArchive.p7zip"
    "downloadArchive.pigz"
    "downloadArchive.zstd"

    "passwordSecrets.op"
    "passwordSecrets.agePluginYubikey"
    "passwordSecrets.sshToAge"

    "system.aerospace"
    "system.karabiner"
    "system.keyclu"
    "system.latestApp"
    "system.xcodesApp"
    "system.swiftgen"
    "system.sourcery"
    "system.periphery"
    "system.carthage"
  ];

  deniedHomebrew = {
    brews = [
      # Remote access / tunneling / scanner-like tools should not land on work
      # hosts through direct backend payload configuration.
      "gemini-cli"
      "git-xet"
      "mosh"
      "anomalyco/tap/opencode"
    ];

    casks = [
      # GUI apps that selected personal profiles may enable but work hosts
      # should not install unless there is a separate company-approved path.
      "alacritty"
      "claude-code@latest"
      "codex"
      "copilot-cli"
      "emacs-plus-app"
      "ghostty"
      "kitty"
      "rio"
      "wezterm"

      # Remote desktop / screen sharing / remote-control apps.
      "anydesk"
      "chrome-remote-desktop-host"
      "jump-desktop"
      "jump-desktop-connect"
      "microsoft-remote-desktop"
      "nomachine"
      "parsec"
      "remote-desktop-manager"
      "royal-tsx"
      "rustdesk"
      "screens"
      "screens-connect"
      "splashtop-business"
      "splashtop-streamer"
      "teamviewer"
      "vnc-viewer"
      "windows-app"

      # VPN / tunnel / traffic inspection / security-sensitive GUI apps.
      "burp-suite"
      "charles"
      "cloudflare-warp"
      "ghidra"
      "ngrok"
      "openvpn-connect"
      "proxyman"
      "tailscale"
      "wireshark"
      "zerotier-one"
    ];

    taps = [
      "anomalyco/tap"
    ];
  };

  deniedBrewNix = {
    casks = deniedHomebrew.casks;
  };

  forcedOff = [
    "editor.emacs.sync.enable"
    "editor.emacs.bootstrap.enable"
    "editor.neovim.sync.enable"
    "editor.vscode.sync.enable"
  ];
}
