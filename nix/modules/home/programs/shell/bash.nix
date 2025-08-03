{ pkgs, lib, ... }:

let
  common = import ./common.nix { inherit pkgs; };
in
{
  programs.bash = {
    enable = true;

    historySize = 10000;
    historyFileSize = 10000;
    historyControl = [ "ignoredups" "ignorespace" ];

    inherit (common) shellAliases;

    initExtra = ''
      # Load local ~/.bashrc
      # This might break the benefits of Nix, but I rather fancy it.
      if [[ -f ~/.bashrc ]]; then
        source ~/.bashrc
      fi

      # Ensure starship is initialized in nix develop environments
      if command -v starship >/dev/null 2>&1; then
        eval "$(starship init bash)"
      fi

      ${common.commonInitContent}
    '';

    enableCompletion = true;
  };

  # Ensure starship is initialized for bash
  programs.starship.enableBashIntegration = true;

  home.sessionVariables = {
    SHELL = lib.mkForce "${pkgs.bash}/bin/bash";
  };
}