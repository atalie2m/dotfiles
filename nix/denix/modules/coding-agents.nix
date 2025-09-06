{ delib, lib, ... }:

# Coding agents toggle module
# Controls availability of AI coding tools (claude-code, codex) across rices/hosts.
delib.module {
  name = "coding-agents";

  options.codingAgents = with delib.options; {
    # Individual toggles (both true by default)
    claudeCode = boolOption true;
    codex = boolOption true;
  };

  # This module does not directly install packages; instead, other modules
  # (e.g., packages.productivity) should consult these flags to decide whether
  # to include AI tools.
}

