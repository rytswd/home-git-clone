{
  lib,
  pkgs,
  helpers,
}:

# Single preflight activation entry that probes every configured remote
# before any activation mutation. Ordered before writeBoundary so a failed
# probe aborts the generation while the home is still untouched, and the
# probes are deliberately not gated on $DRY_RUN_CMD: they mutate nothing,
# and running them during `home-manager switch --dry-run` is the point --
# a dry run becomes a real preflight for the target machine.
{ gitRepos, jjRepos, mode }:
let
  probeFor = kind: path: repo:
    let
      facts = helpers.repoFacts kind path repo;
      # Present repositories only touch the network when update = true, and
      # an updateFailMode = "warn" failure would not abort activation anyway
      # -- skipping those keeps a fully-cloned machine activatable offline.
      probeWhenPresent = repo.update && repo.updateFailMode == "error";
      # Probe the pinned branch when one is configured: a typo'd or deleted
      # branch would otherwise pass an HEAD-only preflight and still fail
      # the clone after writeBoundary (clone always passes --branch).
      probeRef = if repo.rev != null then "refs/heads/${repo.rev}" else "HEAD";
    in
    ''
      if [ ! -d "${facts.repoPath}/${facts.vcsDir}" ] || ${if probeWhenPresent then "true" else "false"}; then
        _hgc_probe "${path}" "${kind}" "${repo.url}" "${if facts.shouldBypass then "1" else "0"}" "${probeRef}"
      fi
    '';

  probes =
    (lib.mapAttrsToList (probeFor "git") gitRepos)
    ++ (lib.mapAttrsToList (probeFor "jj") jjRepos);
in
lib.hm.dag.entryBefore [ "writeBoundary" ] ''
  export PATH="${pkgs.openssh}/bin:${pkgs.git}/bin:${pkgs.coreutils}/bin:${pkgs.ripgrep}/bin:$PATH"

  ${helpers.setupGpgAgent}

  ${builtins.readFile ./probe.sh}

  _hgc_total=0
  _hgc_fail_count=0
  _hgc_failures=""

  # $1 = repo name, $2 = kind (git/jj), $3 = url,
  # $4 = bypass git config (1/0), $5 = ref to probe
  _hgc_probe() {
    _hgc_total=$((_hgc_total + 1))
    hgc_probe_url "$3" "$4" "$5"
    if [ "$hgc_probe_rc" -eq 0 ]; then
      return 0
    fi
    _hgc_fail_count=$((_hgc_fail_count + 1))
    printf -v _hgc_failures '%s  - %s (%s)\n      url:   %s\n      cause: %s\n' \
      "$_hgc_failures" "$1" "$2" "$3" "$hgc_probe_cause"
    return 0
  }

  ${lib.concatStrings probes}

  if [ "$_hgc_fail_count" -gt 0 ]; then
    {
      echo "home-git-clone: remote preflight failed for $_hgc_fail_count of $_hgc_total probed repositories:"
      printf '%s' "$_hgc_failures"
    } >&2
    echo '${
      if mode == "fail" then
        "Aborting before any changes were made"
      else
        "Continuing anyway"
    } (home.cloneVerifyRemotes = "${mode}").' >&2
    ${lib.optionalString (mode == "fail") "exit 1"}
  elif [ "$_hgc_total" -gt 0 ]; then
    echo "home-git-clone: all $_hgc_total probed remotes reachable."
  fi
''
