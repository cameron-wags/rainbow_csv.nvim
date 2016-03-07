"==============================================================================
"  Description: rainbow csv
"               by Dmitry Ignatovich
"==============================================================================

func! s:TryLoadHighlighting()
    "caching
    if exists("b:rainbow_csv_delim") && len(b:rainbow_csv_delim)
        call rainbow_csv#generate_syntax(b:rainbow_csv_delim)
        return
    endif
    if exists("g:disable_rainbow_csv_autodetect")
        return
    endif
    if exists("b:current_syntax")
        return
    endif
    if (!exists("b:rainbow_csv_delim"))
        call rainbow_csv#try_load()
    endif
endfunc

autocmd BufEnter * call s:TryLoadHighlighting()

command RainbowDelim call rainbow_csv#manual_load()
command NoRainbowDelim call rainbow_csv#disable()
command RainbowNoDelim call rainbow_csv#disable()
command RainbowGetColumn call rainbow_csv#get_column()
command -complete=file -nargs=1 RainbowSetHeader call rainbow_csv#set_header_manually(<f-args>)

if !exists('g:rcsv_map_keys')
    let g:rcsv_map_keys = 1
endif

if g:rcsv_map_keys
    execute "autocmd FileType csv" "nnoremap <buffer>" "<Leader>d"  ":RainbowGetColumn<CR>"
endif

