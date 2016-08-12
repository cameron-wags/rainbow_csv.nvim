"==============================================================================
"  Description: rainbow csv
"               by Dmitry Ignatovich
"==============================================================================


let s:max_columns = exists('g:rcsv_max_columns') ? g:rcsv_max_columns : 30


func! s:lines_are_delimited(lines, delim)
    let num_fields = len(split(a:lines[0], a:delim))
    if (num_fields < 2 || num_fields > s:max_columns)
        return 0
    endif
    for line in a:lines
        let nfields = len(split(line, a:delim)) 
        if (num_fields != nfields)
            return 0
        endif
    endfor
    return 1
endfunc

func! s:auto_detect_delimiter(delimiters)
    let lastLineNo = min([line("$"), 10])
    if (lastLineNo < 5)
        return ''
    endif
    let sampled_lines = []
    for linenum in range(1, lastLineNo)
        call add(sampled_lines, getline(linenum))
    endfor
    for delim in a:delimiters
        if (s:lines_are_delimited(sampled_lines, delim))
            return delim
        endif
    endfor
    return ''
endfunc


let s:pairs = [
    \ ['darkred',     'darkred'],
    \ ['darkblue',    'darkblue'],
    \ ['darkgreen',   'darkgreen'],
    \ ['darkmagenta', 'darkmagenta'],
    \ ['darkcyan',    'darkcyan'],
    \ ['red',         'red'],
    \ ['blue',        'blue'],
    \ ['green',       'green'],
    \ ['magenta',     'magenta'],
    \ ['NONE',        'NONE'],
    \ ]

let s:pairs = exists('g:rcsv_colorpairs') ? g:rcsv_colorpairs : s:pairs
let s:delimiters = ['	', ',']
let s:delimiters = exists('g:rcsv_delimiters') ? g:rcsv_delimiters : s:delimiters


func! rainbow_csv#columns_apply()
    if !exists("b:rb_parent_buf_no")
        echoerr "Not in column edit mode buffer"
        return
    endif
    
    let stratch_bfr_nr=bufnr('%')
    let lines = getline(1, '$')
    let convmap = []
    for lnum in range(len(lines))
        if lines[lnum][:5] != 'Column'
            continue
        endif
        let cid = str2nr(split(lines[lnum][6:], ' ')[0])
        call add(convmap, cid - 1)
    endfor

    1,$d
    call setline(1, "Processing...")
    redraw
    let prnt_buffer = b:rb_parent_buf_no
    execute "buffer " . prnt_buffer
    echomsg "Processing..."
    let delim = b:rainbow_csv_delim
    let num_fields = len(split(getline(1), delim))
    for mvv in convmap
        if mvv < 0 || mvv >= num_fields
            echoerr "Bad column specified: Column" . mvv
            return
        endif
    endfor
    let nlines = line('$')
    for lnum in range(1, nlines)
        let src_line = getline(lnum)
        let fields = split(src_line, delim)
        if len(fields) != num_fields
            echoerr "Wrong number of fields in line: " . lnum
            return
        endif
        let new_fields = []
        for mvv in convmap
            call add(new_fields, fields[mvv])
        endfor
        let new_line = join(new_fields, delim)
        call setline(lnum, new_line)
    endfor
    execute "bdelete " . stratch_bfr_nr
    silent! close
    execute "buffer " . prnt_buffer
    let b:in_col_edit_mode = 0
endfunc


func! s:read_column_names()
    let fname = expand("%:p")
    let headerName = fname . '.header'

    let setting_lines = s:read_settings()
    for line in setting_lines
        let fields = split(line, "\t")
        if fields[0] == fname && len(fields) >= 3
            let headerName = fields[2]
            break
        endif
    endfor

    if (!filereadable(headerName))
        return []
    endif
    let lines = readfile(headerName, '', 1)
    if (!len(lines))
        return []
    endif
    let line = lines[0]
    let names = split(line, b:rainbow_csv_delim)
    return names
endfunc



func! rainbow_csv#columns_edit()
    if !exists("b:rainbow_csv_delim") || !len(b:rainbow_csv_delim)
        echoerr "Error: no delim specified"
        return
    endif
    let delim = b:rainbow_csv_delim

    if exists("b:in_col_edit_mode") && b:in_col_edit_mode == 1
        echoerr "Already in col edit mode"
        "TODO improve this situation handling. go to the col edit buffer instead of error
        return
    endif
    let b:in_col_edit_mode = 1

    let lines = getline(1, 10)
    if !len(lines)
        echoerr "Error: no lines in file"
        return
    endif
    let num_fields = len(split(lines[0], delim))
    let custom_names = s:read_column_names()
    let new_rows = []
    for nf in range(1, num_fields)
        let custom_name = ''
        if num_fields == len(custom_names)
            let custom_name = ' (' . custom_names[nf - 1] . ')'
        endif
        call add(new_rows, 'Column' . nf . custom_name . ' [')
    endfor

    let mxf = 4
    let partial = 1
    if len(lines) <= 6
        let mxf = len(lines)
        let partial = 0
    endif

    for lnum in range(mxf)
        let line = lines[lnum]
        let fields = split(line, delim)
        if len(fields) != num_fields
            echoerr "Wrong number of fields in line " . (lnum + 1)
            return
        endif
        for nf in range(num_fields)
            if lnum > 0
                let new_rows[nf] = new_rows[nf] . ', '
            endif
            let new_rows[nf] = new_rows[nf] . fields[nf]
        endfor
    endfor

    for nf in range(num_fields)
        if partial
            let new_rows[nf] = new_rows[nf] . ', ... '
        endif
        let new_rows[nf] = new_rows[nf] . ']'
    endfor

    let parent_buf_num = bufnr('%')

    below new
    let b:rb_parent_buf_no=parent_buf_num
    setlocal buftype=nofile
    setlocal noswapfile
    setlocal nowrap
    file RainbowColumnsEditBuffer

    for nf in range(num_fields)
        call setline(nf + 1, new_rows[nf])
    endfor
    setlocal cursorline
    call rainbow_csv#generate_transposed_syntax(num_fields)
    let help_msg = '"Delete/copy/swap any number of "ColumnX ..." lines. Execute ":RainbowColumnsApply" to apply your changes'
    call setline(num_fields + 1, "")
    call setline(num_fields + 2, "")
    call setline(num_fields + 3, help_msg)
    call cursor(num_fields + 3, 1)
endfunc


func! s:read_settings()
    let lines = []
    let rainbowSettingsPath = $HOME . '/.rainbow_csv_files'
    if (filereadable(rainbowSettingsPath))
        let lines = readfile(rainbowSettingsPath)
    endif
    return lines
endfunc


func! s:write_settings(lines)
    "TODO make setting path configurable
    let rainbowSettingsPath = $HOME . '/.rainbow_csv_files'
    call writefile(a:lines, rainbowSettingsPath)
endfunc


func! s:try_load_from_settings()
    let fname = expand("%:p")
    let lines = s:read_settings()
    for line in lines
        let fields = split(line, "\t")
        if fields[0] == fname
            let delim = fields[1]
            if delim == 'TAB'
                let delim = "\t"
            endif
            return delim
        endif
    endfor
    return ''
endfunc


func! rainbow_csv#try_load()
    let delim = s:try_load_from_settings() 
    if delim == 'DISABLED'
        return
    endif
    if (!len(delim))
        let delim = s:auto_detect_delimiter(s:delimiters)
    endif
    let b:rainbow_csv_delim = delim
    if (!len(delim))
        return
    endif
    set filetype=csv
    call rainbow_csv#generate_syntax(delim)
endfunc


func! rainbow_csv#generate_transposed_syntax(nlines)
    let npairs = len(s:pairs)
    if (npairs < 2)
        return
    endif

    for lnum in range(1, a:nlines)
        let cmd = 'highlight line%d ctermfg=%s guifg=%s'
        exe printf(cmd, lnum, s:pairs[(lnum - 1) % npairs][0], s:pairs[(lnum - 1) % npairs][1])
        let cmd = 'syntax match line%d /Column%d .*/'
        exe printf(cmd, lnum, lnum)
    endfor
    highlight RbCmd ctermbg=blue guibg=blue
    syntax keyword RbCmd RainbowColumnsApply contained
    syntax match Comment "^\".*" contains=RbCmd
endfunc

func! rainbow_csv#generate_syntax(delim)
    if (len(s:pairs) < 2)
        return
    endif

    for groupid in range(len(s:pairs))
        let match = 'column' . groupid
        let nextgroup = groupid + 1 < len(s:pairs) ? groupid + 1 : 0
        let cmd = 'syntax match %s /%s[^%s]*/ nextgroup=column%d'
        exe printf(cmd, match, a:delim, a:delim, nextgroup)
        let cmd = 'highlight %s ctermfg=%s guifg=%s'
        exe printf(cmd, match, s:pairs[groupid][0], s:pairs[groupid][1])
    endfor

    let cmd = 'syntax match startcolumn /^[^%s]*/ nextgroup=column1'
    exe printf(cmd, a:delim)
    let cmd = 'highlight startcolumn ctermfg=%s guifg=%s'
    exe printf(cmd, s:pairs[0][0], s:pairs[0][1])
endfunc

func! s:make_entry(delim)
    let fname = expand("%:p")
    let delim = a:delim
    if delim == "\t"
        let delim = 'TAB'
    endif
    let entry = fname . "\t" . delim
    return entry
endfunc

func! s:save_file_delim(delim)
    let entry = s:make_entry(a:delim)
    let lines = s:read_settings()
    let lines = [entry] + lines
    let lines = lines[:50]
    call s:write_settings(lines)
endfunc


func! rainbow_csv#manual_load()
    let delim = getline('.')[col('.') - 1]  
    let b:rainbow_csv_delim = delim
    call rainbow_csv#generate_syntax(delim)
    call s:save_file_delim(delim)
endfunc


func! rainbow_csv#set_header_manually(fname)
    let delim = b:rainbow_csv_delim
    if (!len(delim))
        echoerr "Error: no delim specified"
        return
    endif
    let entry = s:make_entry(delim)
    let entry = entry . "\t" . a:fname
    let lines = s:read_settings()
    let lines = [entry] + lines
    let lines = lines[:50]
    call s:write_settings(lines)
endfunc


func! s:read_column_name(colNo, numCols)
    let names = s:read_column_names()
    if !len(names)
        return 'n/a (header not found/empty)'
    endif

    if (a:colNo >= len(names))
        return 'n/a (no field in header)'
    endif
    if (a:numCols != len(names))
        return names[a:colNo] . ' (Warning: number of columns in header and csv file mismatch)'
    endif
    return names[a:colNo]
endfunc

func! rainbow_csv#get_column()
    let line = getline('.')
    let pos = col('.') - 1
    let delim = b:rainbow_csv_delim
    if (!len(delim))
        echoerr "Error: no delim specified"
        return
    endif

    let colNo = len(split(line[0:pos], delim))
    let numCols = len(split(line, delim))

    let colName = s:read_column_name(colNo - 1, numCols)
    echomsg 'Col: [' . colNo . '], Name: [' . colName . ']'
endfunc


func! rainbow_csv#disable()
    syntax clear startcolumn
    for groupid in range(len(s:pairs))
        let match = 'column' . groupid
        exe "syntax clear " . match
    endfor

    let b:rainbow_csv_delim = ''
    call s:save_file_delim('DISABLED')
endfunc
