"==============================================================================
"
" Description: rainbow csv
" Authors: Dmitry Ignatovich, ...
"
"
"==============================================================================

func! s:TryLoadHighlighting()
    if !exists("b:current_syntax") && !exists("g:disable_rainbow_csv_autodetect") && !exists("b:rainbow_csv_delim")
        call rainbow_csv#load_from_settings_or_autodetect()
    elseif exists("b:rainbow_csv_delim")
        call rainbow_csv#regenerate_syntax(b:rainbow_csv_delim, b:rainbow_csv_policy)
    endif
endfunc


augroup RainbowAutodetectAuGrp
    autocmd!
    autocmd BufEnter * call s:TryLoadHighlighting()
augroup END

command! RainbowMonoColumn call rainbow_csv#manual_set('monocolumn')
command! RainbowDelim call rainbow_csv#manual_set('simple')
command! RainbowDelimQuoted call rainbow_csv#manual_set('quoted')
command! NoRainbowDelim call rainbow_csv#manual_disable()
command! RainbowNoDelim call rainbow_csv#manual_disable()
command! RbGetColumn call rainbow_csv#get_column()
command! RbSelect call rainbow_csv#select_from_file()
command! RbRun call rainbow_csv#finish_query_editing()
command! -complete=file -nargs=1 RainbowSetHeader call rainbow_csv#set_header_manually(<f-args>)
command! -complete=file -nargs=1 RbSaveAndSwap call rainbow_csv#save_and_swap(<f-args>)
command! -nargs=+ Select call rainbow_csv#run_select_cmd_query(<q-args>)
command! -nargs=+ Update call rainbow_csv#run_update_cmd_query(<q-args>)
command! -nargs=1 RainbowName call rainbow_csv#set_table_name_for_buffer(<q-args>)
