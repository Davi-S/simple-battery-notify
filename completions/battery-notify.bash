# bash completion for battery-notify

_battery_notify() {
    local -r cur="${COMP_WORDS[COMP_CWORD]}"
    COMPREPLY=()
    if ((COMP_CWORD == 1)); then
        mapfile -t COMPREPLY < <(compgen -W "--daemon --help --version" -- "$cur")
    fi
}

complete -F _battery_notify battery-notify
