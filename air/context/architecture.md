# System Architecture

## Core Philosophy

This project follows a simple, focused approach to declarative repository management:

- **Declarative configuration eliminates manual operations**: All repositories defined in Nix configuration, executed automatically
- **Integration with Nix ecosystem for reproducibility**: Leverages Nix's deterministic evaluation and Home Manager's activation system
- **Type-safe configuration via Nix module system**: Validation at evaluation time prevents misconfigurations
- **Idempotent operations**: Safe to run repeatedly without side effects or redundant clones

## Design Principles

### 1. Declarative Configuration

- **Single source of truth** in Nix files (home.nix or flake configurations)
- **No hidden state or manual steps**: Everything defined in configuration
- **Reproducible across machines**: Same config produces same result everywhere

### 2. Ecosystem Integration

- **Leverages Home Manager's activation system**: Runs during `home-manager switch`
- **Uses nixpkgs library functions**: Built on solid, well-tested foundation
- **Compatible with Nix Flakes workflow**: Modern Nix development practices

### 3. Safety and Idempotency

- **Never overwrites existing repositories**: Checks before cloning
- **Checks before cloning**: Existence check prevents redundant operations
- **Optional update mode is explicit**: User must opt-in to auto-updates
- **Per-user operation with own credentials**: SSH keys, GPG agent specific to each user

### 4. Simplicity

- **Modular file structure**: Separate files for concerns (default.nix, git-clone.nix, jj-clone.nix, helpers.nix)
- **No complex state management**: Stateless activation scripts
- **Straightforward bash activation scripts**: Easy to understand and debug
- **Clear error messages**: When things fail, users know why

## System Architecture

```
Nix Configuration (home.nix)
          ↓
home.gitClone.<path> = { ... }
home.jjClone.<path> = { ... }
          ↓
Home Manager Module (nix/default.nix)
          ↓
Script Generators (nix/git-clone.nix, nix/jj-clone.nix)
          ↓
Activation Scripts Generated
          ↓
home-manager switch
          ↓
Scripts Execute (check → clone/update)
          ↓
Repositories in ~/path/
```

## Core Components

### 1. Module Definition System

**Location:** nix/default.nix

**Responsibilities:**
- Declare configuration options with types
- Validate user inputs at evaluation time
- Provide smart defaults for common cases
- Wire up activation script generators

**Key Options:**

```nix
home.gitClone.<path> = {
  url = string;              # Required
  rev = string | null;       # Default: null (auto-detect)
  useWorktree = bool;        # Default: false
  bypassGitConfig = bool?;   # Default: null (auto for HTTPS)
  update = bool;             # Default: false
}

home.jjClone.<path> = {
  url = string;              # Required
  rev = string | null;       # Default: null (auto-detect)
  colocate = bool;           # Default: true
  useWorkspace = bool;       # Default: false
  update = bool;             # Default: false
}
```

**Type Safety:**
- Uses `lib.types.attrsOf` for repository set
- `lib.types.submodule` for individual repo configuration
- `lib.types.str` for strings, `lib.types.bool` for booleans
- `lib.types.nullOr` for optional values
- Prevents invalid configurations at evaluation time
- Clear error messages with option paths when validation fails

**Implementation Pattern:**

```nix
options.home.gitClone = lib.mkOption {
  type = lib.types.attrsOf (lib.types.submodule {
    options = {
      url = lib.mkOption {
        type = lib.types.str;
        description = "Git repository URL";
      };
      # ... more options
    };
  });
  default = {};
  description = "Git repositories to clone";
};
```

### 2. Activation Script Generators

**Location:** nix/git-clone.nix, nix/jj-clone.nix

**Responsibilities:**
- Generate bash scripts for each repository
- Set up environment (PATH, SSH_AUTH_SOCK)
- Implement clone/update logic with idempotency
- Handle VCS-specific operations

**Script Structure:**

1. **Environment setup**:
   ```bash
   export PATH="${pkgs.openssh}/bin:${pkgs.git}/bin:$PATH"
   SSH_SOCKET="$HOME/.gnupg/S.gpg-agent.ssh"
   if [ -S "$SSH_SOCKET" ]; then
     export SSH_AUTH_SOCK="$SSH_SOCKET"
   fi
   ```

2. **Directory creation**:
   ```bash
   $DRY_RUN_CMD mkdir -p "$(dirname "${repoPath}")"
   ```

3. **VCS-specific operations**:
   ```bash
   # Git
   git clone --branch "${cfg.rev}" "${cfg.url}" "${repoPath}"

   # Jujutsu
   jj git clone --colocate --branch "${cfg.rev}" "${cfg.url}" "${repoPath}"
   ```

4. **Conditional logic**:
   ```bash
   if [ ! -d "${repoPath}/.git" ]; then
     # Clone
   else
     if [ "${cfg.update}" = "true" ]; then
       # Update
     fi
   fi
   ```

**Environment Variables:**
- `PATH`: Includes openssh, git, coreutils, and jujutsu (for jjClone)
- `SSH_AUTH_SOCK`: Points to GPG agent socket when available (~/.gnupg/S.gpg-agent.ssh)
- `GIT_CONFIG_GLOBAL`: Set to /dev/null for HTTPS bypass
- `GIT_CONFIG_SYSTEM`: Set to /dev/null for HTTPS bypass
- `DRY_RUN_CMD`: Set by Home Manager for dry-run mode

### 3. Shared Helpers

**Location:** nix/helpers.nix

**Responsibilities:**
- GPG agent SSH socket setup (shared between git and jj)
- Default branch auto-detection via `git ls-remote --symref`

### 4. Git Config Bypass System

**Purpose:** Prevent HTTPS URLs from being rewritten to SSH by git config

Many users configure git to automatically rewrite HTTPS URLs to SSH:
```gitconfig
[url "git@github.com:"]
  insteadOf = https://github.com/
```

This breaks HTTPS authentication. The bypass system solves this.

**Implementation:**

```nix
shouldBypassConfig =
  (cfg.bypassGitConfig == true) ||
  (cfg.bypassGitConfig == null && lib.hasPrefix "https://" cfg.url);
```

**Mechanism:**
- Auto-detects HTTPS URLs with `lib.hasPrefix`
- Sets `GIT_CONFIG_GLOBAL=/dev/null` and `GIT_CONFIG_SYSTEM=/dev/null`
- Git ignores user's ~/.gitconfig and /etc/gitconfig
- HTTPS URLs stay as HTTPS

**Override Capability:**
- `bypassGitConfig = true`: Always bypass (even for SSH URLs)
- `bypassGitConfig = false`: Never bypass (use git config even for HTTPS)
- `bypassGitConfig = null` (default): Auto-detect based on URL scheme

**Use Case Example:**

```nix
# User's ~/.gitconfig has HTTPS → SSH rewrite
# This repo should use HTTPS (e.g., CI token)
home.gitClone."work/private" = {
  url = "https://github.com/company/repo.git";
  # bypassGitConfig defaults to null, detects HTTPS, bypasses config ✓
};

# This repo should use SSH
home.gitClone."personal/public" = {
  url = "git@github.com:user/repo.git";
  # bypassGitConfig defaults to null, detects SSH, uses config ✓
};
```

### 5. VCS-Specific Modules

The module uses separate files for each VCS:

**Git Operations (nix/git-clone.nix):**
- **Clone**: `git clone --branch <rev> <url> <path>`
- **Update**: `git -C <path> pull`
- **Existence check**: `[ -d <path>/.git ]`

**Jujutsu Operations (nix/jj-clone.nix):**
- **Clone**: `jj git clone [--colocate] --branch <rev> <url> <path>`
- **Update**: `jj -R <path> git fetch`
- **Existence check**: `[ -d <path>/.jj ]`

**Co-location:**
- Jujutsu uses `--colocate` flag by default (configurable via `colocate` option)
- When colocated, creates both .jj and .git directories
- Repository works with both jj and git commands
- Enables gradual migration from Git to Jujutsu

### 6. Worktree/Workspace Support

**Standard Mode (useWorktree = false):**
- Repository cloned directly to configured path
- Example: `home.gitClone."Coding/my-repo"` → `~/Coding/my-repo/`
- `.git` directory at `~/Coding/my-repo/.git`

**Worktree Mode (useWorktree = true):**
- Rev appended to path
- Example: `home.gitClone."Coding/my-repo"` with `rev = "main"` → `~/Coding/my-repo/main/`
- `.git` directory at `~/Coding/my-repo/main/.git`

**Benefit:** Easy sibling worktree creation

```bash
cd ~/Coding/my-repo/main
git worktree add ../develop    # Creates ~/Coding/my-repo/develop/
git worktree add ../feature-x  # Creates ~/Coding/my-repo/feature-x/
```

**Implementation (git-clone.nix):**

```nix
finalPath = if repo.useWorktree then "${path}/${repo.rev}" else path;
repoPath = "${config.home.homeDirectory}/${finalPath}";
```

**Jujutsu Workspace Mode (jj-clone.nix):**
- Uses `useWorkspace` instead of `useWorktree` (jj terminology)
- Same path behavior: appends rev to path when enabled

## Technology Stack

### Language and Runtime

- **Language**: Nix (pure functional configuration language)
- **Edition**: Compatible with Nix 2.4+ (Flakes support)
- **Evaluation**: Lazy evaluation with strong typing

### Key Dependencies

- **nixpkgs**: Standard library and package set (provides lib functions)
- **home-manager**: User environment framework (provides activation system)
- **git**: Required for all operations (even Jujutsu uses git remotes)
- **jujutsu**: Added to PATH for home.jjClone repositories
- **openssh**: For SSH authentication
- **gnupg**: Optional, provides GPG agent SSH socket

### Module System

- Uses `nixpkgs.lib.types` for option type declarations
- Leverages `lib` functions: `hasPrefix`, `optionalString`, `mkIf`, `mapAttrs'`
- Integrates with Home Manager's `home.activation` system
- Uses `lib.hm.dag.entryAfter` for activation ordering

## Performance Considerations

### Nix Evaluation

- **Pure functional evaluation**: Deterministic, no side effects during evaluation
- **Lazy evaluation**: Only evaluates options that are actually used
- **Type checking at evaluation time**: Fast failure before activation

### Repository Operations

- **Parallel activation possible**: Home Manager can run activation scripts in parallel
- **Idempotent checks are fast**: Just directory existence check (`[ -d path ]`)
- **Shallow clone not implemented**: Full history cloned (future optimization)

### Activation Time

- **Existing repositories**: Minimal overhead (just existence check, ~1ms per repo)
- **Initial clones**: Network-bound (depends on repository size and network speed)
- **Update mode**: Adds git pull/fetch overhead on every activation

## Error Handling Strategy

### Nix Module Errors

- **Type errors** caught at evaluation time:
  ```
  error: A definition for option `home.gitClone."foo".url' is not of type `string'
  ```
- **Clear error messages** with option paths
- **Prevents activation** if configuration is invalid

### Activation Script Errors

- **Bash errexit mode not used**: Allows partial success
- **Errors printed to stderr**: User sees what failed
- **Non-zero exit continues to next repository**: One failure doesn't block others
- **User sees which repositories failed**: Clear output per repo

### VCS Operation Errors

- **Git/jj errors propagate to user**: Stderr not suppressed
- **Authentication failures visible**: SSH key issues, permission errors shown
- **Network errors clear**: Timeout, DNS failures, etc. all visible

### Recovery Strategies

1. **Manual intervention**: User can fix issue and re-run `home-manager switch`
2. **Re-run to retry**: Idempotent design means safe to retry
3. **Remove and re-clone**: User can delete directory and let module re-clone
4. **Update mode recovery**: Can recover from partial failures on next activation

## Future Architecture Considerations

### Scalability

- **Current limit**: Handles dozens of repositories efficiently
- **Potential bottleneck**: Hundreds of repositories may slow activation
- **Future optimization**: Parallel clone operations with process pooling
- **Conditional activation**: Based on hostname, user, or other criteria

### Extensibility

- **Additional VCS support**: Mercurial, Fossil, Pijul, Darcs
- **Repository groups**: Bulk operations on related repos
- **Pre/post clone hooks**: Custom commands before/after operations
- **Custom clone commands**: Per-repository override of clone behavior

### Enhanced Features

- **Shallow clones**: `--depth 1` for faster clones of large repos
- **LFS support configuration**: Git LFS handling options
- **Submodule control**: Whether to clone submodules, recursive depth
- **Branch tracking**: Automatic checkout of matching remote branch
- **Repository health checks**: Verify repo state, detect corruption
- **Differential updates**: Only fetch changed refs
- **Workspace management**: Integration with project-specific tooling

## Deployment Architecture

### Home Manager Integration

```
User's Nix Configuration
    ├── flake.nix (inputs.home-git-clone)
    └── home.nix
        ├── imports = [ home-git-clone.homeManagerModules.default ]
        ├── home.gitClone = { ... }
        └── home.jjClone = { ... }
                ↓
        Home Manager Evaluation
                ↓
        nix/default.nix → nix/git-clone.nix, nix/jj-clone.nix
                ↓
        Activation Script Generation
                ↓
        home-manager switch
                ↓
        Bash Scripts Execute
                ↓
        Repositories Cloned/Updated
```

### Multi-User Considerations

- Each user has separate home-manager configuration
- Activation runs with user's credentials
- No shared state between users
- Safe for multi-user systems (NixOS or traditional Linux)

```
/home/
├── alice/
│   ├── .config/home-manager/home.nix  (alice's config)
│   └── Coding/                         (alice's repos)
└── bob/
    ├── .config/home-manager/home.nix  (bob's config)
    └── Projects/                       (bob's repos)
```
