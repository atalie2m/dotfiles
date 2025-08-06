{ delib, ... }:

delib.module {
  name = "smartBackup";

  options.smartBackup = with delib.options; {
    enable = boolOption false;
  };

  home.always.imports = [ ../../../modules/home/services/smart-backup.nix ];
  home.ifEnabled.services.smartBackup.enable = true;
}
