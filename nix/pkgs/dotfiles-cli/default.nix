{ lib, rustPlatform, makeWrapper }:

rustPlatform.buildRustPackage {
  pname = "dotfiles-cli";
  version = "0.1.0";

  src = ../../..;

  nativeBuildInputs = [ makeWrapper ];

  cargoLock = {
    lockFile = ../../../Cargo.lock;
  };

  cargoBuildFlags = [ "-p" "dotfiles-cli" ];
  cargoTestFlags = [ "-p" "dotfiles-cli" ];

  doCheck = true;

  postFixup = ''
    wrapProgram "$out/bin/dotfiles" \
      --set-default DOTFILES_ROOT "${../../..}"
  '';

  meta = with lib; {
    description = "Unified dotfiles CLI";
    license = licenses.mit;
    platforms = platforms.unix;
  };
}
