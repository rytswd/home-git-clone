# Documentation Conventions

## Document States
Air uses six predefined states for document lifecycle management:

- **draft**: Initial planning phase - document is being written and refined
- **ready**: Specification complete, ready for implementation
- **work-in-progress**: Currently being implemented or actively worked on
- **complete**: Implementation finished and documented
- **dropped**: No longer needed or abandoned
- **unknown**: State cannot be determined from document metadata

## Document Structure
Recommended structure for Air documents:

### For Org-mode (.org files):
```
#+title: Document Title
#+state: draft|ready|work-in-progress|complete|dropped
#+FILETAGS: :tag1:tag2:tag3:

* Summary
Brief overview of what this document addresses.

* Motivation
Why this work is needed and what problems it solves.

* Proposal
Detailed specification of the solution.

* Implementation Notes
- YYYY-MM-DD: Progress or decisions made
```

### For Markdown (.md files):
```markdown
---
title: Document Title
state: draft|ready|work-in-progress|complete|dropped
tags: [tag1, tag2, tag3]
---

# Summary
Brief overview of what this document addresses.

# Motivation
Why this work is needed and what problems it solves.

# Proposal
Detailed specification of the solution.

# Implementation Notes
- YYYY-MM-DD: Progress or decisions made
```

## Optional Sections
Consider adding these sections as needed:
- **Goals/Non-Goals**: Clarify scope boundaries
- **Design Details**: Technical implementation specifics
- **Test Plan**: How to validate the implementation
- **Dependencies**: External requirements or blockers
- **Alternatives Considered**: Other approaches evaluated

## Tag Taxonomy

<!-- TODO: Define project-specific tags -->
<!-- Example categories to consider:
### Feature Areas
- `:frontend:` - User interface components
- `:backend:` - Server-side logic
- `:database:` - Data storage and retrieval
- `:api:` - External interfaces

### Work Types
- `:feature:` - New functionality
- `:bugfix:` - Bug corrections
- `:refactor:` - Code improvements
- `:docs:` - Documentation updates
- `:test:` - Testing improvements
-->
- `:context:` - Context generation and AI integration
- `:ai:` - AI tool integration features
- `:tui:` - Terminal user interface
- `:web:` - Web interface components
- `:cli:` - Command-line interface features

### Tag Usage in Documents
- **Org-mode**: Use `#+FILETAGS: :tag1:tag2:tag3:` format
- **Markdown**: Use `tags: [tag1, tag2, tag3]` in YAML/TOML front matter

## File Naming Patterns

- Use lowercase with hyphens: `air-config.org`, `status-command.org`
- Include component prefix when relevant: `airctl-show.org`, `airctl-update.org`
- Use descriptive names that match the document title
- Avoid abbreviations unless widely understood

## Directory Structure and Organization

### Main Directory Structure
```
./air/                    # Main Air directory
├── v0.1/                # Version 0.1 specifications
├── v0.2/                # Version 0.2 specifications
├── archive/             # Completed or obsolete documents
├── templates/           # Document templates
└── context/             # Generated context files
```

### Version-Aware Organization
- Use semantic versioning for directory names: `v0.1`, `v0.2`, `v0.10`
- Directories sort correctly with version-aware comparison
- Move completed work to `archive/` when no longer actively referenced
- Use milestone-based organization rather than date-based

### Overview Files
- Place `OVERVIEW.org` or `README.org` in each major directory
- Overview files excluded from status counts
- Use to summarize the contents and purpose of each directory

## File Type Preferences
Default supported formats from air-config.toml:
- **Primary**: `.org` files (Org-mode format)
- **Secondary**: `.md` files (Markdown format)
- Extensible system allows adding new formats

## Metadata Conventions

### State Updates
- Always update `#+state:` property when work status changes
- Add entry to "Implementation History" section with date and description
- Use ISO date format (YYYY-MM-DD) for consistency

### Git Integration
- Air is Git-aware but doesn't require Git
- Document dates can be extracted from Git history when available
- Filesystem timestamps used as fallback

### Implementation History Format
```
* Implementation History
- 2025-08-26: Initial draft created
- 2025-08-27: Moved to ready state after review
- 2025-08-28: Implementation started, state changed to work-in-progress
- 2025-08-29: Core functionality complete
- 2025-08-30: Testing complete, marked as complete
```

## Archive Management
- Move documents to `archive/` when implementation is complete and stable
- Keep documents in main directories while still being referenced
- Archive inclusion controlled by `include-archive` config option
- Archived documents excluded from status counts by default
