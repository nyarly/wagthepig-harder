{
  description = "wagthepig is a web app to help with the What Are We Going to Play Game";
  inputs = {
    #nixpkgs.url = "github:nixos/nixpkgs/24.05";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
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
        cargo-expand
        rustc
        rust-analyzer
        clippy

        nodejs_latest
        elmPackages.elm
        elmPackages.elm-test-rs
        elmPackages.elm-live
        lightningcss

        process-compose
        watchexec
        postgresql
        sqlx-cli
        biscuit-cli
        mailpit
        openssl
      ] ++ buildDeps;
    };
    devShells.default = devShells.devShell.${system};
  });
}
