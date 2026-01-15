# Bash completion for prs
# Source this file or add to ~/.bashrc:
#   source ~/bin/prs.d/completion.bash

_prs_completions() {
    local cur prev opts topics
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    # All available flags
    opts="-o --outstanding -s --status -d --diff -f --files -m --merge -c --close -w --web -bw -bs -bc -br -brf -rq -qs --open --closed --merged -u --user -h --help"

    # If completing a flag
    if [[ ${cur} == -* ]]; then
        COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
        return 0
    fi

    # If previous word was -u/--user, don't complete (user types username)
    if [[ ${prev} == "-u" || ${prev} == "--user" ]]; then
        return 0
    fi

    # If previous word was a job number flag, and we already have topic, complete job numbers
    if [[ ${prev} =~ ^[0-9]+$ ]]; then
        return 0
    fi

    # Get topics from open PRs (cached, background refresh)
    local cache_file="/tmp/prs_topics_cache_${USER}"
    local lock_file="/tmp/prs_topics_cache_${USER}.lock"
    local cache_age=1000

    # Always use cached topics immediately (even if stale)
    if [[ -f "$cache_file" ]]; then
        topics=$(cat "$cache_file")
    fi

    # Check if cache needs refresh
    local needs_refresh=false
    if [[ ! -f "$cache_file" ]]; then
        needs_refresh=true
    else
        local file_age=$(( $(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0) ))
        if [[ $file_age -ge $cache_age ]]; then
            needs_refresh=true
        fi
    fi

    # Background refresh if needed (and not already running)
    if [[ "$needs_refresh" == true ]] && ! [[ -f "$lock_file" ]]; then
        (
            touch "$lock_file"
            trap "rm -f '$lock_file'" EXIT
            local gh_user
            gh_user=$(gh api user -q .login 2>/dev/null)
            if [[ -n "$gh_user" ]]; then
                gh pr list -R "${PRS_REPO}" --author "$gh_user" --state open \
                    --json body,headRefName 2>/dev/null | \
                    jq -r '.[] | ((.body | capture("Topic:\\s*(?<t>\\S+)") | .t) // (.headRefName | split("/") | last))' 2>/dev/null \
                    > "$cache_file"
            fi
        ) &>/dev/null &
        disown
    fi

    COMPREPLY=( $(compgen -W "${topics}" -- ${cur}) )
    return 0
}

complete -F _prs_completions prs
