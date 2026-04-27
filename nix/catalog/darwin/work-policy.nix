{
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
    "terminalVisual.*"

    "downloadArchive.ffmpeg"
    "downloadArchive.aria2"
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

  forcedOff = [
    "editor.emacs.sync.enable"
    "editor.emacs.bootstrap.enable"
    "editor.neovim.sync.enable"
    "editor.vscode.sync.enable"
  ];
}
