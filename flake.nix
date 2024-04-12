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
      nativeBuildInputs = [pkgs.zigpkgs.master-2024-04-07];
      picogron = pkgs.stdenv.mkDerivation {
        pname = "picogron";
        version = "v0.1.0";
        src = ./.;
        nativeBuildInputs = nativeBuildInputs;
        buildPhase = ''
          mkdir -p .cache
          ln -s ${pkgs.callPackage ./deps.nix { }} .cache/p
          zig build install --cache-dir $(pwd)/zig-cache --global-cache-dir $(pwd)/.cache -Dcpu=native -Doptimize=ReleaseFast --prefix $out
        '';
        meta = with pkgs.lib; {
          description = "Smaller and faster gron";
          homepage = "https://github.com/hwchen/picogron";
          license = licenses.mit;
          mainProgram = "picogron";
        };
      };

      zls = zls-flake.packages.${system}.zls;
      lib = pkgs.lib;
      in {
        # nix build
        packages = {
          inherit picogron;
          default = picogron;
        };

        # nix run
        apps = let
          picogron = {
            type = "app";
            program = "${self.packages.${system}.picogron}/bin/picogron";
          };
        in {
          inherit picogron;
          default = picogron;
        };

        devShells.default = pkgs.mkShell {
        nativeBuildInputs = nativeBuildInputs;
        buildInputs = [
          zls
          pkgs.zon2nix
          pkgs.jq
          pkgs.fd

          # for benchmarks
          pkgs.gron
          pkgs.fastgron
          pkgs.hyperfine
          pkgs.poop

          # for script to generate json
          pkgs.nodejs-slim_21
        ];
      };
    });
}
