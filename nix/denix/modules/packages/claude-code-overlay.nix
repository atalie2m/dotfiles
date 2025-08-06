{ delib, ... }:

# Claude Code overlay for Denix
delib.module {
  name = "packages.claude-code-overlay";

  # This module doesn't have user-facing options, it just provides the overlay
  options.packages.claude-code-overlay = with delib.options; {
    enable = boolOption false;
  };

  # Apply the overlay at both home and darwin levels
  home.ifEnabled = _: {
    nixpkgs.overlays = [
      (final: prev: {
        claude-code = prev.claude-code.overrideAttrs (old: rec {
          version = "1.0.51";
          src = prev.fetchzip {
            url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${version}.tgz";
            hash = "sha256-sAILRsi8ZViMfcpqykfnFQzHTJHRwRSZz45otMqa4U0=";
          };
        });
      })
    ];
  };

  darwin.ifEnabled = _: {
    nixpkgs.overlays = [
      (final: prev: {
        claude-code = prev.claude-code.overrideAttrs (old: rec {
          version = "1.0.51";
          src = prev.fetchzip {
            url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${version}.tgz";
            hash = "sha256-sAILRsi8ZViMfcpqykfnFQzHTJHRwRSZz45otMqa4U0=";
          };
        });
      })
    ];
  };
}
