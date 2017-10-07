"==============================================================================
"  Description: rainbow csv
"==============================================================================


func! s:TryLoadHighlighting()
    if !exists("b:current_syntax") && !exists("g:disable_rainbow_csv_autodetect") && !exists("b:rainbow_csv_delim")
        call rainbow_csv#run_autodetection()
    elseif exists("b:rainbow_csv_delim")
        call rainbow_csv#regenerate_syntax(b:rainbow_csv_delim)
    endif
endfunc


augroup RainbowAutodetectAuGrp
    autocmd!
    autocmd BufEnter * call s:TryLoadHighlighting()
augroup END

command! RainbowDelim call rainbow_csv#manual_load()
command! NoRainbowDelim call rainbow_csv#manual_disable()
command! RainbowNoDelim call rainbow_csv#manual_disable()
command! RbGetColumn call rainbow_csv#get_column()
command! RbSelect call rainbow_csv#select_mode()
command! RainbowSelect call rainbow_csv#select_mode()
command! RbRun call rainbow_csv#select_from_file()
command! RainbowRun call rainbow_csv#select_from_file()
command! -complete=file -nargs=1 RainbowSetHeader call rainbow_csv#set_header_manually(<f-args>)
command! -complete=file -nargs=1 RbSaveAndSwap call rainbow_csv#save_and_swap(<f-args>)
command! -nargs=+ Select call rainbow_csv#run_cmd_query('select', <f-args>)
command! -nargs=+ Update call rainbow_csv#run_cmd_query('update', <f-args>)
