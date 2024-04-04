{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    zig-overlay = {
      url = "github:mitchellh/zig-overlay";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    zls-flake = {
      url = "github:zigtools/zls";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        zig-overlay.follows = "zig-overlay";
      };
    };
  };

  outputs = { self, nixpkgs, flake-utils, zig-overlay, zls-flake }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          (zig-overlay.overlays.default)
        ];
        };

        zls = zls-flake.packages.${system}.zls;

        lib = pkgs.lib;
        in {
        devShells.default = pkgs.mkShell {
        nativeBuildInputs = [
          pkgs.zigpkgs.master-2024-04-01
          zls
          pkgs.jq
          pkgs.fd

          # for benchmarks
          pkgs.gron
          pkgs.hyperfine
          pkgs.poop

          # for script to generate json
          pkgs.nodejs-slim_21
        ];
      };
    });
}
