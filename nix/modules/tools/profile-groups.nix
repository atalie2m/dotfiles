{ delib, lib, ... }:

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
    delib.module {
      name = "tools.${group}";

      options = with delib; moduleOptions {
        enable = boolOption false;
      };
    };
in
{
  imports = lib.map mkGroupModule groups;
}
