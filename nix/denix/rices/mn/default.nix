{ delib, ... }:

# mn rice: based on full, excludes AI coding agents
delib.rice {
  name = "mn";
  inherits = [ "full" ];

  myconfig = {
    # Disable AI coding tools for this rice
    codingAgents = {
      claudeCode = false;
      codex = false;
    };

    # Also respect via productivity module knob (belt-and-suspenders)
    packages.productivity.includeAITools = false;
  };
}
