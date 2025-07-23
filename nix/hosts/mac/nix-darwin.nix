{pkgs, ...}: {
  system = {
    primaryUser = "{{USER_NAME}}";
    defaults = {
      NSGlobalDomain.AppleShowAllExtensions = true;
      finder = {
        AppleShowAllFiles = true;
        AppleShowAllExtensions = true;
      };
      dock = {
        autohide = true;
      };
    };
  };
}
