#!/usr/bin/env bash
#xdotool windowactivate 41943044 type --window 41943044 --clearmodifiers --delay 100 ls
xdotool windowactivate 41943044
xdotool type --clearmodifiers --delay 100 ls
xdotool key --clearmodifiers --delay 100 Return
xdotool type --clearmodifiers --delay 100 'vim movies.tsv'
xdotool key --clearmodifiers --delay 100 Return
sleep 1.5
xdotool type --clearmodifiers --delay 100 ':q'
xdotool key --clearmodifiers --delay 100 Return
