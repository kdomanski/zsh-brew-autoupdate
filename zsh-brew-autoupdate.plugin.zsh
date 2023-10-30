function current_epoch() {
  zmodload zsh/datetime
  echo $(( EPOCHSECONDS / 60 / 60 ))
}

function update_last_updated_file() {
    local LAST_UPDATE_EPOCH

    if [[ -f "${ZSH_CACHE_DIR}/.brew-auto-update" ]]; then
        source "${ZSH_CACHE_DIR}/.brew-auto-update"
    fi

    if [[ -n "$1" ]]; then
        LAST_UPDATE_EPOCH="$1"
    fi

    echo "LAST_UPDATE_EPOCH=${LAST_UPDATE_EPOCH}" >! "${ZSH_CACHE_DIR}/.brew-auto-update"
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
        if brew outdated 2>/dev/null > "${ZSH_CACHE_DIR}/.brew-outdated" ; then
            update_last_updated_file "$(current_epoch)"

            if command -v terminal-notifier &>/dev/null; then
                local num_of_updates
                num_of_updates="$(cat ${ZSH_CACHE_DIR}/.brew-outdated | wc -l)"
                if [[ "$num_of_updates" -gt 0 ]]; then
                    terminal-notifier -message "$num_of_updates updates are available" -title "Homebrew"
                fi
            fi
        fi
    fi
}

() {
    emulate -L zsh

    local epoch_target mtime LAST_UPDATE_EPOCH

    # Remove lock directory if older than a day
    zmodload zsh/datetime
    zmodload -F zsh/stat b:zstat
    if mtime=$(zstat +mtime "$ZSH/log/brew-auto-update.lock" 2>/dev/null); then
        if (( (mtime + 3600 * 24) < EPOCHSECONDS )); then
            command rm -rf "$ZSH/log/brew-auto-update.lock"
        fi
    fi

    # Create or update .brew-auto-update file if missing or malformed
    if ! source "${ZSH_CACHE_DIR}/.brew-auto-update" 2>/dev/null || [[ -z "$LAST_UPDATE_EPOCH" ]]; then
        update_last_updated_file "$(current_epoch)"
        return
    fi

    ### brew update
    # check updates every 24 hours
    epoch_target=24

    if (( ( $(current_epoch) - $LAST_UPDATE_EPOCH ) >= $epoch_target )); then
        # Check for lock directory
        if ! command mkdir "$ZSH/log/brew-auto-update.lock" 2>/dev/null; then
            return
        fi

        echo "[zsh-brew-autoupdate] Starting a Homebrew update check in background."
        update_homebrew &>/dev/null &!
        return
    fi

    if [[ -f "${ZSH_CACHE_DIR}/.brew-outdated" ]] && [[ "$(cat ${ZSH_CACHE_DIR}/.brew-outdated | wc -l)" -gt 0 ]]; then
        local fistpkg pkgmtime outdatedmtime

        firstpkg="$(head -n1 ${ZSH_CACHE_DIR}/.brew-outdated)"
        firstpkg="${firstpkg##*/}"
        pkgmtime="$(date -r $HOMEBREW_CELLAR/${firstpkg}/*/INSTALL_RECEIPT.json '+%s')"
        outdatedmtime="$(date -r ${ZSH_CACHE_DIR}/.brew-outdated '+%s')"

        # was it installed after we checked for outdated packages?
        if [[ "$pkgmtime" -gt "$outdatedmtime" ]]; then
            rm "${ZSH_CACHE_DIR}/.brew-outdated"
        else
            echo "[zsh-brew-autoupdate] There seem to be outdated Homebrew packages."
        fi

        unset firstpkg pkgmtime outdatedmtime
    fi
}

unset -f current_epoch update_last_updated_file update_homebrew
