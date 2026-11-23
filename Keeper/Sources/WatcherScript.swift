import Foundation

/// The shell script that watches the App Store download folder.
///
/// Arguments: <App Store cache folder> <output .pkg> <staging folder> <uid to give the file to, or "">
///
/// It writes one line to <staging>/status so the app can follow along:
///   waiting | found <path> | link <path> | copy <path> | done | stopped | timeout | noaccess | copyfailed
///
/// It first tries a hard link: a second name for the same file. The link keeps the
/// package when the App Store deletes its own copy, and costs no disk space or time.
/// If a link is not possible, it falls back to copying the file every second.
enum WatcherScript {
    static let source = #"""
#!/bin/sh
base="$1"
out="$2"
staging="$3"
owner="$4"

link="$staging/capture.link"
marker="$staging/marker"
stop="$staging/stop"
status="$staging/status"

say() { echo "$1" > "$status"; }

finish() {
    if [ -n "$owner" ] && [ "$(id -u)" = "0" ]; then
        chown "$owner" "$out" 2>/dev/null
    fi
    say "done"
    exit 0
}

parent=$(dirname "$base")
start=$(date +%s)
existing="$staging/existing"
# Remember packages that are already there, so only a new download is picked up.
find "$base" -type f -name '*.pkg' -print 2>/dev/null > "$existing"
say "waiting"

while :; do
    [ -e "$stop" ] && { say "stopped"; exit 4; }

    now=$(date +%s)
    [ $((now - start)) -gt 7200 ] && { say "timeout"; exit 5; }

    for d in "$parent" "$base"; do
        if [ -d "$d" ] && ! ls "$d" >/dev/null 2>&1; then
            say "noaccess"
            exit 3
        fi
    done

    f=$(find "$base" -type f -name '*.pkg' -print 2>"$staging/find.err" | grep -vxF -f "$existing" | head -n 1)

    # Without admin rights, a folder deeper inside can be closed to us. Then find
    # fails quietly, so look at its errors and ask for admin rights.
    if [ -z "$f" ] && [ "$(id -u)" != "0" ] && grep -qE 'Permission denied|Operation not permitted' "$staging/find.err" 2>/dev/null; then
        say "noaccess"
        exit 3
    fi

    if [ -n "$f" ]; then
        say "found $f"
        rm -f "$link"

        if ln "$f" "$link" 2>/dev/null; then
            say "link $f"
            prev=-1
            stable=0
            while :; do
                [ -e "$stop" ] && { rm -f "$link"; say "stopped"; exit 4; }
                # The App Store deletes its copy after the install (or the failed install).
                [ -e "$f" ] || break
                size=$(stat -f%z "$link" 2>/dev/null || echo 0)
                if [ "$size" -gt 0 ] && [ "$size" -eq "$prev" ]; then
                    stable=$((stable + 1))
                else
                    stable=0
                fi
                prev=$size
                [ "$stable" -ge 30 ] && break
                sleep 1
            done
            rm -f "$out"
            cp -c "$link" "$out" 2>/dev/null || cp "$link" "$out" || { say "copyfailed"; exit 6; }
            rm -f "$link"
            finish
        else
            say "copy $f"
            prev=-1
            stable=0
            while [ -f "$f" ]; do
                [ -e "$stop" ] && { say "stopped"; exit 4; }
                size=$(stat -f%z "$f" 2>/dev/null || echo 0)
                if [ "$size" -gt 0 ]; then
                    cp "$f" "$out.tmp" 2>/dev/null && mv -f "$out.tmp" "$out"
                    if [ "$size" -eq "$prev" ]; then
                        stable=$((stable + 1))
                    else
                        stable=0
                    fi
                    prev=$size
                    [ "$stable" -ge 5 ] && finish
                fi
                sleep 1
            done
            [ -s "$out" ] && finish
            say "waiting"
        fi
    fi

    sleep 0.5
done
"""#
}
