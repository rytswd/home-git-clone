# Project Overview

## Description

A Home Manager module for declaratively cloning and managing Git/Jujutsu repositories in your home directory. This project eliminates manual repository cloning across environments by integrating with Nix's declarative configuration system, allowing users to specify repositories once and have them automatically managed during home-manager activation.

## Core Principles

- **Declarative configuration over imperative commands**: Repositories defined in Nix configuration, not manual git clone commands
- **Integration with Nix ecosystem and Home Manager**: Leverages existing Nix tools and workflows
- **Multi-VCS support**: Works with both Git and Jujutsu (jj) version control systems
- **Safe multi-user operation**: Each user's credentials and repositories managed independently
- **Idempotent activation**: Safe to run repeatedly, no redundant clones or overwrites

## Technology Stack

- **Language**: Nix (functional configuration language)
- **Framework**: Home Manager (Nix user environment management)
- **Version Control**: Git (primary), Jujutsu (optional)
- **Packaging**: Nix Flakes
- **License**: MIT

## Project Structure

```
home-git-clone/
├── flake.nix              # Flake outputs and module exposure
├── nix/                   # Nix module implementation
│   ├── default.nix        # Main Home Manager module (options + config)
│   ├── git-clone.nix      # Git clone activation script generator
│   ├── jj-clone.nix       # Jujutsu clone activation script generator
│   └── helpers.nix        # Shared helper functions (GPG agent, branch detection)
├── README.org             # User documentation
├── LICENSE                # MIT License
├── air/                   # Air documentation
│   ├── initialise-home-git-clone.org  # Implementation spec
│   ├── v0.1/              # Version 0.1 specifications
│   └── context/           # Context files for AI tools
└── air-config.toml        # Air configuration
```

## Architecture

The project uses a simple, focused architecture:

- **Nix module system** for type-safe configuration with validation at evaluation time
- **Home Manager activation system integration** to run repository operations during `home-manager switch`
- **Bash scripts** for VCS operations (git clone, jj git clone, updates)
- **Environment variable isolation** for git config control (prevents HTTPS→SSH rewrites)

## Core Components

### 1. Module Definition (nix/default.nix)

The main module that declares the `home.gitClone` and `home.jjClone` configuration options:

- **Options declaration**: Type-safe configuration schema using `lib.types`
- **Activation script generation**: Creates bash scripts for each repository
- **SSH setup**: Automatically configures GPG agent SSH socket when available
- **Path configuration**: Handles both standard and worktree directory structures

**Key features**:
- Type validation at Nix evaluation time
- Smart defaults (rev="main", useWorktree=false)
- Per-repository activation entries
- VCS-specific command generation

### 2. Activation Script Generators (nix/git-clone.nix, nix/jj-clone.nix)

Separate modules that generate activation scripts for each VCS:

- **git-clone.nix**: Generates Git clone/update activation scripts
- **jj-clone.nix**: Generates Jujutsu clone/update activation scripts
- **Shared logic via helpers.nix**: GPG agent setup, branch auto-detection

### 3. Flake Interface (flake.nix)

Minimal flake configuration that exposes the module:

- **homeManagerModules.default**: Primary module export (imports ./nix)
- **homeManagerModules.git-clone**: Backwards-compatible alias
- **Simple structure**: Focuses on module exposure

### 4. Repository Configuration Schema

Type-safe options for each repository:

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

**Validation features**:
- Required fields enforced at evaluation time
- Optional nullable types for advanced options
- Default values for common use cases
- Assertions for mutually dependent options (e.g., useWorktree requires rev)

## Document States (Air Workflow)

Air uses these predefined states to track document lifecycle:
- `draft` - Initial planning phase
- `ready` - Specification complete, ready for implementation
- `work-in-progress` - Currently being implemented
- `complete` - Implementation finished
- `dropped` - No longer needed
- `unknown` - State cannot be determined

## Getting Started

1. Add flake input or import module:
   ```nix
   {
     inputs = {
       home-git-clone.url = "github:rytswd/home-git-clone";
     };
   }
   ```

2. Configure repositories in home.gitClone:
   ```nix
   home.gitClone = {
     "Coding/dotfiles" = {
       url = "git@github.com:user/dotfiles.git";
       rev = "main";
     };
   };
   ```

3. Run home-manager switch:
   ```bash
   home-manager switch
   ```

4. Repositories automatically cloned to ~/Coding/dotfiles/

## Current Focus

- **home.gitClone**: Complete and documented (Git repositories)
- **home.jjClone**: Complete and documented (Jujutsu repositories with colocate control)
- **Future enhancements**: Repository groups, pre/post clone hooks, shallow clones

## Key Features

### Declarative Repository Management
- Define repositories in Nix configuration
- Automatic cloning during home-manager activation
- Idempotent operations (safe to run repeatedly)

### Multi-VCS Support
- Git: Standard git clone and pull operations
- Jujutsu: Supports jj git clone with --colocate for Git-compatible repos

### Worktree-Friendly Structure
- Optional mode to append branch name to path
- Easy to create sibling worktrees with `git worktree add`

### Smart HTTPS Handling
- Automatically detects HTTPS URLs
- Bypasses git config to prevent SSH rewrites
- Overridable for special cases

### Multi-User Safe
- Each user's home-manager activation runs with their credentials
- No shared state between users
- Respects user permissions and SSH keys

### GPG Agent Integration
- Automatically detects GPG agent SSH socket
- Uses ~/.gnupg/S.gpg-agent.ssh when available
- Falls back to standard SSH agent

### Optional Auto-Update
- Can automatically pull updates on activation
- Configurable per repository
- Handles updates gracefully (continues on failure)

## Use Cases

- **Dotfiles management**: Clone dotfiles repos to specific locations
- **Development workspace setup**: Automatically clone work repositories on new machines
- **Multi-machine sync**: Same Nix config keeps repos consistent across machines
- **Worktree workflows**: Easy setup for git worktree-based development
- **Jujutsu adoption**: Declarative jj repo management with Git co-location
