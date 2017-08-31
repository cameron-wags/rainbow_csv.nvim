#!/usr/bin/env bash
#xdotool windowactivate 41943044 type --window 41943044 --clearmodifiers --delay 100 ls
window_id="$1"
if [ -z "$window_id" ] ; then
    echo "Error: window id is not provided" >&2
    exit 1
fi
xdotool windowactivate "$window_id"
xdotool type --clearmodifiers --delay 100 clear
xdotool key --clearmodifiers --delay 100 Return
#sleep 2.0
sleep 10.0
#xdotool type --clearmodifiers --delay 100 ls
#xdotool key --clearmodifiers --delay 100 Return
#sleep 2.0
xdotool type --clearmodifiers --delay 100 'vim movies.tsv'
xdotool key --clearmodifiers --delay 100 Return
sleep 1.5
xdotool type --clearmodifiers --delay 100 ":Select * where re.search('[0-9]', a1) is not None and int(a4) > 120 order by int(a3) desc"
sleep 3.0
xdotool key --clearmodifiers --delay 100 Return
sleep 1.0
xdotool type --clearmodifiers --delay 100 ":let g:rbql_meta_language='JavaScript'"
sleep 1.5
xdotool key --clearmodifiers --delay 100 Return
sleep 0.2
xdotool type --clearmodifiers --delay 100 ":Select top 5 a1, a5, 'const', (10 * 9 -6)/2  where a1.length > 8 && a5.indexOf('Drama') != -1"
sleep 3.0
xdotool key --clearmodifiers --delay 100 Return
sleep 2.0
xdotool type --clearmodifiers --delay 100 ":q"
sleep 1.0
xdotool key --clearmodifiers --delay 100 Return
sleep 0.8
