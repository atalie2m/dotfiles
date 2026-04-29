final: prev: {
  roots = prev.roots or (final.callPackage ./roots { });
}
