{ pkgs, ... }:
let
  common = import ./common.nix { inherit pkgs; };
in
{
  # Configure bash for nix develop environments
  programs.bash = {
    enable = true;
    shellAliases = common.shellAliases // {
      # Bash-specific hidden command
      helloworld = "echo '👋 Hello from Bash! You are running in a Bash shell.'";
    };

    initExtra = ''
      # Only load bash customizations in nix develop environments
      if [[ -n "$IN_NIX_SHELL" ]]; then
        ${common.commonShellInit}
      fi
    '';
  };
}
