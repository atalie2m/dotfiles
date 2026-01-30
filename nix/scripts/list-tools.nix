{ }:
let
  getTools = cfg:
    if cfg ? myconfig && cfg.myconfig ? tools then cfg.myconfig.tools
    else if cfg ? tools then cfg.tools
    else {};

  isToggle = prefix:
    builtins.match "^[^.]+\\.enable$" prefix != null
    || builtins.match "^[^.]+\\.[^.]+\\.enable$" prefix != null;

  flattenPairs = prefix: value:
    if builtins.isAttrs value then
      builtins.concatLists (builtins.map (name:
        flattenPairs (if prefix == "" then name else prefix + "." + name) value.${name}
      ) (builtins.attrNames value))
    else if builtins.isBool value && isToggle prefix then
      [ { path = prefix; value = value; } ]
    else
      [ ];

  merge = left: right:
    if builtins.isAttrs left && builtins.isAttrs right then
      builtins.foldl' (acc: key:
        acc // {
          ${key} =
            if acc ? ${key} then merge acc.${key} right.${key} else right.${key};
        }
      ) left (builtins.attrNames right)
    else
      right;

  toNested = acc: entry:
    let
      parts = builtins.filter builtins.isString (builtins.split "\\." entry.path);
      setAt = path: val: builtins.listToAttrs [
        {
          name = builtins.head path;
          value =
            if builtins.length path == 1 then val
            else setAt (builtins.tail path) val;
        }
      ];
    in
      merge acc (setAt parts entry.value);

  selectTools = cfg:
    builtins.foldl' toNested {} (flattenPairs "" (getTools cfg));

  flattenText = prefix: value:
    if builtins.isAttrs value then
      builtins.concatLists (builtins.map (name:
        flattenText (if prefix == "" then name else prefix + "." + name) value.${name}
      ) (builtins.attrNames value))
    else if builtins.isBool value then
      [ "${prefix} = ${if value then "true" else "false"}" ]
    else
      [ ];

  toText = cfg:
    builtins.concatStringsSep "\n" (flattenText "" (selectTools cfg));
in
{
  select = selectTools;
  text = toText;
}
