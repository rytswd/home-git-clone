{
  lib,
  pkgs,
  helpers,
}:

# Renders the configured repository set as JSON so it lands in the
# generation and stays inspectable at ~/.config/home-git-clone/manifest.json.
# The doctor app (`nix run github:rytswd/home-git-clone#check`) consumes this
# on machines that have no access to the Nix configuration that produced it.
{ gitRepos, jjRepos }:
let
  entryFor = kind: path: repo:
    let
      facts = helpers.repoFacts kind path repo;
    in
    {
      name = path;
      inherit kind;
      # rev is null when the default branch is auto-detected at clone time;
      # update/updateFailMode let manifest consumers model which repositories
      # an activation would actually touch.
      inherit (repo) url rev update updateFailMode;
      path = facts.repoPath;
      # Effective value (explicit setting or HTTPS auto-detection), so the
      # doctor app reproduces the clone environment without re-implementing
      # the detection.
      bypassGitConfig = facts.shouldBypass;
    };
in
# Nix iterates attributes in name order, keeping the manifest deterministic.
pkgs.writeText "home-git-clone-manifest.json" (
  builtins.toJSON {
    version = 1;
    repos =
      (lib.mapAttrsToList (entryFor "git") gitRepos)
      ++ (lib.mapAttrsToList (entryFor "jj") jjRepos);
  }
)
