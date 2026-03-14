{ full ? false }:

let
  getTools = cfg:
    if cfg ? myconfig && cfg.myconfig ? tools then
      cfg.myconfig.tools
    else if cfg ? tools then
      cfg.tools
    else
      { };

  includePath = path:
    if builtins.match ".*\\.enable$" path == null then
      false
    else if full then
      true
    else
      builtins.match "^[^.]+\\.enable$" path != null;

  flattenPairs = prefix: value:
    if builtins.isAttrs value then
      builtins.concatLists
        (builtins.map
          (name:
            flattenPairs
              (if prefix == "" then name else prefix + "." + name)
              value.${name}
          )
          (builtins.attrNames value))
    else if builtins.isBool value && includePath prefix then
      [
        {
          name = prefix;
          value = value;
        }
      ]
    else
      [ ];

  selectTools = cfg:
    builtins.listToAttrs (flattenPairs "" (getTools cfg));

  targetNames = targets:
    builtins.sort builtins.lessThan (builtins.attrNames targets);

  matrixRows = targets:
    builtins.map
      (target: {
        inherit target;
        values = selectTools targets.${target}.config;
      })
      (targetNames targets);

  columnsFromRows = rows:
    let
      columnSet = builtins.foldl'
        (acc: row:
          builtins.foldl'
            (inner: key: inner // { ${key} = true; })
            acc
            (builtins.attrNames row.values))
        { }
        rows;
    in
    builtins.sort builtins.lessThan (builtins.attrNames columnSet);

  boolText = value:
    if value then "true" else "false";

  rowText = columns: row:
    builtins.concatStringsSep "\t"
      ([ row.target ] ++ (builtins.map (column: boolText (row.values.${column} or false)) columns));

  matrixFor = targets:
    let
      rows = matrixRows targets;
      columns = columnsFromRows rows;
    in
    {
      mode = if full then "full" else "group";
      inherit columns rows;
    };

  normalizeRows = matrix:
    builtins.map
      (row: {
        inherit (row) target;
        values = builtins.listToAttrs
          (builtins.map
            (column: {
              name = column;
              value = row.values.${column} or false;
            })
            matrix.columns);
      })
      matrix.rows;

  renderText = matrix:
    let
      header = builtins.concatStringsSep "\t" ([ "target" ] ++ matrix.columns);
      lines = [ header ] ++ (builtins.map (rowText matrix.columns) matrix.rows);
    in
    builtins.concatStringsSep "\n" lines;
in
{
  json = targets:
    let
      matrix = matrixFor targets;
    in
    {
      mode = matrix.mode;
      columns = matrix.columns;
      rows = normalizeRows matrix;
    };

  text = targets:
    let
      matrix = matrixFor targets;
    in
    renderText matrix;
}
