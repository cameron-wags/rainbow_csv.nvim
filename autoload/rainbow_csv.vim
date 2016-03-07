"==============================================================================
"  Description: rainbow csv
"               by Dmitry Ignatovich
"==============================================================================

let s:max_columns = exists('g:rcsv_max_columns') ? g:rcsv_max_columns : 30

func! s:lines_are_delimited(lines, delim)
    let fieldsNumber = len(split(a:lines[0], a:delim))
    if (fieldsNumber < 2 || fieldsNumber > s:max_columns)
        return 0
    endif
    for line in a:lines
        let nfields = len(split(line, a:delim)) 
        if (fieldsNumber != nfields)
            return 0
        endif
        let fieldsNumber = nfields
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
    if (!len(delim))
        let delim = s:auto_detect_delimiter(s:delimiters)
    endif
    let b:rainbow_csv_delim = delim
    if (!len(delim))
        return
    endif
    call rainbow_csv#generate_syntax(delim)
endfunc


func! rainbow_csv#generate_syntax(delim)
    if (len(s:pairs) < 2)
        return
    endif

    set filetype=csv

    for groupid in range(len(s:pairs))
        let match = 'column' . groupid
        let nextgroup = groupid + 1 < len(s:pairs) ? groupid + 1 : 0
        let cmd = 'sy match %s /%s[^%s]*/ nextgroup=column%d'
        exe printf(cmd, match, a:delim, a:delim, nextgroup)
        let cmd = 'hi %s ctermfg=%s guifg=%s'
        exe printf(cmd, match, s:pairs[groupid][0], s:pairs[groupid][1])
    endfor

    let cmd = 'sy match startcolumn /^[^%s]*/ nextgroup=column1'
    exe printf(cmd, a:delim)
    let cmd = 'hi startcolumn ctermfg=%s guifg=%s'
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
        return 'n/a (header not found)'
    endif
    let lines = readfile(headerName, '', 1)
    if (!len(lines))
        return 'n/a (empty header)'
    endif
    let line = lines[0]
    let names = split(line, b:rainbow_csv_delim)
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
    syntax clear
    let b:rainbow_csv_delim = ''
endfunc
