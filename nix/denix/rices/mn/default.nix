{ delib, ... }:

# mn rice: based on full; retains full-featured tooling
delib.rice {
  name = "mn";
  inherits = [ "full" ];

  myconfig = {};
}
