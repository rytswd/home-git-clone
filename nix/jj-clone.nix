{
  lib,
  config,
  pkgs,
  helpers,
}:

path: repo:
let
  name = builtins.replaceStrings [ "/" ] [ "-" ] path;

  # Jujutsu uses git under the hood, so the same bypass logic applies
  facts = helpers.repoFacts "jj" path repo;
  repoPath = facts.repoPath;

  withBypass =
    cmd:
    if facts.shouldBypass then
      ''${pkgs.coreutils}/bin/env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null ${cmd}''
    else
      cmd;

  colocateFlag = if repo.colocate then "--colocate" else "";
  cloneArgs =
    if repo.rev != null then
      ''--branch "${repo.rev}" "${repo.url}" "$REPO_PATH"''
    else
      ''--branch "$DEFAULT_BRANCH" "${repo.url}" "$REPO_PATH"'';
in
lib.nameValuePair "jjClone-${name}" (
  lib.hm.dag.entryAfter [ "writeBoundary" "reloadSystemd" ] ''
    export PATH="${pkgs.jujutsu}/bin:${pkgs.git}/bin:${pkgs.openssh}/bin:${pkgs.gnupg}/bin:${pkgs.coreutils}/bin:$PATH"

    ${helpers.setupGpgAgent}

    REPO_PATH="${repoPath}"

    if [ ! -d "$REPO_PATH/.jj" ]; then
      ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$REPO_PATH")"

      ${lib.optionalString (repo.rev == null) (helpers.autoDetectBranch repo.url withBypass)}

      echo "Cloning Jujutsu repository ${repo.url} (${
        if repo.rev != null then repo.rev else "$DEFAULT_BRANCH"
      }) to $REPO_PATH..."
      $DRY_RUN_CMD ${withBypass ''${pkgs.jujutsu}/bin/jj git clone ${colocateFlag} ${cloneArgs}''}
    ${lib.optionalString repo.update ''
      else
        echo "Updating Jujutsu repository at $REPO_PATH..."
        ${helpers.withRetry
          { failMode = repo.updateFailMode; }
          ''$DRY_RUN_CMD ${withBypass ''${pkgs.jujutsu}/bin/jj -R "$REPO_PATH" git fetch''}''
        }
    ''}
    fi
  ''
)
