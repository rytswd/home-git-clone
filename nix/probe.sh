# Shared remote probe, used verbatim by both the activation preflight
# (nix/preflight.nix) and the doctor app (nix/check.sh) so the two cannot
# drift apart. Expects git, coreutils (env, timeout) and rg on PATH.
#
# hgc_probe_url URL BYPASS REF
#   URL    - git remote URL
#   BYPASS - "1" to bypass git config (GIT_CONFIG_GLOBAL/SYSTEM=/dev/null)
#   REF    - ref to ask for: "HEAD" or "refs/heads/<branch>"
# Sets: hgc_probe_rc (0 = reachable and ref present) and, on failure,
# hgc_probe_cause (single line, always non-empty).
#
# GIT_TERMINAL_PROMPT=0 makes credential prompts fail fast instead of
# sitting under the timeout; the SSH command is intentionally left alone so
# the probe sees the same auth path the actual clone would use.
hgc_probe_url() {
  hgc_probe_rc=0
  hgc_probe_cause=""
  _hgc_probe_env=(GIT_TERMINAL_PROMPT=0)
  if [ "$2" = "1" ]; then
    _hgc_probe_env+=(GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null)
  fi
  _hgc_probe_err=$(env "${_hgc_probe_env[@]}" \
    timeout 10 git ls-remote --exit-code "$1" "$3" 2>&1 >/dev/null) || hgc_probe_rc=$?
  if [ "$hgc_probe_rc" -eq 0 ]; then
    return 0
  fi
  if [ "$hgc_probe_rc" -eq 124 ]; then
    # ssh prompts on /dev/tty, so an interactive host-key or passphrase
    # prompt shows up here as a timeout -- hint at the manual fix.
    hgc_probe_cause="timed out after 10s (if this host prompts for host-key or passphrase confirmation, connect once manually first)"
  elif [ "$hgc_probe_rc" -eq 2 ]; then
    # ls-remote --exit-code: reachable remote, asked-for ref absent -- and
    # with empty stderr, so a cause must be synthesised.
    hgc_probe_cause="remote reachable but $3 not found (empty repository, or missing branch)"
  else
    # First non-blank stderr line: the root cause (ssh/curl error) comes
    # first, git's generic advice last.
    hgc_probe_cause=$(printf '%s\n' "$_hgc_probe_err" | rg --max-count 1 '\S') || true
    if [ -z "$hgc_probe_cause" ]; then
      hgc_probe_cause="probe failed with exit code $hgc_probe_rc"
    fi
  fi
  return 0
}
