# Implementation Guide

## Development Environment

### Nix Configuration

- **Language**: Nix (functional configuration language)
- **Nix Version**: 2.4+ (Flakes support required)
- **Project Structure**: Modular structure in `nix/` directory with flake interface
- **Linting**: Use nixpkgs-fmt or alejandra for formatting

### Build Environment

**Required Settings:**
```nix
# Enable Flakes in your Nix configuration
nix.settings.experimental-features = [ "nix-command" "flakes" ];
```

**Required Tools:**
- Nix with Flakes enabled
- Home Manager installed and configured
- Git installed for testing
- Jujutsu (optional) for jj functionality testing

### Development Setup

```bash
# Clone the repository
git clone <repo-url> ~/home-git-clone
cd ~/home-git-clone

# Test the flake
nix flake check

# Test integration with Home Manager
# Add to your home.nix:
# imports = [ /path/to/home-git-clone/nix ];
# home.gitClone = { "test/repo" = { url = "https://..."; }; };
# home.jjClone = { "test/jj-repo" = { url = "https://..."; }; };

# Activate to test
home-manager switch
```

### Dependency Management

- All runtime dependencies declared in module (openssh, git)
- No external Nix dependencies beyond nixpkgs and home-manager
- Jujutsu added to PATH only when home.jjClone is used
- Dependencies automatically available during activation

## Coding Standards

### Nix Style

#### Formatting and Structure

- Use 2-space indentation (Nix convention)
- Use `lib.mkOption` for all options (never raw attrsets)
- Provide clear `description` for every option (shows in docs and error messages)
- Use `lib.types` for type safety (prevents runtime errors)

#### Module Organization

Organize module code in this order:

1. **Options first** - lib.mkOption declarations
2. **Config next** - lib.mkIf conditionals and config values
3. **Activation scripts last** - home.activation entries

Example structure:
```nix
{ config, lib, pkgs, ... }:

{
  options.home.gitClone = lib.mkOption {
    # Options here
  };

  config = lib.mkIf (config.home.gitClone != {}) {
    # Config here
    home.activation = {
      # Activation scripts here
    };
  };
}
```

#### Naming Conventions

- **camelCase** for option names: `useWorktree`, `bypassGitConfig`
- **lowercase-with-dashes** for paths and package names: `home-git-clone`
- **Descriptive variable names** in bash scripts: `REPO_PATH`, `SSH_SOCKET`
- **UPPERCASE** for environment variables: `GIT_CONFIG_GLOBAL`

#### Code Safety

- Always use `lib.types` for type checking (catches errors at evaluation time)
- Provide default values where reasonable (reduces boilerplate for users)
- Use `lib.mkDefault` for overridable defaults (allows users to override)
- Validate inputs at Nix level, not bash level (faster, clearer errors)

#### Error Handling

- Bash scripts should print clear error messages to stderr
- Use descriptive error messages with context (which repo, what failed, why)
- Don't exit early in bash scripts (allow other repos to process)
- Log actions for user visibility (`echo "Cloning repository..."`)

#### Documentation Standards

- Every option must have a `description` field
- README.org must reflect all features (user-facing documentation)
- Code comments for non-obvious logic (why, not what)
- Examples for common use cases in README

## Development Practices

### Testing Strategy

**Manual Testing:**

Since Nix modules don't have a traditional unit test framework, testing is done manually on actual Home Manager setups.

**Test Configuration Setup:**

Create a test configuration in a separate file:

```nix
# test-config.nix
{ config, pkgs, ... }:
{
  imports = [ ./nix ];

  home.gitClone = {
    "test/https-repo" = {
      url = "https://github.com/nixos/nixpkgs.git";
    };
    "test/ssh-repo" = {
      url = "git@github.com:user/repo.git";
      rev = "develop";
    };
    "test/worktree-repo" = {
      url = "https://github.com/user/repo.git";
      rev = "main";
      useWorktree = true;
    };
  };

  home.jjClone = {
    "test/jj-repo" = {
      url = "https://github.com/martinvonz/jj.git";
    };
    "test/jj-pure" = {
      url = "https://github.com/user/repo.git";
      colocate = false;
    };
  };
}
```

**Test Matrix:**

Test all combinations of these scenarios:

1. **URL types**:
   - SSH URLs (`git@github.com:user/repo.git`)
   - HTTPS URLs (`https://github.com/user/repo.git`)

2. **Worktree/Workspace mode**:
   - Standard mode (`useWorktree = false` / `useWorkspace = false`)
   - Worktree mode (`useWorktree = true` for Git)
   - Workspace mode (`useWorkspace = true` for Jujutsu)

3. **VCS options**:
   - Git via `home.gitClone`
   - Jujutsu via `home.jjClone`

4. **Jujutsu co-location**:
   - Colocated (`colocate = true`, default)
   - Pure jj (`colocate = false`)

5. **Update mode**:
   - No updates (`update = false`)
   - Auto-update (`update = true`)

6. **Multiple repositories**:
   - Single repository
   - Multiple repositories simultaneously

### Integration Testing

```bash
# Test Flakes integration
nix flake check

# Test module evaluation (doesn't actually activate)
nix-instantiate --eval -E '
  let
    pkgs = import <nixpkgs> {};
    home-manager = import <home-manager> {};
    module = import ./nix;
  in
    home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [ module ];
    }
'

# Test in actual environment
home-manager switch --flake .#test

# Test dry-run mode (shows what would be done)
home-manager switch --flake .#test --dry-run
```

### Test Cases

#### 1. First-time clone (no existing repository)

Expected: Repository cloned to configured path

```bash
rm -rf ~/test/repo
home-manager switch
ls ~/test/repo/.git  # Should exist
```

#### 2. Existing repository (should skip)

Expected: Repository left untouched

```bash
# Clone once
home-manager switch
# Modify repo
echo "test" >> ~/test/repo/testfile
# Run again
home-manager switch
# File should still exist
cat ~/test/repo/testfile  # Should show "test"
```

#### 3. Update mode with changes upstream

Expected: Latest changes pulled

```bash
# Set update = true in config
home-manager switch
# Check for upstream changes
cd ~/test/repo && git log
```

#### 4. Worktree mode directory structure

Expected: Rev appended to path

```bash
home-manager switch
ls ~/test/repo/main/.git  # Should exist with useWorktree=true
```

#### 5. HTTPS bypass with git config rewrites

Expected: HTTPS URL not rewritten to SSH

```bash
# Add URL rewrite to ~/.gitconfig
git config --global url."git@github.com:".insteadOf "https://github.com/"
# Clone with HTTPS
home-manager switch
# Should clone with HTTPS, not SSH
```

#### 6. SSH authentication with GPG agent

Expected: GPG agent socket used

```bash
# Ensure GPG agent SSH socket exists
ls ~/.gnupg/S.gpg-agent.ssh
# Clone with SSH URL
home-manager switch
# Should use GPG agent for authentication
```

#### 7. Jujutsu co-located repository

Expected: Both .jj and .git directories exist

```bash
home-manager switch
ls ~/test/jj-repo/.jj   # Should exist
ls ~/test/jj-repo/.git  # Should exist (co-located)
jj status               # Should work
git status              # Should also work
```

#### 8. Multiple repositories in different paths

Expected: All clone successfully

```bash
home-manager switch
ls ~/test/repo1/.git  # Exists
ls ~/test/repo2/.git  # Exists
ls ~/other/repo3/.git # Exists
```

### Version Control

- Use semantic versioning for releases: v0.1.0, v0.2.0, v1.0.0
- Tag releases with git: `git tag v0.1.0`
- Keep README.org updated with all features
- Document breaking changes clearly in commit messages and release notes

**Commit Message Format:**

```
<type>: <short summary>

<optional longer description>

Breaking changes:
- <what changed>
- <migration path>
```

Types: feat, fix, docs, refactor, test, chore

## Nix-Specific Patterns

### Option Declaration Pattern

Use this pattern for all options:

```nix
options.home.gitClone = lib.mkOption {
  type = lib.types.attrsOf (lib.types.submodule {
    options = {
      url = lib.mkOption {
        type = lib.types.str;
        description = "Git repository URL (HTTPS or SSH)";
      };
      rev = lib.mkOption {
        type = lib.types.str;
        default = "main";
        description = "Branch or revision to checkout";
      };
      useWorktree = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Append revision to path for worktree workflows";
      };
      # ... more options
    };
  });
  default = {};
  description = "Git repositories to clone and manage";
};
```

**Key points:**
- `lib.types.attrsOf` creates an attribute set of repositories
- `lib.types.submodule` defines the shape of each repository config
- `default = {}` makes the option optional (user can omit if not using)
- Descriptions show in `man home-configuration.nix` and error messages

### Activation Script Pattern

Use this pattern for activation scripts:

```nix
config = lib.mkIf (cfg != {}) {
  home.activation = lib.mapAttrs' (path: repoCfg:
    lib.nameValuePair "gitClone-${path}" (
      lib.hm.dag.entryAfter ["writeBoundary"] ''
        # Bash script here
        export PATH="${pkgs.git}/bin:${pkgs.openssh}/bin:$PATH"

        # Repository operations
        if [ ! -d "$REPO_PATH/.git" ]; then
          $DRY_RUN_CMD git clone ...
        fi
      ''
    )
  ) cfg;
};
```

**Key points:**
- `lib.mkIf (cfg != {})` only activates if user configured any repos
- `lib.mapAttrs'` transforms each repo config into an activation entry
- `lib.nameValuePair` creates the activation entry name and value
- `lib.hm.dag.entryAfter ["writeBoundary"]` runs after files are written
- `$DRY_RUN_CMD` respects Home Manager's dry-run mode

### Conditional Logic

Use these patterns for conditional code:

```nix
# Conditional string concatenation
lib.optionalString condition "text-when-true"

# Conditional attributes
lib.optionalAttrs condition { attr = value; }

# Conditional config blocks
lib.mkIf condition {
  # config here
}

# Multiple conditions
lib.mkMerge [
  (lib.mkIf condition1 { ... })
  (lib.mkIf condition2 { ... })
]
```

## Performance Guidelines

### Nix Evaluation

- **Avoid expensive computations in option defaults**: Defaults evaluated for all users
- **Use lib.mkDefault** instead of hardcoded defaults when user might override
- **Lazy evaluation** means unused options don't cost anything
- **Type checking is free**: Happens at evaluation time, no runtime cost

**Example:**

```nix
# Good: Simple default
rev = lib.mkOption {
  type = lib.types.str;
  default = "main";
};

# Bad: Expensive computation in default
rev = lib.mkOption {
  type = lib.types.str;
  default = builtins.readFile ./default-branch.txt;  # File I/O at evaluation time!
};
```

### Activation Performance

- **Existence checks are fast**: Just a directory test (~1ms)
- **Network operations dominate clone time**: Git clone/fetch bottleneck
- **No optimization needed** for dozens of repositories
- **Consider parallel clones** for future (not currently implemented)

**Current performance:**
- Existing repos: ~1ms per repo (just existence check)
- New clones: Depends on repo size and network (seconds to minutes)
- Updates: Depends on changes and network (seconds typically)

### Resource Usage

- **Disk space**: One copy per repository (no deduplication)
- **Memory**: Minimal Nix evaluation overhead (< 10MB typically)
- **Network**: Full history cloned (no shallow clones by default)

## Common Pitfalls

### 1. Git Config Interaction

**Problem**: User's ~/.gitconfig rewrites HTTPS to SSH

```gitconfig
[url "git@github.com:"]
  insteadOf = https://github.com/
```

This breaks HTTPS authentication (tokens, passwords).

**Solution**: Auto-detect and bypass config for HTTPS URLs

```nix
shouldBypassConfig =
  (cfg.bypassGitConfig == true) ||
  (cfg.bypassGitConfig == null && lib.hasPrefix "https://" cfg.url);
```

**Override**: Set `bypassGitConfig = false` if you need git config for HTTPS

### 2. SSH Authentication

**Problem**: SSH keys not available during activation

**Solution**: Check for GPG agent socket first

```bash
SSH_SOCKET="$HOME/.gnupg/S.gpg-agent.ssh"
if [ -S "$SSH_SOCKET" ]; then
  export SSH_AUTH_SOCK="$SSH_SOCKET"
fi
```

**Fallback**: User must have ssh-agent running or GPG agent configured

### 3. Path Handling

**Problem**: Spaces in paths break bash scripts

```bash
# Bad
cd $REPO_PATH  # Breaks if path has spaces

# Good
cd "$REPO_PATH"  # Always quote variables
```

**Prevention**: Nix's bash string escaping handles this automatically

### 4. VCS Not Installed

**Problem**: Jujutsu not in PATH when using home.jjClone

**Solution**: Module adds jj to PATH in activation script (nix/jj-clone.nix)

```nix
export PATH="${pkgs.jujutsu}/bin:${pkgs.git}/bin:${pkgs.openssh}/bin:${pkgs.coreutils}/bin:$PATH"
```

**User requirement**: Packages are automatically available via nixpkgs in the activation script

### 5. Update Mode Conflicts

**Problem**: User has local changes, git pull fails

```
error: Your local changes to the following files would be overwritten by merge:
  file.txt
Please commit your changes or stash them before you merge.
```

**Solution**: Don't exit script, continue to next repo

```bash
if $DRY_RUN_CMD git pull 2>&1; then
  echo "Updated successfully"
else
  echo "Warning: Update failed, continuing..." >&2
fi
```

**User action**: Manual conflict resolution required

## Debugging Tips

### Enable Verbose Output

```bash
# See what Home Manager is doing
home-manager switch --verbose

# See activation script output
home-manager switch --show-trace
```

### Check Generated Scripts

```bash
# View generated activation scripts
nix eval --impure --expr 'builtins.trace (builtins.readFile ~/.config/home-manager/home.nix) "done"'

# Or check Home Manager generation
ls ~/.local/state/home-manager/generations/
```

### Test Bash Scripts Manually

```bash
# Extract the bash script from module
# Run it manually to debug

export PATH="/nix/store/.../bin:$PATH"
export DRY_RUN_CMD=""
# Run clone command manually
```

### Common Error Messages

**"File exists" error:**
- Usually means repository already cloned
- Check existence check logic

**"Permission denied (publickey)":**
- SSH authentication failed
- Check SSH keys, GPG agent socket

**"Could not resolve host":**
- Network/DNS issue
- Check internet connection

**"Repository not found":**
- Wrong URL or no access
- Check URL, authentication

## Best Practices

1. **Always test in dry-run mode first**: `home-manager switch --dry-run`
2. **Use version control for config**: Commit home.nix changes
3. **Keep options simple**: Don't over-configure, use defaults
4. **Document custom setups**: Add comments to unusual configurations
5. **Test with multiple repos**: Ensure interactions work correctly
6. **Use HTTPS for public repos**: Avoids SSH key requirement
7. **Use SSH for private repos**: Better security, key-based auth
8. **Enable GPG agent SSH**: Better key management
9. **Avoid update mode for dev repos**: Manual control better for active development
10. **Use worktree mode for multi-branch work**: Cleaner workspace organization
