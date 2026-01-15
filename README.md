# prs

CLI for managing GitHub PRs and Buildkite CI.

## Requirements

- [gh](https://cli.github.com/) - GitHub CLI (authenticated)
- [bk](https://github.com/buildkite/cli) - Buildkite CLI (authenticated)
- [jq](https://jqlang.github.io/jq/) - JSON processor
- bash 4+

## Install

```bash
# Add to PATH
export PATH="$HOME/bin:$PATH"

# Optional: enable tab completion
source ~/bin/prs.d/completion.bash
```

## Usage

```
prs                  # List outstanding PRs
prs <topic>          # Show chain containing topic
prs this             # PRs for current worktree
prs -s <topic>       # Detailed status
prs -d <topic>       # Show diff
prs -f <topic>       # List changed files
prs -m <topic>       # Add to merge queue
prs -c <topic>       # Close PR
prs -w <topic>       # Open in browser
prs -bs <topic>      # Show build steps
prs -br <topic> <#>  # Retry build job
prs -brf <topic>     # Retry all failed jobs
prs -h               # Full help
```

## Config

Edit `prs.d/config.sh` to change defaults:
- `GITHUB_USER` - Your GitHub username
- `BRANCH_USER` - Your branch prefix (e.g., `firstname.lastname`)
- `REPO` - Target repository
