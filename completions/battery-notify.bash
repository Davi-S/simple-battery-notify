# bash completion for battery-notify

_battery_notify() {
    local -r cur="${COMP_WORDS[COMP_CWORD]}"
    COMPREPLY=()
    # Only the command is completed: no command takes arguments.
    if ((COMP_CWORD == 1)); then
        mapfile -t COMPREPLY < <(compgen -W "show status daemon --help --version" -- "$cur")
    fi
}

complete -F _battery_notify battery-notify
