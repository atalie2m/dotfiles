{ delib, ... }:

delib.module {
  name = "smartBackup";
  home.always.imports = [ ../../modules/home/services/smart-backup.nix ];
}
