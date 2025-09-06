{ delib, lib, pkgs, ... }: delib.module {
  name = "vscode-disabled";
  # disabled: moved to nix/denix/modules_disabled/programs/vscode.nix
  options.vscode = with delib.options; { enable = boolOption false; };
  home.ifEnabled = _: {};
}
