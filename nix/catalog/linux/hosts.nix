let
  supportedProfiles = [
    "minimal"
    "workbench"
  ];
in
{
  inherit supportedProfiles;

  hosts = {
    linux_workbench = {
      name = "linux_workbench";
      defaultProfile = "workbench";
      buildTarget = "linux_workbench";
      inherit supportedProfiles;
      machineKey = "linux_workbench";
      system = "x86_64-linux";
      extraMyconfig = { };
    };
  };
}
