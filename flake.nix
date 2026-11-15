{
  description = "Nix packages repository";

  inputs = {
    # Netscape cookie file for .stencil.so (store copy), needed to download
    # tern. Regenerate when the session expires:
    #   nix store add --mode flat --name stencil-cookie .stencil-cookie
    # then paste the printed store path here and rerun `nix flake lock`.
    stencilCookie = {
      url = "path:/nix/store/75kn2mrhwpmdvzs46irk2lkrgbbd7zji-stencil-cookie";
      flake = false;
    };
    flake-compat.url = "https://git.lix.systems/lix-project/flake-compat/archive/main.tar.gz";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    nix-github-actions = {
      url = "github:nix-community/nix-github-actions";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.zst";
    nvfetcher = {
      url = "github:berberman/nvfetcher/0.8.1";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-compat.follows = "";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      imports = [
        inputs.treefmt-nix.flakeModule
        ./pkgs/omp-gui.nix
        ./pkgs/tern.nix
      ];

      perSystem = {
        treefmt = {
          projectRootFile = "flake.nix";
          programs.nixfmt.enable = true;
          flakeCheck = true;
          flakeFormatter = true;
        };
      };
    };
}
