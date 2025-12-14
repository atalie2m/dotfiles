{ delib, ... }:

# mn rice: mirrors `full`, including the `minimum` base
delib.rice {
  name = "mn";
  # NOTE: Inherits are not assumed to be transitive; include `minimum` explicitly.
  inherits = [ "minimum" "full" ];

  myconfig = {};
}
