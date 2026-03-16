{ lib, rustPlatform, sqlite, makeWrapper }:

rustPlatform.buildRustPackage {
  pname = "dotfiles-sync-vscode";
  version = "0.1.0";

  src = ../../..;

  nativeBuildInputs = [ makeWrapper ];

  cargoLock = {
    lockFile = ../../../Cargo.lock;
  };

  cargoBuildFlags = [ "-p" "dotfiles-sync-vscode" ];
  cargoTestFlags = [ "-p" "dotfiles-sync-vscode" ];

  nativeCheckInputs = [ sqlite ];

  doCheck = true;

  postFixup = ''
    wrapProgram "$out/bin/dotfiles-sync-vscode" \
      --set-default DOTFILES_ROOT "${../../..}"
  '';

  meta = with lib; {
    description = "VS Code native profile reconciliation engine for dotfiles sync";
    license = licenses.mit;
    platforms = platforms.unix;
  };
}
