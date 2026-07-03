{
  lib,
  pkgs,
}:

# Optional Linux-only execution mode: the exact per-repository scripts the
# inline mode would run during activation are concatenated into a oneshot
# user service instead. Activation only triggers the service, so transient
# network flakes retry under systemd instead of failing the generation.
{ cloneEntries }:
let
  # The DAG entries carry the script bodies in .data; reusing them verbatim
  # keeps the two execution modes behaviourally identical.
  cloneScript = pkgs.writeShellScript "home-git-clone-clones" ''
    # Mirror Home Manager's activation shell semantics so the snippets behave
    # identically in both execution modes.
    set -eu
    # systemd has no dry-run concept; the generated snippets expand this.
    DRY_RUN_CMD=""
    ${lib.concatMapStrings (entry: entry.value.data + "\n") cloneEntries}
  '';
in
{
  service = {
    Unit = {
      Description = "home-git-clone repository provisioning";
      # Cap retries: 5 attempts in 10 minutes absorbs transient network
      # flakes, then systemd gives up until the next trigger (activation or
      # login) instead of burning cycles on a genuinely broken remote.
      StartLimitIntervalSec = 600;
      StartLimitBurst = 5;
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${cloneScript}";
      # Valid for oneshot units since systemd 244; oneshot units are never
      # restarted on clean exit. set -eu stops the script at the first
      # failure, and retries converge: completed repositories are skipped by
      # the existence check, while interrupted clones never reach their
      # final path (temp-dir + rename) so they are simply redone.
      Restart = "on-failure";
      RestartSec = 30;
    };
    # Fallback trigger: when the systemd user instance is unreachable during
    # activation (e.g. nixos-rebuild before the user session exists), the
    # next login still provisions the repositories. Idempotency keeps the
    # extra runs cheap.
    Install.WantedBy = [ "default.target" ];
  };

  triggerEntry = lib.nameValuePair "cloneSystemdService" (
    lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
      # Unlike the preflight, the trigger is gated on dry-run: starting the
      # service would perform real clones.
      #
      # reset-failed first: after the start rate limiter trips, the unit
      # refuses further starts (including this one) for the rest of the
      # StartLimitIntervalSec window even once the underlying problem is
      # fixed. Errors are ignored: the unit may simply never have failed,
      # and an unreachable bus is diagnosed by the start below.
      $DRY_RUN_CMD ${pkgs.systemd}/bin/systemctl --user reset-failed home-git-clone.service 2>/dev/null || true
      # start, not restart: restart SIGTERMs an in-flight provisioning run
      # (e.g. the login-triggered instance mid-clone), while start joins it;
      # a completed oneshot without RemainAfterExit is inactive again, so
      # start still re-runs the service on later activations.
      if ! $DRY_RUN_CMD ${pkgs.systemd}/bin/systemctl --user start --no-block home-git-clone.service; then
        if ${pkgs.systemd}/bin/systemctl --user is-enabled home-git-clone.service >/dev/null 2>&1; then
          echo "Warning: could not start home-git-clone.service; inspect it with 'systemctl --user status home-git-clone'." >&2
        else
          echo "Warning: systemd user instance unreachable; home-git-clone.service will run when the user manager next starts." >&2
        fi
      fi
    ''
  );
}
