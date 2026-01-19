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

## Installation Guide

### 1. Install Dependencies

**macOS:**
```bash
brew install gh jq
brew install buildkite/buildkite/bk
```

**Ubuntu/Debian:**
```bash
sudo apt install gh jq
```

**Buildkite CLI:** https://buildkite.com/docs/platform/cli/installation

### 2. Authenticate CLIs

**GitHub CLI:**
```bash
gh auth login
```
Follow prompts to authenticate via browser.

**Buildkite CLI:**
```bash
bk configure
```
You'll need a Buildkite API token:
1. Go to https://buildkite.com/user/api-access-tokens
2. Click "New API Access Token"
3. Select scopes: `read_builds`, `write_builds`, `read_pipelines`, `read_artifacts`, `read_build_logs`, `graphql`
4. Under "Organization Access", select your org
5. Copy the token and paste when prompted

### 3. Run Install Script

```bash
git clone <repo-url>
cd "$(basename "$_" .git)"
./install.sh
```

The script will:
- Verify dependencies and authentication
- Create symlinks in `~/bin`
- Prompt for your config (GitHub username, branch prefix, target repo)
- Optionally enable tab completion

After install:
```bash
source ~/.bashrc
prs --help
```
