function current_epoch() {
  zmodload zsh/datetime
  echo $(( EPOCHSECONDS / 60 / 60 / 24 ))
}

function update_last_updated_file() {
  echo "LAST_EPOCH=$(current_epoch)" >! "${ZSH_CACHE_DIR}/.brew-auto-update"
}

function update_homebrew() {
    # Remove lock directory on exit. `return $ret` is important for when trapping a SIGINT:
    #  The return status from the function is handled specially. If it is zero, the signal is
    #  assumed to have been handled, and execution continues normally. Otherwise, the shell
    #  will behave as interrupted except that the return status of the trap is retained.
    #  This means that for a CTRL+C, the trap needs to return the same exit status so that
    #  the shell actually exits what it's running.
    trap "
        ret=\$?
        unset -f current_epoch update_last_updated_file update_homebrew
        command rm -rf '$ZSH/log/brew-auto-update.lock'
        return \$ret
    " EXIT INT QUIT

    if brew update &>/dev/null; then
        update_last_updated_file
    fi
}

() {
    emulate -L zsh

    local epoch_target mtime  LAST_EPOCH

    # Remove lock directory if older than a day
    zmodload zsh/datetime
    zmodload -F zsh/stat b:zstat
    if mtime=$(zstat +mtime "$ZSH/log/brew-auto-update.lock" 2>/dev/null); then
        if (( (mtime + 3600 * 24) < EPOCHSECONDS )); then
            command rm -rf "$ZSH/log/brew-auto-update.lock"
        fi
    fi

    # Create or update .zsh-update file if missing or malformed
    if ! source "${ZSH_CACHE_DIR}/.brew-auto-update" 2>/dev/null || [[ -z "$LAST_EPOCH" ]]; then
        update_last_updated_file
        return
    fi

    # check every day
    epoch_target=1

    if (( ( $(current_epoch) - $LAST_EPOCH ) < $epoch_target )); then
        return
    fi

    # Check for lock directory
    if ! command mkdir "$ZSH/log/brew-auto-update.lock" 2>/dev/null; then
        return
    fi

    echo "[zsh-brew-auto-upgrade] Starting a Homebrew update in background."
    update_homebrew &>/dev/null &!
}

unset -f current_epoch update_last_updated_file update_homebrew