{
  description = "shoppinglist is the WIP name for a web app to manage shopping lists";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/24.05";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = { self, nixpkgs, flake-utils }:
  flake-utils.lib.eachDefaultSystem (system:
  let
    pkgs = (import "${nixpkgs}" {
      inherit system;
    });

    runDeps = with pkgs; [
      openssl
    ];

    buildDeps = with pkgs; [
      pkg-config
    ] ++ runDeps;
  in rec {
    devShells.devShell.${system} = pkgs.mkShell {
      buildInputs = with pkgs; [
        cargo
        rustc
        rust-analyzer
        clippy

        nodejs_latest
        elmPackages.elm
        elmPackages.elm-test
      ] ++ buildDeps;
    };
    devShells.default = devShells.devShell.${system};
  });
}
