{
  lib,
  config,
  pkgs,
  helpers,
}:

path: repo:
let
  name = builtins.replaceStrings [ "/" ] [ "-" ] path;

  facts = helpers.repoFacts "git" path repo;
  repoPath = facts.repoPath;

  withBypass =
    cmd:
    if facts.shouldBypass then
      ''${pkgs.coreutils}/bin/env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null ${cmd}''
    else
      cmd;

  cloneArgs =
    if repo.rev != null then
      ''--branch "${repo.rev}" "${repo.url}" "$REPO_PATH"''
    else
      ''--branch "$DEFAULT_BRANCH" "${repo.url}" "$REPO_PATH"'';
in
lib.nameValuePair "gitClone-${name}" (
  lib.hm.dag.entryAfter [ "writeBoundary" "reloadSystemd" ] ''
    export PATH="${pkgs.openssh}/bin:${pkgs.git}/bin:${pkgs.coreutils}/bin:$PATH"

    ${helpers.setupGpgAgent}

    REPO_PATH="${repoPath}"

    if [ ! -d "$REPO_PATH/.git" ]; then
      ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$REPO_PATH")"

      ${lib.optionalString (repo.rev == null) (helpers.autoDetectBranch repo.url withBypass)}

      echo "Cloning ${repo.url} (${
        if repo.rev != null then repo.rev else "$DEFAULT_BRANCH"
      }) to $REPO_PATH..."
      $DRY_RUN_CMD ${withBypass ''${pkgs.git}/bin/git clone ${cloneArgs}''}
    ${lib.optionalString repo.update ''
      else
        echo "Updating repository at $REPO_PATH..."
        ${helpers.withRetry
          { failMode = repo.updateFailMode; }
          ''$DRY_RUN_CMD ${withBypass ''${pkgs.git}/bin/git -C "$REPO_PATH" pull''}''
        }
    ''}
    fi
  ''
)
