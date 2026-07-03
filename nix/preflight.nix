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
    in
    ''
      if [ ! -d "${facts.repoPath}/${facts.vcsDir}" ] || ${if probeWhenPresent then "true" else "false"}; then
        _hgc_probe "${path}" "${kind}" "${repo.url}" "${if facts.shouldBypass then "1" else "0"}"
      fi
    '';

  probes =
    (lib.mapAttrsToList (probeFor "git") gitRepos)
    ++ (lib.mapAttrsToList (probeFor "jj") jjRepos);
in
lib.hm.dag.entryBefore [ "writeBoundary" ] ''
  export PATH="${pkgs.openssh}/bin:${pkgs.git}/bin:${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin:$PATH"

  ${helpers.setupGpgAgent}

  _hgc_total=0
  _hgc_fail_count=0
  _hgc_failures=""

  # $1 = repo name, $2 = kind (git/jj), $3 = url, $4 = bypass git config (1/0)
  # GIT_TERMINAL_PROMPT=0 makes credential prompts fail fast instead of
  # sitting under the timeout; the SSH command is intentionally left alone so
  # the probe sees the same auth path the actual clone would use.
  _hgc_probe() {
    _hgc_total=$((_hgc_total + 1))
    _probe_rc=0
    if [ "$4" = "1" ]; then
      _probe_err=$(GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_TERMINAL_PROMPT=0 \
        timeout 10 git ls-remote --exit-code "$3" HEAD 2>&1 >/dev/null) || _probe_rc=$?
    else
      _probe_err=$(GIT_TERMINAL_PROMPT=0 \
        timeout 10 git ls-remote --exit-code "$3" HEAD 2>&1 >/dev/null) || _probe_rc=$?
    fi
    if [ "$_probe_rc" -eq 0 ]; then
      return 0
    fi
    if [ "$_probe_rc" -eq 124 ]; then
      _probe_cause="timed out after 10s"
    else
      # First non-empty stderr line: the root cause (ssh/curl error) comes
      # first, git's generic "make sure you have the correct access rights"
      # advice last.
      _probe_cause=$(printf '%s\n' "$_probe_err" | grep -v '^[[:space:]]*$' | head -n 1) || true
      if [ -z "$_probe_cause" ]; then
        _probe_cause="probe failed with exit code $_probe_rc"
      fi
    fi
    _hgc_fail_count=$((_hgc_fail_count + 1))
    printf -v _hgc_failures '%s  - %s (%s)\n      url:   %s\n      cause: %s\n' \
      "$_hgc_failures" "$1" "$2" "$3" "$_probe_cause"
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
