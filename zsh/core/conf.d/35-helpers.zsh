# =============================================================================
#  35-helpers.zsh
#  Functions with logic (anything that is not a one-liner alias). Mirrors
#  powershell/core/conf.d/35-helpers.ps1.
# =============================================================================

# --- git clone then cd into the clone -------------------------------------------
gcl() {
    git clone "$@" || return
    cd -- "${${@[-1]:t}%.git}"
}

# --- Files ------------------------------------------------------------------------
mkcd() { mkdir -p -- "$1" && cd -- "$1" }

#  Linux ships touch and wget; these only stand in when the real ones are missing.
if ! nowhere_tool touch; then
    touch() { local f; for f in "$@"; do [[ -e $f ]] || : > "$f"; done }
fi

# --- wget (curl fallback) -----------------------------------------------------------
#  wget <url>          download to the current dir, filename derived from the URL
#  wget <url> -O file  download to a specific filename
#  wget <url> -P dir   download into a specific directory
if ! nowhere_tool wget; then
    wget() {
        local url out dir
        while (( $# )); do
            case $1 in
                -O) out=$2; shift 2 ;;
                -P) dir=$2; shift 2 ;;
                *) url=$1; shift ;;
            esac
        done
        [[ -n $url ]] || { print -u2 'Usage: wget <url> [-O file] [-P dir]'; return 1 }
        [[ -n $out ]] || out=${${url%%[?#]*}:t}
        [[ -n $out && $out != *:* ]] || out=index.html
        if [[ -n $dir ]]; then mkdir -p -- "$dir"; out=$dir/$out; fi
        print -P "%F{cyan}-> $out%f"
        curl -fL -o "$out" "$url"
    }
fi
