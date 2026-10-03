#!/usr/bin/env bash
# netmenu.sh - network popup for polybar's network module.
# Invoked from polybar: %{A1:setsid -f ~/.config/rofi/scripts/netmenu.sh >/dev/null 2>&1 &:} ... %{A}
#
# nmcli is read-only while listing; connect / disconnect / forget only run
# after an explicit selection. Passwords travel as nmcli argv only: never
# logged, never written to disk, never echoed. No terminal is ever opened.

set -u

THEME="${HOME}/.config/rofi/netmenu.rasi"
TITLE="netmenu"          # rofi -window-title netmenu -> WM_NAME "rofi - netmenu"
US=$'\x1f'               # sort-key separator (SSIDs may contain spaces/colons)
RS=$'\x1e'               # separates action name from its argument
SEP=$'·'              # middle dot used in the header
DASH=$'\u2500'

ROFI_PROC_RE='rofi.*-window-title netmenu'   # our popup's rofi process pattern
SUPPRESS_FILE="${XDG_RUNTIME_DIR:-/tmp}/netmenu-$UID.suppress"   # outside-click stamp
DEBUG_LOG="/tmp/netmenu.log"          # NETMENU_DEBUG=1: main rofi stderr + exit code

# Icons: Iosevka Nerd Font covers these; escapes keep this file pure ASCII.
IC_LOCK=$'\uf023'
IC_WIFI=$'\uf1eb'
IC_RES=$'\uf021'
IC_OK=$'\u2713'
IC_OFF=$'\u23fb'
IC_MENU=$'\u2261'
IC_X=$'\u00d7'
IC_BACK=$'\xe2\x86\x90'
BARS=($'\u2581' $'\u2582' $'\u2583' $'\u2584' $'\u2585' $'\u2586' $'\u2587' $'\u2588')

C_OFF="#B5B5B5"           # "Wi-Fi off" header - neutral, no accent
DIM_C="#8A8A8A"           # section separator rows

F=()
WIFI_DEV=""
RADIO="unknown"
HDR="Disconnected"
declare -A AP=()         # SSID -> "active US signal US security"
declare -A ACT=()        # visible row -> action
ROWS=()

notify() {
    command -v notify-send >/dev/null 2>&1 || return 0
    notify-send -u normal "Network" "$1"
}

# Escape pango special characters so odd SSIDs cannot break the header/rows.
pango() {
    local s=$1 out="" i c
    for (( i = 0; i < ${#s}; i++ )); do
        c=${s:i:1}
        case $c in
            '&') out+="&amp;" ;;
            '<') out+="&lt;" ;;
            '>') out+="&gt;" ;;
            *)   out+=$c ;;
        esac
    done
    printf '%s' "$out"
}

# Split one `nmcli -t` line into F[], unescaping "\:" and "\\" (F is global).
nm_split() {
    local line=$1 i c field="" esc=0
    F=()
    for (( i = 0; i < ${#line}; i++ )); do
        c=${line:i:1}
        if (( esc )); then
            field+=$c
            esc=0
        elif [[ $c == "\\" ]]; then
            esc=1
        elif [[ $c == ":" ]]; then
            F+=("$field")
            field=""
        else
            field+=$c
        fi
    done
    (( esc )) && field+="\\"
    F+=("$field")
}

wifi_dev() {
    local line dev=""
    while IFS= read -r line; do
        nm_split "$line"
        if [[ ${F[1]-} == "wifi" ]]; then
            dev=${F[0]-}
            break
        fi
    done < <(nmcli -t -f DEVICE,TYPE device status 2>/dev/null)
    printf '%s' "$dev"
}

# Fill AP[] from the cached scan (instant: --rescan no), strongest wins per SSID.
load_aps() {
    AP=()
    local line inuse ssid sig sec prev pa ps pp
    [[ -z $WIFI_DEV ]] && return 0
    while IFS= read -r line; do
        nm_split "$line"
        inuse=${F[0]-}
        ssid=${F[1]-}
        sig=${F[2]-}
        sec=${F[3]-}
        [[ -z $ssid ]] && continue            # hidden / empty SSID: not listable
        [[ $sig =~ ^[0-9]+$ ]] || sig=0
        [[ $inuse == "*" ]] && inuse=1 || inuse=0
        prev=${AP[$ssid]-}
        if [[ -z $prev ]]; then
            AP[$ssid]="$inuse$US$sig$US$sec"
        else
            IFS=$US read -r pa ps pp <<< "$prev"
            (( sig > ps )) && ps=$sig
            (( inuse > pa )) && pa=$inuse
            [[ -n $sec ]] && pp=$sec
            AP[$ssid]="$pa$US$ps$US$pp"
        fi
    done < <(nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY device wifi list \
                 ifname "$WIFI_DEV" --rescan no 2>/dev/null)
}

# Emit "signal US ssid US active US security" lines, strongest signal first.
sorted_aps() {
    local ssid active sig sec
    for ssid in "${!AP[@]}"; do
        IFS=$US read -r active sig sec <<< "${AP[$ssid]}"
        printf '%s\n' "$sig$US$ssid$US$active$US$sec"
    done | LC_ALL=C sort -t "$US" -k1,1nr
}

sig_bar() {
    local i=$(( $1 * 8 / 100 ))
    (( i > 7 )) && i=7
    (( i < 0 )) && i=0
    printf '%s' "${BARS[i]}"
}

ap_sec() {
    local e=${AP[$1]-} active sig sec
    [[ -z $e ]] && return 0
    IFS=$US read -r active sig sec <<< "$e"
    printf '%s' "$sec"
}

# ACTIVE_SSID / ACTIVE_SIG: from the scan when possible, else active profile.
find_active() {
    ACTIVE_SSID=""
    ACTIVE_SIG=""
    local ssid active sig sec line
    for ssid in "${!AP[@]}"; do
        IFS=$US read -r active sig sec <<< "${AP[$ssid]}"
        if [[ $active == 1 ]]; then
            ACTIVE_SSID=$ssid
            ACTIVE_SIG=$sig
            return 0
        fi
    done
    while IFS= read -r line; do
        nm_split "$line"
        if [[ ${F[1]-} == "802-11-wireless" ]]; then
            ACTIVE_SSID=${F[0]-}
            return 0
        fi
    done < <(nmcli -t -f NAME,TYPE,DEVICE connection show --active 2>/dev/null)
}

build_header() {
    local ip
    if [[ $RADIO != "enabled" ]]; then
        HDR="<span foreground='${C_OFF}'>Wi-Fi off</span>"
        return 0
    fi
    if [[ -z $ACTIVE_SSID ]]; then
        HDR="Disconnected"
        return 0
    fi
    ip=""
    if [[ -n $WIFI_DEV ]]; then
        ip=$(nmcli -g IP4.ADDRESS device show "$WIFI_DEV" 2>/dev/null | head -n1)
        ip=${ip%%/*}
    fi
    HDR="<b>$(pango "$ACTIVE_SSID")</b>"
    [[ -n $ACTIVE_SIG ]] && HDR+=" ${SEP} ${ACTIVE_SIG}%"
    HDR+=" ${SEP} ${ip:-no IP}"
}

type_label() {
    case $1 in
        802-3-ethernet) printf 'wired' ;;
        802-11-wireless) printf 'wi-fi' ;;
        vpn)            printf 'VPN' ;;
        wireguard)      printf 'WireGuard' ;;
        gsm|cdma)       printf 'mobile' ;;
        *)              printf '%s' "$1" ;;
    esac
}

add_row() {
    ROWS+=("$1")
    ACT["$1"]=${2:-noop}
}

# Section dividers: dim gray so they read as structure, not selectable content.
dim_row() {
    printf '<span foreground="%s">%s</span>' "$DIM_C" "$1"
}

build_menu() {
    ROWS=()
    ACT=()
    local line name type dev ssid active sig sec row saved=0 s
    local -A IN_SCAN=()

    if [[ $RADIO == "enabled" ]]; then
        add_row "$IC_OFF Wi-Fi on" "toggle${RS}off"
    else
        add_row "$IC_OFF Wi-Fi off" "toggle${RS}on"
    fi

    if [[ $RADIO == "enabled" ]]; then
        if [[ -n $ACTIVE_SSID ]]; then
            add_row "$IC_X Disconnect $(pango "$ACTIVE_SSID")" "disconnect"
        fi
        add_row "$IC_RES Rescan" "rescan"

        add_row "$(dim_row "$DASH$DASH Wi-Fi networks $DASH$DASH")" "noop"
        if (( ${#AP[@]} == 0 )); then
            add_row "No networks found" "noop"
        else
            while IFS=$US read -r sig ssid active sec; do
                IN_SCAN[$ssid]=1
                row="$(sig_bar "$sig") "
                [[ -n $sec ]] && row+="$IC_LOCK"
                row+=" $(pango "$ssid")"
                [[ $active == 1 ]] && row+=" $IC_OK"
                add_row "$row" "net${RS}${ssid}"
            done < <(sorted_aps)
        fi
    fi

    add_row "$(dim_row "$DASH$DASH Saved, wired, VPN $DASH$DASH")" "noop"
    while IFS= read -r line; do
        nm_split "$line"
        name=${F[0]-}
        type=${F[1]-}
        dev=${F[2]-}
        [[ -z $name ]] && continue
        [[ $type == "loopback" || $type == "bridge" ]] && continue
        if [[ $type == "802-11-wireless" ]]; then
            s=$(nmcli -g 802-11-wireless.ssid connection show id "$name" 2>/dev/null) || s=""
            [[ -n $s && -n ${IN_SCAN[$s]+x} ]] && continue   # already listed above
        fi
        row="$(pango "$name") $SEP $(type_label "$type")"
        if [[ -n $dev ]]; then
            add_row "$row (up)" "down${RS}${name}"
        else
            add_row "$row (down)" "up${RS}${name}"
        fi
        saved=1
    done < <(nmcli -t -f NAME,TYPE,DEVICE connection show 2>/dev/null)
    if (( saved == 0 )); then
        add_row "No saved connections" "noop"
    fi

    add_row "$IC_WIFI Join hidden network..." "hidden"
    add_row "$IC_X Forget saved network..." "forget"
    add_row "$IC_MENU Edit connections..." "edit"
}

find_profile_for_ssid() {
    local target=$1 line name ssid
    while IFS= read -r line; do
        nm_split "$line"
        [[ ${F[1]-} == "802-11-wireless" ]] || continue
        name=${F[0]-}
        [[ -z $name ]] && continue
        ssid=$(nmcli -g 802-11-wireless.ssid connection show id "$name" 2>/dev/null) || continue
        if [[ $ssid == "$target" ]]; then
            printf '%s' "$name"
            return 0
        fi
    done < <(nmcli -t -f NAME,TYPE connection show 2>/dev/null)
    return 1
}

# Compact single-field prompt: one input row, no list, same gray-glass theme.
# $1 placeholder, $2 -mesg line ("" = none), $3 "password" for masked input.
# Password mode binds Alt+S (rofi exit code 10) to reveal/hide; the typed text
# survives the toggle via -filter. Prints the text on Enter; any other exit
# (Esc, outside click, killed) prints nothing and returns nonzero.
text_prompt() {
    local ph=$1 msg=${2:-} mode=${3:-}
    local rc text="" masked=1 reshow=0
    local -a cmd
    [[ $mode == password ]] || masked=0
    while true; do
        cmd=(rofi -dmenu -normal-window -window-title "$TITLE" -theme "$THEME"
             -l 0 -format f -theme-str "listview { lines: 0; }"
             -theme-str "entry { placeholder: \"$ph\"; }")
        [[ -n $msg ]] && cmd+=(-mesg "$msg")
        if [[ $mode == password ]]; then
            cmd+=(-kb-custom-1 "Alt+s")
            (( masked )) && cmd+=(-password)
        fi
        (( reshow )) && cmd+=(-filter "$text")
        reshow=0
        text=$("${cmd[@]}" </dev/null)
        rc=$?
        if (( rc == 10 )); then
            masked=$(( 1 - masked ))
            reshow=1           # keep the typed text across the toggle
            continue
        fi
        if (( rc == 0 )); then
            printf '%s' "$text"
            text=""
            return 0
        fi
        text=""                # cancelled: drop the input, print nothing
        return 1
    done
}

connect_ssid() {
    local ssid=$1 prof sec pw
    prof=$(find_profile_for_ssid "$ssid")
    if [[ -n $prof ]]; then
        run_nmcli "Connecting to $ssid" nmcli connection up id "$prof"
        return 0
    fi
    sec=$(ap_sec "$ssid")
    if [[ -z $sec ]]; then
        run_nmcli "Connecting to $ssid" nmcli device wifi connect "$ssid"
        return 0
    fi
    pw=$(text_prompt "Password" \
             "Password for <b>$(pango "$ssid")</b> · Alt+S: show/hide" \
             password) || return 0
    [[ -z ${pw:-} ]] && return 0               # empty input = cancel
    run_nmcli "Connecting to $ssid" nmcli device wifi connect "$ssid" password "$pw"
    pw=""
}

connect_hidden() {
    local ssid pw
    ssid=$(text_prompt "Network name (SSID)" "Join a hidden network") || return 0
    [[ -z ${ssid:-} ]] && return 0
    pw=$(text_prompt "Password" \
             "Password for <b>$(pango "$ssid")</b> · leave empty for an open network · Alt+S: show/hide" \
             password) || return 0
    if [[ -z ${pw:-} ]]; then
        run_nmcli "Connecting to $ssid" nmcli device wifi connect "$ssid" hidden yes
    else
        run_nmcli "Connecting to $ssid" nmcli device wifi connect "$ssid" \
                  hidden yes password "$pw"
    fi
    pw=""
    ssid=""
}

confirm_forget() {
    local name=$1
    # No list: Enter (any input) deletes the profile, Esc cancels.
    text_prompt "Enter = confirm" \
        "Forget <b>$(pango "$name")</b>? Enter deletes the profile and its saved password, Esc cancels" \
        >/dev/null || return 0
    run_nmcli "Forgot $name" nmcli connection delete id "$name"
}

forget_menu() {
    local line name choice display
    local back="${IC_BACK} Back"
    local rows=("$back")
    local -A act=()
    while IFS= read -r line; do
        nm_split "$line"
        [[ ${F[1]-} == "802-11-wireless" ]] || continue
        name=${F[0]-}
        [[ -z $name ]] && continue
        display="$IC_X $(pango "$name")"
        rows+=("$display")
        act["$display"]=$name
    done < <(nmcli -t -f NAME,TYPE connection show 2>/dev/null)
    if (( ${#rows[@]} == 1 )); then
        notify "No saved Wi-Fi networks"
        return 0
    fi
    choice=$(printf '%s\n' "${rows[@]}" | rofi -dmenu -i -markup-rows -only-match \
                 -normal-window -window-title "$TITLE" -theme "$THEME" -p "Forget" \
                 -mesg "Pick a saved network to delete" -format s)
    [[ -z ${choice:-} || $choice == "$back" ]] && return 0
    name=${act[$choice]-}
    [[ -z $name ]] && return 0
    confirm_forget "$name"
}

run_nmcli() {
    local msg=$1 out rc
    shift
    out=$("$@" 2>&1)
    rc=$?
    if (( rc == 0 )); then
        notify "$msg"
    else
        notify "Failed: ${out:-nmcli error}"
    fi
}

dispatch() {
    local choice=$1 action arg
    action=${ACT[$choice]-noop}
    arg=${action#*"$RS"}
    action=${action%%"$RS"*}
    case $action in
        noop) ;;
        toggle)
            if [[ $arg == on ]]; then
                run_nmcli "Wi-Fi enabled" nmcli radio wifi on
            else
                run_nmcli "Wi-Fi disabled" nmcli radio wifi off
            fi
            ;;
        rescan)
            if [[ -n $WIFI_DEV ]]; then
                nmcli device wifi rescan ifname "$WIFI_DEV" >/dev/null 2>&1
                sleep 1
                notify "Wi-Fi networks rescanned"
            else
                notify "No Wi-Fi device"
            fi
            ;;
        net)      connect_ssid "$arg" ;;
        hidden)   connect_hidden ;;
        disconnect)
            if [[ -n $WIFI_DEV ]]; then
                run_nmcli "Disconnected" nmcli device disconnect "$WIFI_DEV"
            fi
            ;;
        up)       run_nmcli "Activating $arg" nmcli connection up id "$arg" ;;
        down)      run_nmcli "Deactivating $arg" nmcli connection down id "$arg" ;;
        forget)    forget_menu ;;
        edit)      nm-connection-editor >/dev/null 2>&1 & ;;
        *) ;;
    esac
}

# Popup lifecycle: rofi runs -normal-window (no X grabs), so the whole desktop
# stays live; close via Esc, the focus watcher below, the outside-click pointer
# watcher, or a toggle click on the polybar label.
WATCH_PID=""

kill_netmenu() {
    pkill -TERM -f "$ROFI_PROC_RE" 2>/dev/null
}

stop_watcher() {
    [[ -z ${WATCH_PID:-} ]] && return 0
    pkill -TERM -P "$WATCH_PID" 2>/dev/null
    kill -TERM "$WATCH_PID" 2>/dev/null
    WATCH_PID=""
}

watch_events() {
    sleep 0.6                        # let rofi map and focus first
    local ev
    while IFS= read -r ev; do
        [[ $ev == *'rofi - netmenu'* ]] && continue   # events about our popup
        [[ $ev == *'"change":"focus"'* ]] || continue # focus only, not new/title
        kill_netmenu
        break
    done < <(i3-msg -t subscribe -m '["window","workspace"]' 2>/dev/null)
}

start_watcher() {
    command -v i3-msg >/dev/null 2>&1 || return 0
    watch_events 9>&- &
    WATCH_PID=$!
}

# Raw pointer fallback: a click landing outside the popup geometry closes it.
PW_PID=""

pointer_outside() {
    command -v xdotool >/dev/null 2>&1 || return 1
    command -v xwininfo >/dev/null 2>&1 || return 1
    local wid X Y AX AY W H
    wid=$(xdotool search --name 'rofi - netmenu' 2>/dev/null | head -n1)
    [[ -z $wid ]] && return 0                      # popup already gone
    eval "$(xdotool getmouselocation --shell 2>/dev/null | grep -E '^[XY]=')"
    eval "$(xwininfo -id "$wid" 2>/dev/null | awk '
        /Absolute upper-left X:/{print "AX="$NF}
        /Absolute upper-left Y:/{print "AY="$NF}
        /^ *Width:/{print "W="$NF}
        /^ *Height:/{print "H="$NF}')"
    [[ -z ${X:-}${Y:-}${AX:-}${AY:-}${W:-}${H:-} ]] && return 1   # unknown: never kill
    (( X < AX || X >= AX + W || Y < AY || Y >= AY + H )) && return 0
    return 1
}

watch_pointer() {
    local t0 now line
    t0=$(date +%s%N)
    while IFS= read -r line; do
        [[ $line == *RawButtonPress* ]] || continue
        now=$(date +%s%N)
        (( now - t0 < 400000000 )) && continue          # ignore first ~0.4s
        pointer_outside || continue
        printf '%s' "$(date +%s%N)" > "$SUPPRESS_FILE"  # block instant reopen
        kill_netmenu
        break
    done < <(xinput test-xi2 --root 2>/dev/null)
}

start_pointer_watcher() {
    command -v xinput >/dev/null 2>&1 || return 0
    command -v xdotool >/dev/null 2>&1 || return 0
    command -v xwininfo >/dev/null 2>&1 || return 0
    watch_pointer 9>&- &
    PW_PID=$!
}

stop_pointer_watcher() {
    [[ -z ${PW_PID:-} ]] && return 0
    pkill -TERM -P "$PW_PID" 2>/dev/null
    kill -TERM "$PW_PID" 2>/dev/null
    PW_PID=""
}

# Polybar is still mid-click when setsid starts us; map only after the button
# is up so focus and typing land cleanly on the new window.
wait_buttons_released() {
    local i
    if ! command -v xinput >/dev/null 2>&1; then
        sleep 0.4                       # degrade: fixed grace period
        return 0
    fi
    for (( i = 0; i < 75; i++ )); do    # ~1.5s max, 20ms steps
        xinput query-state 'Virtual core pointer' 2>/dev/null \
            | grep -qE 'button\[[0-9]+\]=down' || return 0
        sleep 0.02
    done
}

cleanup_all() {
    stop_watcher
    stop_pointer_watcher
}

main() {
    command -v nmcli >/dev/null 2>&1 || { notify "nmcli not available"; exit 1; }
    command -v rofi >/dev/null 2>&1 || { notify "rofi not available"; exit 1; }

    # Outside click stamped a short suppress window; the same click landing on
    # the polybar label must not reopen the popup.
    if [[ -f $SUPPRESS_FILE ]]; then
        local now ts
        now=$(date +%s%N)
        ts=$(<"$SUPPRESS_FILE")
        if [[ $ts =~ ^[0-9]+$ ]] && (( now - ts < 500000000 )); then
            exit 0
        fi
    fi

    # Toggle: popup already open -> close it, never stack a second one.
    if pgrep -f "$ROFI_PROC_RE" >/dev/null 2>&1; then
        kill_netmenu
        exit 0
    fi

    # Single instance: fd 9 closes (lock released) the moment this script exits.
    exec 9>"${XDG_RUNTIME_DIR:-/tmp}/netmenu-$UID.lock"
    flock -n 9 2>/dev/null || exit 0

    trap cleanup_all EXIT

    WIFI_DEV=$(wifi_dev)
    RADIO=$(nmcli radio wifi 2>/dev/null)
    [[ -z $RADIO ]] && RADIO="unknown"

    load_aps
    find_active

    # one background refresh so the next open sees fresh results
    if [[ -n $WIFI_DEV && $RADIO == "enabled" ]]; then
        nmcli device wifi rescan ifname "$WIFI_DEV" >/dev/null 2>&1 9>&- &
        disown 2>/dev/null || true
    fi

    build_header
    build_menu

    wait_buttons_released    # polybar holds the grab while its click is down
    start_watcher            # i3 focus/workspace fallback
    start_pointer_watcher    # raw button press outside the popup -> close
    local choice
    if [[ ${NETMENU_DEBUG:-0} == 1 ]]; then
        choice=$(printf '%s\n' "${ROWS[@]}" | rofi -dmenu -i -markup-rows -only-match \
                     -normal-window -window-title "$TITLE" -theme "$THEME" \
                     -mesg "$HDR" -format s 2>>"$DEBUG_LOG")
        printf '%s main rofi rc=%s\n' "$(date -Is)" "$?" >>"$DEBUG_LOG"
    else
        choice=$(printf '%s\n' "${ROWS[@]}" | rofi -dmenu -i -markup-rows -only-match \
                     -normal-window -window-title "$TITLE" -theme "$THEME" \
                     -mesg "$HDR" -format s 2>/dev/null)
    fi
    [[ -z ${choice:-} ]] && exit 0    # Esc / click outside / focus+pointer watchers
    dispatch "$choice"
    exit 0
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi
