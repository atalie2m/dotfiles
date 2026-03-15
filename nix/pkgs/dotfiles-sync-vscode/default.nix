{ lib, rustPlatform, sqlite }:

rustPlatform.buildRustPackage {
  pname = "dotfiles-sync-vscode";
  version = "0.1.0";

  src = ../../../scripts/sync-adapters/vscode-rs;

  cargoLock = {
    lockFile = ../../../scripts/sync-adapters/vscode-rs/Cargo.lock;
  };

  nativeCheckInputs = [ sqlite ];

  doCheck = true;

  meta = with lib; {
    description = "VS Code native profile reconciliation engine for dotfiles sync";
    license = licenses.mit;
    platforms = platforms.unix;
  };
}
