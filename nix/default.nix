{
  lib,
  config,
  pkgs,
  ...
}:

let
  gitCfg = config.home.gitClone;
  jjCfg = config.home.jjClone;

  helpers = import ./helpers.nix { inherit lib config pkgs; };
  gitCloneRepoScript = import ./git-clone.nix {
    inherit
      lib
      config
      pkgs
      helpers
      ;
  };
  jjCloneRepoScript = import ./jj-clone.nix {
    inherit
      lib
      config
      pkgs
      helpers
      ;
  };

  gitRepoModule = { lib, ... }: {
    options = {
      url = lib.mkOption {
        type = lib.types.str;
        description = "Git repository URL (HTTPS or SSH)";
        example = "git@github.com:user/repo.git";
      };

      rev = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Branch or revision to checkout.
          If null (default), automatically detects the remote's default branch.
          Set explicitly to override (e.g., "main", "master", "develop").
        '';
        example = "main";
      };

      useWorktree = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          If true, appends the rev/branch name to the path for worktree setup.
          Example: "Coding/repo" with rev="main" becomes "Coding/repo/main/"
          This allows easy use of `git worktree add` for sibling branches.
        '';
      };

      bypassGitConfig = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        description = ''
          If true, ignores git config during clone (useful to prevent HTTPS→SSH rewrites).
          If null (default), automatically bypasses config for HTTPS URLs only.
          If false, always uses git config.
        '';
      };

      update = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to pull updates on activation";
      };

      updateFailMode = lib.mkOption {
        type = lib.types.enum [ "error" "warn" ];
        default = "error";
        description = "Whether update failures cause an error or a warning";
      };
    };
  };

  jjRepoModule = { lib, ... }: {
    options = {
      url = lib.mkOption {
        type = lib.types.str;
        description = "Jujutsu/Git repository URL (HTTPS or SSH)";
        example = "git@github.com:user/repo.git";
      };

      rev = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Branch or bookmark to checkout.
          If null (default), automatically detects the remote's default branch.
          Set explicitly to override (e.g., "main", "master", "develop").
        '';
        example = "main";
      };

      colocate = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Create Git-colocated repository (.git + .jj directories).
          When true, both jj and git commands work on the repository.
          When false, creates pure jj repository (only .jj directory).
        '';
      };

      useWorkspace = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          If true, appends the rev/bookmark name to the path for workspace setup.
          Example: "Coding/repo" with rev="main" becomes "Coding/repo/main/"
          This allows easy use of jj workspace commands for sibling bookmarks.
        '';
      };

      bypassGitConfig = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        description = ''
          If true, ignores git config during clone (useful to prevent HTTPS→SSH rewrites).
          If null (default), automatically bypasses config for HTTPS URLs only.
          If false, always uses git config.
        '';
      };

      update = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to fetch updates on activation (runs jj git fetch)";
      };

      updateFailMode = lib.mkOption {
        type = lib.types.enum [ "error" "warn" ];
        default = "error";
        description = "Whether update failures cause an error or a warning";
      };
    };
  };
in
{
  options.home.gitClone = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule gitRepoModule);
    default = { };
    description = ''
      Git repositories to clone and manage.

      By default, repositories are cloned directly to the specified path.
      With `useWorktree = true`, the rev/branch name is appended to create
      a worktree-friendly structure.

      Example (default):
        home.gitClone."Coding/github.com/user/repo" = {
          url = "git@github.com:user/repo.git";
        };
      Creates: ~/Coding/github.com/user/repo/

      Example (auto-detect with explicit rev):
        home.gitClone."Coding/github.com/user/repo" = {
          url = "git@github.com:user/repo.git";
          rev = "main";
        };

      Example (worktree mode):
        home.gitClone."Coding/github.com/user/repo" = {
          url = "git@github.com:user/repo.git";
          rev = "main";
          useWorktree = true;
        };
      Creates: ~/Coding/github.com/user/repo/main/

      You can then add sibling worktrees:
        cd ~/Coding/github.com/user/repo/main
        git worktree add ../develop

      For Jujutsu repositories, use home.jjClone instead.
    '';
    example = lib.literalExpression ''
      {
        "Coding/dotfiles" = {
          url = "git@github.com:user/dotfiles.git";
          useWorktree = true;
          rev = "main";
        };
        "Coding/public-repo" = {
          url = "https://github.com/user/repo.git";
          update = true;
        };
      }
    '';
  };

  options.home.jjClone = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule jjRepoModule);
    default = { };
    description = ''
      Jujutsu repositories to clone and manage.

      This option provides a dedicated interface for Jujutsu (jj) repositories,
      with jj-specific options like colocate control and future jj features.

      By default, repositories are Git-colocated (--colocate flag), creating
      both .jj and .git directories so both jj and git commands work.

      Example (basic):
        home.jjClone."Coding/my-project" = {
          url = "git@github.com:user/project.git";
        };
      Creates: ~/Coding/my-project/ (with both .jj and .git)

      Example (workspace mode):
        home.jjClone."Coding/my-project" = {
          url = "git@github.com:user/project.git";
          rev = "main";
          useWorkspace = true;
        };
      Creates: ~/Coding/my-project/main/

      You can then add sibling workspaces:
        cd ~/Coding/my-project/main
        jj workspace add ../develop

      Example (pure jj, no git):
        home.jjClone."Coding/pure-jj" = {
          url = "git@github.com:user/repo.git";
          colocate = false;
        };
      Creates: ~/Coding/pure-jj/ (only .jj directory, git commands won't work)
    '';
    example = lib.literalExpression ''
      {
        "Coding/jj-project" = {
          url = "git@github.com:user/project.git";
          update = true;
          useWorkspace = true;
          rev = "main";
        };
        "Coding/pure-jj-repo" = {
          url = "https://github.com/user/repo.git";
          colocate = false;
        };
      }
    '';
  };

  config = lib.mkMerge [
    (lib.mkIf (gitCfg != { }) {
      home.activation = lib.listToAttrs (lib.mapAttrsToList gitCloneRepoScript gitCfg);
      assertions = lib.mapAttrsToList (name: repo: {
        assertion = repo.useWorktree -> repo.rev != null;
        message = "home.gitClone.\"${name}\": useWorktree requires rev to be explicitly set (cannot auto-detect in worktree mode)";
      }) gitCfg;
    })
    (lib.mkIf (jjCfg != { }) {
      home.activation = lib.listToAttrs (lib.mapAttrsToList jjCloneRepoScript jjCfg);
      assertions = lib.mapAttrsToList (name: repo: {
        assertion = repo.useWorkspace -> repo.rev != null;
        message = "home.jjClone.\"${name}\": useWorkspace requires rev to be explicitly set (cannot auto-detect in workspace mode)";
      }) jjCfg;
    })
  ];
}