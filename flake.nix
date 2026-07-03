{
  description = "Home Manager module for declaratively cloning and managing Git/Jujutsu repositories";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      homeManagerModules.default = import ./nix;
      homeManagerModules.git-clone = import ./nix;

      formatter = forAllSystems (pkgs: pkgs.nixpkgs-fmt);

      packages = forAllSystems (pkgs: {
        # Doctor app: probes every repository in a manifest written by the
        # module (~/.config/home-git-clone/manifest.json by default), so any
        # machine -- including a deploy target before switching -- can be
        # checked ad hoc with `nix run github:rytswd/home-git-clone#check`.
        check = pkgs.writeShellApplication {
          name = "home-git-clone-check";
          runtimeInputs = with pkgs; [
            coreutils
            git
            jq
            openssh
            ripgrep
          ];
          # probe.sh first: it defines the hgc_probe_url function shared
          # verbatim with the activation preflight.
          text = builtins.readFile ./nix/probe.sh + builtins.readFile ./nix/check.sh;
        };
      });

      apps = forAllSystems (pkgs: {
        check = {
          type = "app";
          program = "${self.packages.${pkgs.stdenv.hostPlatform.system}.check}/bin/home-git-clone-check";
          meta.description = "Probe every repository in a home-git-clone manifest";
        };
      });

      checks = forAllSystems (pkgs: {
        # Building the doctor app runs its shellcheck gate.
        check = self.packages.${pkgs.stdenv.hostPlatform.system}.check;
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          name = "home-git-clone";
          buildInputs = with pkgs; [
            nixpkgs-fmt
          ];
        };
      });
    };
}
