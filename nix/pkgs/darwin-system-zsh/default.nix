{ lib, runCommandLocal, zsh }:

runCommandLocal "darwin-system-zsh"
{
  meta = {
    description = "macOS system zsh with Nix-provided support files";
    mainProgram = "zsh";
    platforms = lib.platforms.darwin;
  };
} ''
  mkdir -p "$out/bin"
  ln -s /bin/zsh "$out/bin/zsh"
  ln -s ${zsh}/share "$out/share"
''
