"==============================================================================
"
" Description: Rainbow CSV
" Authors: Dmitry Ignatovich, ...
"
"==============================================================================

func! s:TryLoadHighlighting()
    if rainbow_csv#is_rainbow_table()
        call rainbow_csv#regenerate_syntax(b:rainbow_csv_delim, b:rainbow_csv_policy)
    else
        call rainbow_csv#try_initialize_table()
    endif
endfunc


augroup RainbowAutodetectAuGrp
    autocmd!
    autocmd BufEnter * call s:TryLoadHighlighting()
augroup END

" FIXME treat all non-csv files as monocolumn
command! RainbowMonoColumn call rainbow_csv#manual_set('monocolumn')
command! RainbowDelim call rainbow_csv#manual_set('simple')
command! RainbowDelimQuoted call rainbow_csv#manual_set('quoted')
command! NoRainbowDelim call rainbow_csv#manual_disable()
command! RainbowNoDelim call rainbow_csv#manual_disable()
command! RbSelect call rainbow_csv#select_from_file()
command! RbRun call rainbow_csv#finish_query_editing()
command! -complete=file -nargs=1 RainbowSetHeader call rainbow_csv#set_header_manually(<f-args>)
command! -nargs=+ Select call rainbow_csv#run_select_cmd_query(<q-args>)
command! -nargs=+ Update call rainbow_csv#run_update_cmd_query(<q-args>)
command! -nargs=1 RainbowName call rainbow_csv#set_table_name_for_buffer(<q-args>)
