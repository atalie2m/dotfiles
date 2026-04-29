{ dotmod, config, lib, ... }:

let
  groups = [
    "shellUx"
    "filesNavigation"
    "viewersPreview"
    "searchText"
    "gitPersonal"
    "nixOperator"
    "observability"
    "network"
    "xorg"
    "httpApiPersonal"
    "downloadArchive"
    "tuiWorkspace"
    "dataPersonal"
    "containerK8sPersonal"
    "securityPersonal"
    "passwordSecrets"
    "aiLlm"
    "modelHfPersonal"
    "backupRecovery"
    "terminalVisual"
  ];

  mkGroupModule = group:
    (dotmod.mkModule { inherit config; }) {
      path = "tools.${group}";

      options = with dotmod; moduleOptions {
        enable = boolOption false;
      };
    };
in
{
  imports = lib.map mkGroupModule groups;
}
