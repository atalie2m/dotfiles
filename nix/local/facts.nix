{
  user = {
    username = "public";
    git = {
      fullName = "Public Example";
      email = "public@example.invalid";
    };
    stateVersion = {
      home = "25.11";
      darwin = 6;
    };
  };

  machines = {
    own_mac = {
      computerName = "Public Own Mac";
      localHostName = "public-own-mac";
      hostName = "public-own-mac";
      domain = "local";
    };
    work_mac = {
      computerName = "Public Work Mac";
      localHostName = "public-work-mac";
      hostName = "public-work-mac";
      domain = "local";
    };
    linux_workbench = {
      hostName = "public-linux-workbench";
      domain = "local";
    };
  };
}
