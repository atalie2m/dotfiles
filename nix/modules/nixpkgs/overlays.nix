{ lib, ... }:

{
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
}
