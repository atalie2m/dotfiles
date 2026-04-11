{ delib, lib, ... }:

# Claude Code is intentionally managed outside Homebrew/Nix so the upstream
# native installer can own updates. This toggle wires the expected PATH surface.

delib.module {
  name = "tools.aiCodingAgent.claudeCode";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  home.ifEnabled = { myconfig, ... }: {
    home.sessionPath = lib.mkAfter [
      "${myconfig.hostContext.user.homeDirectory}/.local/bin"
    ];
  };
}
