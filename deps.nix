# generated by zon2nix (https://github.com/nix-community/zon2nix)

{ linkFarm, fetchzip }:

linkFarm "zig-packages" [
  {
    name = "1220db88c1ba7cfddb6915b61d9cf9ae58ced88d74ad4efbfff1d1dc95236086c251";
    path = fetchzip {
      url = "https://codeberg.org/dude_the_builder/zg/archive/master.tar.gz";
      hash = "sha256-1dtXCXCsnQLWzfXaPjMUV+9+ZAwCwr2uaLoGaJobr/E=";
    };
  }
]
