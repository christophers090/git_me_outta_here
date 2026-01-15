# prs.d - PR Status Tool Modules

Modular components for the `prs` CLI tool.

## Structure

```
prs.d/
├── config.sh              # Colors, symbols, user config
├── helpers.sh             # Shared PR helpers (find_pr, format_duration, etc.)
├── helpers_buildkite.sh   # Buildkite-specific helpers
├── completion.bash        # Bash tab completion
└── mode_*.sh              # Command modes (one per flag)
```

## Adding a New Mode

1. Create `mode_<name>.sh` with a `run_<name>()` function
2. Add flag parsing in main `prs` script
3. Update usage() help text

## Key Helpers

**helpers.sh:**
- `find_pr(topic, state, fields)` - Find PR by topic
- `pr_exists(json)`, `pr_field(json, field)` - Parse PR JSON
- `require_topic(mode, topic)` - Validate topic arg
- `format_duration(seconds)` - Human readable time
- `open_url(url)` - Open URL in browser

**helpers_buildkite.sh:**
- `get_build_for_topic(topic)` - Sets `BK_BUILD_JSON`, `BK_BUILD_NUMBER`, `BK_BUILD_URL`
- `get_job_by_number(num)` - Sets `BK_JOB_ID`, `BK_JOB_NAME`, `BK_JOB_STATE`
- `strip_emoji(text)` - Remove `:emoji:` codes
- `check_job_cancelable(num, topic)` - Validate job can be canceled
- `check_job_retriable(num, topic)` - Validate job can be retried

## Modes with Sub-flags

Some modes accept additional flags after the topic/job args:
- `-bcon <topic> <#> [-n N]` - The `-n` flag is passed through to the mode
