"==============================================================================
"  Description: rainbow csv
"==============================================================================

"TODO create explanatory youtube video


func! s:TryLoadHighlighting()
    if exists("b:current_syntax")
        return
    endif
    if exists("g:disable_rainbow_csv_autodetect")
        return
    endif
    if (!exists("b:rainbow_csv_delim"))
        call rainbow_csv#try_load()
    endif
endfunc

augroup RainbowAutodetectAuGrp
    autocmd!
    autocmd BufEnter * call s:TryLoadHighlighting()
augroup END

command! RainbowDelim call rainbow_csv#manual_load()
command! NoRainbowDelim call rainbow_csv#disable()
command! RainbowNoDelim call rainbow_csv#disable()
command! RbGetColumn call rainbow_csv#get_column()
command! RbSelect call rainbow_csv#select_mode()
command! RbRun call rainbow_csv#run_select()
command! RainbowSelect call rainbow_csv#select_mode()
command! RainbowRun call rainbow_csv#run_select()
command! -complete=file -nargs=1 RainbowSetHeader call rainbow_csv#set_header_manually(<f-args>)
