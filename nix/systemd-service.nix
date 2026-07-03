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
      # failure, and the idempotent existence checks make whole-set retries
      # converge instead of re-cloning.
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
      if ! $DRY_RUN_CMD ${pkgs.systemd}/bin/systemctl --user restart --no-block home-git-clone.service; then
        echo "Warning: systemd user instance unreachable; home-git-clone.service will run at next login instead." >&2
      fi
    ''
  );
}
