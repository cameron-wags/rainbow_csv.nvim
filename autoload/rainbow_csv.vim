"==============================================================================
"
" Description: Rainbow CSV
" Authors: Dmitry Ignatovich, ...
"
"==============================================================================

let s:max_columns = exists('g:rcsv_max_columns') ? g:rcsv_max_columns : 30
let s:rb_storage_dir = $HOME . '/.rainbow_csv_storage'
let s:table_names_settings = $HOME . '/.rbql_table_names'
let s:rainbow_table_index = $HOME . '/.rbql_table_index'

let s:script_folder_path = expand('<sfile>:p:h:h')
let s:python_env_initialized = 0
let s:js_env_initialized = 0
let s:system_python_interpreter = ''

let s:magic_chars = '^*$.~/[]\'

let s:named_syntax_map = {'csv': [',', 'quoted'], 'csv_semicolon': [';', 'quoted'], 'tsv': ["\t", 'simple'], 'csv_pipe': ['|', 'simple'], 'csv_whitespace': [" ", 'whitespace'], 'rfc_csv': [',', 'quoted_rfc'], 'rfc_semicolon': [';', 'quoted_rfc']}

let s:delimiters = exists('g:rcsv_delimiters') ? g:rcsv_delimiters : ["\t", ",", ";", "|"]



" XXX Use :syntax command to list all syntax groups


" TODO fix update -> Update switch it also occures with this `:echo "update "` -> `:echo "Update "` scenario. but only with csv files!
" It might be possible  to modify set_statusline_columns() to read current
" command line text and if it starts with "select" indeed, then replace
" (return special flag) otherwise do not replace by ternary expression

" TODO implement select -> Select switch for monocolumn files
"
" TODO support comment prefixes

" TODO implement csv_lint for "rfc_csv" dialect


func! s:init_groups_from_links()
    let link_groups = ['String', 'Comment', 'NONE', 'Special', 'Identifier', 'Type', 'Question', 'CursorLineNr', 'ModeMsg', 'Title']
    for gi in range(len(link_groups))
        let cmd = 'highlight link status_color%d %s'
        exe printf(cmd, gi, link_groups[gi])
        let cmd = 'highlight link rbql_color%d %s'
        exe printf(cmd, gi, link_groups[gi])
        let cmd = 'highlight link column%d %s'
        exe printf(cmd, gi, link_groups[gi])
        let cmd = 'highlight link escaped_column%d %s'
        exe printf(cmd, gi, link_groups[gi])
    endfor
    let s:num_groups = len(link_groups)
endfunc


func! s:has_custom_colors()
    return exists('g:rcsv_colorpairs') && len(g:rcsv_colorpairs) > 1
endfunc


func! s:init_groups_from_colors()
    let pairs = [['red', 'red'], ['green', 'green'], ['blue', 'blue'], ['magenta', 'magenta'], ['NONE', 'NONE'], ['darkred', 'darkred'], ['darkblue', 'darkblue'], ['darkgreen', 'darkgreen'], ['darkmagenta', 'darkmagenta'], ['darkcyan', 'darkcyan']]
    if s:has_custom_colors()
        let pairs = g:rcsv_colorpairs
    endif
    for gi in range(len(pairs))
        let cmd = 'highlight status_color%d ctermfg=%s guifg=%s ctermbg=black guibg=black'
        exe printf(cmd, gi, pairs[gi][0], pairs[gi][1])
        let cmd = 'highlight rbql_color%d ctermfg=%s guifg=%s'
        exe printf(cmd, gi, pairs[gi][0], pairs[gi][1])
        let cmd = 'highlight column%d ctermfg=%s guifg=%s'
        exe printf(cmd, gi, pairs[gi][0], pairs[gi][1])
        let cmd = 'highlight escaped_column%d ctermfg=%s guifg=%s'
        exe printf(cmd, gi, pairs[gi][0], pairs[gi][1])
    endfor
    let s:num_groups = len(pairs)
endfunc


func! s:init_rb_color_groups()
    if !exists("g:syntax_on") || s:has_custom_colors()
        call s:init_groups_from_colors()
    else
        call s:init_groups_from_links()
    endif
    highlight link escaped_startcolumn column0

    highlight RbCmd ctermbg=blue guibg=blue
endfunc


call s:init_rb_color_groups()


func! s:try_read_lines(src_path)
    let lines = []
    if (filereadable(a:src_path))
        let lines = readfile(a:src_path)
    endif
    return lines
endfunc


func! s:try_read_index(src_path)
    let lines = s:try_read_lines(a:src_path)
    let records = []
    for line in lines
        let fields = split(line, "\t", 1)
        call add(records, fields)
    endfor
    return records
endfunc


func! s:write_index(records, dst_path)
    let lines = []
    for record in a:records
        let new_line = join(record, "\t")
        call add(lines, new_line)
    endfor
    call writefile(lines, a:dst_path)
endfunc


func! s:update_records(records, key, new_record)
    let old_idx = -1
    for ir in range(len(a:records))
        let record = a:records[ir]
        if len(record) && record[0] == a:key
            let old_idx = ir
        endif
    endfor
    if old_idx != -1
        call remove(a:records, old_idx)
    endif
    call add(a:records, a:new_record)
    return a:records
endfunc


func! s:index_encode_delim(delim)
    " We need this ugly function to keep backward-compatibility with old single-char delim format
    if a:delim == "\t"
        return 'TAB'
    endif
    if len(a:delim) > 1
        let result = substitute(a:delim, '\\', '\\\\', "g")
        let result = substitute(result, '\t', '\\t', "g")
        return 'multichar:' . result
    endif
    return a:delim
endfunc


func! s:index_decode_delim(encoded_delim)
    if a:encoded_delim == "TAB"
        return "\t"
    endif
    if stridx(a:encoded_delim, 'multichar:') == 0
        let result = strpart(a:encoded_delim, len('multichar:'))
        let result = substitute(result, '\\t', '\t', 'g')
        let result = substitute(result, '\\\\', '\\', 'g')
        return result
    endif
    return a:encoded_delim
endfunc


func! s:update_table_record(table_path, delim, policy)
    if !len(a:table_path)
        " For tmp buffers e.g. `cat table.csv | vim -`
        return
    endif
    let encoded_delim = s:index_encode_delim(a:delim)
    let new_record = [a:table_path, encoded_delim, a:policy]
    let records = s:try_read_index(s:rainbow_table_index)
    let records = s:update_records(records, a:table_path, new_record)
    if len(records) > 100
        call remove(records, 0)
    endif
    call s:write_index(records, s:rainbow_table_index)
endfunc


func! s:get_table_record(table_path)
    if !len(a:table_path)
        return []
    endif
    let records = s:try_read_index(s:rainbow_table_index)
    for record in records
        if len(record) >= 3 && record[0] == a:table_path
            let delim = s:index_decode_delim(record[1])
            let policy = record[2]
            return [delim, policy]
        endif
    endfor
    return []
endfunc


func! s:string_to_hex(src)
    let result = ''
    for nt in range(len(a:src))
        let result .= printf("%x", char2nr(a:src[nt]))
    endfor
    return result
endfunc


func! s:hex_to_string(src)
    let result = ''
    let nt = 0
    while nt < len(a:src)
        let result .= nr2char(str2nr(strpart(a:src, nt, 2), 16))
        let nt += 2
    endwhile
    return result
endfunc


func! rainbow_csv#dialect_to_ft(delim, policy)
    for [ft, delim_policy] in items(s:named_syntax_map)
        if a:delim == delim_policy[0] && a:policy == delim_policy[1]
            return ft
        endif
    endfor
    return join(['rcsv', s:string_to_hex(a:delim), a:policy], '_')
endfunc


func! rainbow_csv#ft_to_dialect(ft_val)
    if has_key(s:named_syntax_map, a:ft_val)
        return s:named_syntax_map[a:ft_val]
    endif
    let ft_parts = split(a:ft_val, '_')
    if len(ft_parts) != 3 || ft_parts[0] != 'rcsv'
        return ['', 'monocolumn']
    endif
    return [s:hex_to_string(ft_parts[1]), ft_parts[2]]
endfunc


func! rainbow_csv#generate_named_dialects()
    for [ft, delim_policy] in items(s:named_syntax_map)
        call rainbow_csv#ensure_syntax_exists(ft, delim_policy[0], delim_policy[1])
    endfor
endfunc


func! rainbow_csv#get_current_dialect()
    let current_ft = &ft
    return rainbow_csv#ft_to_dialect(current_ft)
endfunc


func! rainbow_csv#is_rainbow_table()
    let [delim, policy] = rainbow_csv#get_current_dialect()
    return policy != 'monocolumn'
endfunc


func! s:get_meta_language()
    let lang_lw = 'python'
    if exists("g:rbql_meta_language")
        let lang_lw = tolower(g:rbql_meta_language)
    endif
    if exists("g:rbql_backend_language")
        let lang_lw = tolower(g:rbql_backend_language)
    endif
    if lang_lw == 'javascript'
        let lang_lw = 'js'
    endif
    return lang_lw
endfunc


func! s:has_python_27()
    if !has("python")
        return 0
    endif
    py import sys
    if pyeval('sys.version_info[1]') < 7
        return 0
    endif
    return 1
endfunc


func! s:read_virtual_header(delim, policy)
    let table_path = resolve(expand("%:p"))
    let headerName = table_path . '.header'
    if (!filereadable(headerName))
        return []
    endif
    let lines = readfile(headerName, '', 1)
    if (!len(lines))
        return []
    endif
    let line = lines[0]
    let names = []
    if a:policy == 'monocolumn'
        let names = [line]
    else
        let regex_delim = escape(a:delim, s:magic_chars)
        let names = split(line, regex_delim)
    endif
    return names
endfunc


func! rainbow_csv#dbg_set_system_python_interpreter(interpreter)
    let s:system_python_interpreter = a:interpreter
endfunction


func! rainbow_csv#find_python_interpreter()
    " Checking `python3` first, because `python` could be theorethically linked to python 2.6
    let py3_version = tolower(system('python3 --version'))
    if (v:shell_error == 0 && match(py3_version, 'python 3\.') == 0)
        let s:system_python_interpreter = 'python3'
        return s:system_python_interpreter
    endif
    let py_version = tolower(system('python --version'))
    if (v:shell_error == 0 && (match(py_version, 'python 2\.7') == 0 || match(py_version, 'python 3\.') == 0))
        let s:system_python_interpreter = 'python'
        return s:system_python_interpreter
    endif
    let s:system_python_interpreter = ''
    return s:system_python_interpreter
endfunc


function! s:py_source_escape(src)
    " Strings in 'substitute' must follow esoteric rules, see `:help substitute()`
    let dst = substitute(a:src, '\\', '\\\\', "g")
    let dst = substitute(dst, '\t', '\\t', "g")
    let dst = substitute(dst, '"', '\\"', "g")
    return dst
endfunc


function! s:char_class_escape(src)
    if a:src == ']'
        return '\]'
    endif
    if a:src == '\'
        return '\\'
    endif
    return a:src
endfunc


function! s:test_coverage()
    if !exists("g:rbql_dbg_test_coverage")
        return 0
    endif
    return reltime()[1] % 2
endfunc


function! s:EnsureJavaScriptInitialization()
    if (s:js_env_initialized)
        return 1
    endif
    let js_version = tolower(system('node --version'))
    if (v:shell_error != 0)
        return 0
    endif
    let s:js_env_initialized = 1
    return 1
endfunction


function! s:EnsurePythonInitialization()
    if (s:python_env_initialized)
        return 1
    endif
    let py_home_dir = s:script_folder_path . '/rbql_core'
    let py_home_dir = s:py_source_escape(py_home_dir)
    if has("python3") && !s:test_coverage()
        py3 import sys
        py3 import vim
        exe 'python3 sys.path.insert(0, "' . py_home_dir . '")'
        py3 import vim_rbql
    elseif s:has_python_27() && !s:test_coverage()
        py import sys
        py import vim
        exe 'python sys.path.insert(0, "' . py_home_dir . '")'
        py import vim_rbql
    else
        call rainbow_csv#find_python_interpreter()
        if s:system_python_interpreter == ""
            return 0
        endif
    endif
    let s:python_env_initialized = 1
    return 1
endfunction


func! s:ensure_storage_exists()
    if !isdirectory(s:rb_storage_dir)
        call mkdir(s:rb_storage_dir, "p")
    endif
endfunc


func! rainbow_csv#rstrip(line)
    let result = a:line
    if len(result) && result[len(result) - 1] == "\n"
        let result = strpart(result, 0, len(result) - 1)
    endif
    if len(result) && result[len(result) - 1] == "\r"
        let result = strpart(result, 0, len(result) - 1)
    endif
    return result
endfunc


function! rainbow_csv#strip_spaces(input_string)
    return substitute(a:input_string, '^ *\(.\{-}\) *$', '\1', '')
endfunction


func! rainbow_csv#unescape_quoted_fields(src)
    let res = a:src
    for nt in range(len(res))
        let res[nt] = rainbow_csv#strip_spaces(res[nt])
        if len(res[nt]) >= 2 && res[nt][0] == '"'
            let res[nt] = strpart(res[nt], 1, len(res[nt]) - 2)
        endif
        let res[nt] = substitute(res[nt], '""', '"', 'g')
    endfor
    return res
endfunc


func! rainbow_csv#preserving_quoted_split(line, delim)
    let src = a:line
    if stridx(src, '"') == -1
        " Optimization for majority of lines
        let regex_delim = escape(a:delim, s:magic_chars)
        return [split(src, regex_delim, 1), 0]
    endif
    let result = []
    let cidx = 0
    let has_warning = 0
    while cidx < len(src)
        let uidx = cidx
        while uidx < len(src) && src[uidx] == ' '
            let uidx += 1
        endwhile
        if src[uidx] == '"'
            let uidx += 1
            while 1
                let uidx = stridx(src, '"', uidx)
                if uidx == -1
                    call add(result, strpart(src, cidx))
                    return [result, 1]
                endif
                let uidx += 1
                if uidx < len(src) && src[uidx] == '"'
                    let uidx += 1
                    continue
                endif
                while uidx < len(src) && src[uidx] == ' '
                    let uidx += 1
                endwhile
                if uidx >= len(src) || src[uidx] == a:delim
                    call add(result, strpart(src, cidx, uidx - cidx))
                    let cidx = uidx + 1
                    break
                endif
                let has_warning = 1
            endwhile
        else
            let uidx = stridx(src, a:delim, uidx)
            if uidx == -1
                let uidx = len(src)
            endif
            let field = strpart(src, cidx, uidx - cidx)
            let cidx = uidx + 1
            call add(result, field)
            let has_warning = has_warning || stridx(field, '"') != -1
        endif
    endwhile
    if src[len(src) - 1] == a:delim
        call add(result, '')
    endif
    return [result, has_warning]
endfunc


func! rainbow_csv#quoted_split(line, delim)
    let quoted_fields = rainbow_csv#preserving_quoted_split(a:line, a:delim)[0]
    let clean_fields = rainbow_csv#unescape_quoted_fields(quoted_fields)
    return clean_fields
endfunc


func! rainbow_csv#whitespace_split(line, preserve_whitespaces)
    let result = []
    let cidx = 0
    while cidx < len(a:line)
        let uidx = cidx
        while uidx < len(a:line) && a:line[uidx] == ' '
            let uidx += 1
        endwhile
        let startidx = uidx
        while uidx < len(a:line) && a:line[uidx] != ' '
            let uidx += 1
        endwhile
        if uidx == startidx
            if a:preserve_whitespaces && len(result)
                let startidx = cidx
                let result[len(result) - 1] = result[len(result) - 1] . strpart(a:line, startidx, uidx - startidx)
            endif
            break
        endif
        if a:preserve_whitespaces
            let startidx = len(result) ? cidx + 1 : cidx
        endif
        let field = strpart(a:line, startidx, uidx - startidx)
        let cidx = uidx
        call add(result, field)
    endwhile
    if len(result) == 0
        if a:preserve_whitespaces
            call add(result, a:line)
        else
            call add(result, '')
        endif
    endif
    return result
endfunc


func! rainbow_csv#smart_split(line, delim, policy)
    let stripped = rainbow_csv#rstrip(a:line)
    if a:policy == 'monocolumn'
        return [stripped]
    elseif a:policy == 'quoted' || a:policy == 'quoted_rfc'
        return rainbow_csv#quoted_split(stripped, a:delim)
    elseif a:policy == 'simple'
        let regex_delim = escape(a:delim, s:magic_chars)
        return split(stripped, regex_delim, 1)
    elseif a:policy == 'whitespace'
        return rainbow_csv#whitespace_split(a:line, 0)
    else
        echoerr 'bad delim policy'
    endif
endfunc


func! rainbow_csv#preserving_smart_split(line, delim, policy)
    let stripped = rainbow_csv#rstrip(a:line)
    if a:policy == 'monocolumn'
        return [[stripped], 0]
    elseif a:policy == 'quoted' || a:policy == 'quoted_rfc'
        return rainbow_csv#preserving_quoted_split(stripped, a:delim)
    elseif a:policy == 'simple'
        let regex_delim = escape(a:delim, s:magic_chars)
        return [split(stripped, regex_delim, 1), 0]
    elseif a:policy == 'whitespace'
        return [rainbow_csv#whitespace_split(a:line, 1), 0]
    else
        echoerr 'bad delim policy'
    endif
endfunc


func! rainbow_csv#csv_lint()
    let [delim, policy] = rainbow_csv#get_current_dialect()
    if policy == 'monocolumn'
        echoerr "CSVLint is available only for highlighted CSV files"
        return
    endif
    if policy == 'rfc_csv'
        " TODO implement
        echoerr "CSVLint is not implemented yet for rfc_csv"
        return
    endif
    let lastLineNo = line("$")
    let num_fields = 0
    for linenum in range(1, lastLineNo)
        let line = getline(linenum)
        let [fields, has_warning] = rainbow_csv#preserving_smart_split(line, delim, policy)
        if has_warning
            echoerr printf("Line %s has formatting error: double quote chars are not consistent", linenum)
            return
        endif
        let num_fields_cur = len(fields)
        if !num_fields
            let num_fields = num_fields_cur
        endif
        if (num_fields != num_fields_cur)
            echoerr printf("Number of fields is not consistent: e.g. line 1 has %s fields, and line %s has %s fields", num_fields, linenum, num_fields_cur)
            return
        endif
    endfor
    echomsg "CSVLint: OK"
endfunc


func! s:calc_column_sizes(delim, policy)
    let result = []
    let lastLineNo = line("$")
    for linenum in range(1, lastLineNo)
        let line = getline(linenum)
        let [fields, has_warning] = rainbow_csv#preserving_smart_split(line, a:delim, a:policy)
        if has_warning
            return [result, linenum]
        endif
        for fnum in range(len(fields))
            let field = rainbow_csv#strip_spaces(fields[fnum])
            if len(result) <= fnum
                call add(result, 0)
            endif
            let result[fnum] = max([result[fnum], strdisplaywidth(field)])
        endfor
    endfor
    return [result, 0]
endfunc


func! rainbow_csv#csv_align()
    let [delim, policy] = rainbow_csv#get_current_dialect()
    if policy == 'monocolumn'
        echoerr "RainbowAlign is available only for highlighted CSV files"
        return
    endif
    if policy == 'rfc_csv'
        echoerr 'RainbowAlign not available for "rfc_csv" filetypes, consider using "csv" instead'
        return
    endif
    let [column_sizes, first_failed_line] = s:calc_column_sizes(delim, policy)
    if first_failed_line != 0
        echoerr 'Unable to allign: Inconsistent double quotes at line ' . first_failed_line
        return
    endif
    let lastLineNo = line("$")
    let has_edit = 0
    for linenum in range(1, lastLineNo)
        let has_line_edit = 0
        let line = getline(linenum)
        let fields = rainbow_csv#preserving_smart_split(line, delim, policy)[0]
        for fnum in range(len(fields))
            if fnum >= len(column_sizes)
                break " Should never happen
            endif
            let field = rainbow_csv#strip_spaces(fields[fnum])
            let delta_len = column_sizes[fnum] - strdisplaywidth(field)
            if delta_len >= 0
                let field = field . repeat(' ', delta_len + 1)
            endif
            if fields[fnum] != field
                let fields[fnum] = field
                let has_line_edit = 1
            endif
        endfor
        if has_line_edit
            let updated_line = join(fields, delim)
            call setline(linenum, updated_line)
            let has_edit = 1
        endif
    endfor
    if !has_edit
        echoerr "File is already aligned"
    endif
endfunc


func! rainbow_csv#csv_shrink()
    let [delim, policy] = rainbow_csv#get_current_dialect()
    if policy == 'monocolumn'
        echoerr "RainbowShrink is available only for highlighted CSV files"
        return
    endif
    if policy == 'rfc_csv'
        echoerr 'RainbowShrink not available for "rfc_csv" filetypes, consider using "csv" instead'
        return
    endif
    let lastLineNo = line("$")
    let has_edit = 0
    for linenum in range(1, lastLineNo)
        let has_line_edit = 0
        let line = getline(linenum)
        let [fields, has_warning] = rainbow_csv#preserving_smart_split(line, delim, policy)
        if has_warning
            echoerr 'Unable to shrink: Inconsistent double quotes at line ' . linenum
            return
        endif
        for fnum in range(len(fields))
            let field = rainbow_csv#strip_spaces(fields[fnum])
            if fields[fnum] != field
                let fields[fnum] = field
                let has_line_edit = 1
            endif
        endfor
        if has_line_edit
            let updated_line = join(fields, delim)
            call setline(linenum, updated_line)
            let has_edit = 1
        endif
    endfor
    if !has_edit
        echoerr "File is already shrinked"
    endif
endfunc


func! rainbow_csv#get_csv_header(delim, policy)
    if exists("b:cached_virtual_header") && len(b:cached_virtual_header)
        return b:cached_virtual_header
    endif
    return rainbow_csv#smart_split(getline(1), a:delim, a:policy)
endfunc


func! s:get_col_num_single_line(fields, delim, offset)
    let col_num = 0
    let kb_pos = col('.')
    let cpos = a:offset + len(a:fields[col_num]) + len(a:delim)
    while kb_pos > cpos && col_num + 1 < len(a:fields)
        let col_num += 1
        let cpos += len(a:fields[col_num]) + len(a:delim)
    endwhile
    return col_num
endfunc


func s:do_get_col_num_rfc_lines(cur_line, delim, start_line, end_line, expected_num_fields)
    let record_lines = getline(a:start_line, a:end_line)
    let record_str = join(record_lines, "\n")
    let [fields, has_warning] = rainbow_csv#preserving_smart_split(record_str, a:delim, 'quoted_rfc')
    if has_warning || len(fields) != a:expected_num_fields
        return []
    endif
    let cursor_line_offset = a:cur_line - a:start_line
    let current_line_offset = 0
    let col_num = 0
    while col_num < len(fields)
        let current_line_offset += len(split(fields[col_num], "\n", 1)) - 1
        if current_line_offset >= cursor_line_offset
            break
        endif
        let col_num += 1
    endwhile
    if current_line_offset > cursor_line_offset
        return [fields, col_num]
    endif
    if current_line_offset < cursor_line_offset
        " Should never happen
        return []
    endif
    let length_of_previous_field_segment_on_cursor_line = 0
    if current_line_offset > 0
        let length_of_previous_field_segment_on_cursor_line = len(split(fields[col_num], "\n", 1)[-1]) + len(a:delim)
        if col('.') <= length_of_previous_field_segment_on_cursor_line
            return [fields, col_num]
        else
            let col_num += 1
        endif
    endif
    let col_num = col_num + s:get_col_num_single_line(fields[col_num:], a:delim, length_of_previous_field_segment_on_cursor_line)
    return [fields, col_num]
endfunc


func s:find_unbalanced_lines_around(cur_line)
    let start_line = -1
    let end_line = -1
    let multiline_search_range = exists('g:multiline_search_range') ? g:multiline_search_range : 10
    let lnmb = max([1, a:cur_line - multiline_search_range])
    let lnme = min([line('$'), a:cur_line + multiline_search_range])
    while lnmb < lnme
        if len(split(getline(lnmb), '"', 1)) % 2 == 0
            if lnmb < a:cur_line
                let start_line = lnmb
            endif
            if lnmb > a:cur_line
                let end_line = lnmb
                break
            endif
        endif
        let lnmb += 1
    endwhile
    return [start_line, end_line]
endfunc


func s:get_col_num_rfc_basic_even_case(line, delim, expected_num_fields)
    let [fields, has_warning] = rainbow_csv#preserving_smart_split(a:line, a:delim, 'quoted_rfc')
    if !has_warning && len(fields) == a:expected_num_fields
        let col_num = s:get_col_num_single_line(fields, a:delim, 0)
        return [fields, col_num]
    endif
    return []
endfunc


func s:get_col_num_rfc_lines(line, delim, expected_num_fields)
    let cur_line = line('.')
    let [start_line, end_line] = s:find_unbalanced_lines_around(cur_line)
    let even_number_of_dquotes = len(split(a:line, '"', 1)) % 2 == 1
    if even_number_of_dquotes
        if start_line != -1 && end_line != -1
            let report = s:do_get_col_num_rfc_lines(cur_line, a:delim, start_line, end_line, a:expected_num_fields)
            if len(report)
                return report
            endif
        endif
        return s:get_col_num_rfc_basic_even_case(a:line, a:delim, a:expected_num_fields)
    else
        if start_line != -1
            let report = s:do_get_col_num_rfc_lines(cur_line, a:delim, start_line, cur_line, a:expected_num_fields)
            if len(report)
                return report
            endif
        endif
        if end_line != -1
            let report = s:do_get_col_num_rfc_lines(cur_line, a:delim, cur_line, end_line, a:expected_num_fields)
            if len(report)
                return report
            endif
        endif
        return []
    endif
endfunc


func! rainbow_csv#provide_column_info_on_hover()
    let [delim, policy] = rainbow_csv#get_current_dialect()
    if policy == 'monocolumn'
        return
    endif
    let line = getline('.')

    let header = rainbow_csv#get_csv_header(delim, policy)
    let fields = []
    let col_num = 0
    if policy == 'quoted_rfc'
        let report = s:get_col_num_rfc_lines(line, delim, len(header))
        if len(report) != 2
            echo ''
            return
        endif
        let [fields, col_num] = report
    else
        let fields = rainbow_csv#preserving_smart_split(line, delim, policy)[0]
        let col_num = s:get_col_num_single_line(fields, delim, 0)
    endif
    let num_cols = len(fields)

    let ui_message = printf('Col #%s', col_num + 1)
    let col_name = ''
    if col_num < len(header)
        let col_name = header[col_num]
    endif

    let max_col_name = 50
    if len(col_name) > max_col_name
        let col_name = strpart(col_name, 0, max_col_name) . '...'
    endif
    if col_name != ""
        let ui_message = ui_message . printf(' "%s"', col_name)
    endif
    if len(header) != num_cols
        let ui_message = ui_message . '; WARN: num of fields in Header and this line differs'
    endif
    if exists("b:root_table_name")
        let ui_message = ui_message . printf('; F7: Copy to %s', b:root_table_name)
    endif
    echo ui_message
endfunc


func! s:get_num_columns_if_delimited(delim, policy)
    let lastLineNo = min([line("$"), 100])
    if (lastLineNo < 5)
        return 0
    endif
    let num_fields = 0
    let num_lines_tested = 0
    for linenum in range(1, lastLineNo)
        let line = getline(linenum)
        if len(line) && line[0] == '#'
            continue
        endif
        let num_lines_tested += 1
        let num_fields_cur = len(rainbow_csv#preserving_smart_split(line, a:delim, a:policy)[0])
        if !num_fields
            let num_fields = num_fields_cur
        endif
        if (num_fields != num_fields_cur || num_fields < 2)
            return 0
        endif
    endfor
    if num_lines_tested < 5
        return 0
    endif
    return num_fields
endfunc


func! s:guess_table_params_from_content()
    let best_dialect = []
    let best_score = 1
    for delim in s:delimiters
        let policy = (delim == ',' || delim == ';') ? 'quoted' : 'simple'
        let score = s:get_num_columns_if_delimited(delim, policy)
        if score > best_score
            let best_dialect = [delim, policy]
            let best_score = score
        endif
    endfor
    if best_score > s:max_columns
        return []
    endif
    return best_dialect
endfunc


func! s:guess_table_params_from_content_frequency_based()
    let best_delim = ','
    let best_score = 0
    let lastLineNo = min([line("$"), 50])
    for delim in s:delimiters
        let regex_delim = escape(delim, s:magic_chars)
        let score = 0
        for linenum in range(1, lastLineNo)
            let line = getline(linenum)
            let score += len(split(line, regex_delim, 1)) - 1
        endfor
        if score > best_score
            let best_delim = delim
            let best_score = score
        endif
    endfor
    let best_policy = (best_delim == ',' || best_delim == ';') ? 'quoted' : 'simple'
    return [best_delim, best_policy]
endfunc


func! rainbow_csv#clear_current_buf_content()
    let nl = line("$")
    call cursor(1, 1)
    execute "delete " . nl
endfunc


func! rainbow_csv#generate_tab_statusline(tabstop_val, delim_len, template_fields)
    let result = []
    let space_deficit = 0
    for nf in range(len(a:template_fields))
        let available_space = (a:delim_len + len(a:template_fields[nf]) / a:tabstop_val) * a:tabstop_val
        let column_name = 'a' . string(nf + 1)
        let extra_len = available_space - len(column_name) - 1
        if extra_len < 0
            let space_deficit -= extra_len
            let extra_len = 0
        else
            let regained = min([space_deficit, extra_len])
            let space_deficit -= regained
            let extra_len -= regained
        endif
        let space_filling = repeat(' ', extra_len + 1)
        if nf + 1 == len(a:template_fields)
            let space_filling = ''
        endif
        call add(result, column_name)
        call add(result, space_filling)
    endfor
    return result
endfunc


func! s:status_escape_string(src)
    " Strings in 'substitute' must follow esoteric rules, see `:help substitute()`
    let result = substitute(a:src, ' ', '\\ ', 'g')
    let result = substitute(result, '"', '\\"', 'g')
    return result
endfunc


func! rainbow_csv#restore_statusline()
    if !exists("b:statusline_before")
        return
    endif
    augroup StatusDisableGrp
        autocmd!
    augroup END
    let escaped_statusline = s:status_escape_string(b:statusline_before)
    execute "set statusline=" . escaped_statusline
    unlet b:statusline_before
endfunc


func! rainbow_csv#set_statusline_columns()
    let [delim, policy] = rainbow_csv#get_current_dialect()
    if !exists("b:statusline_before")
        let b:statusline_before = &statusline 
    endif
    let has_number_column = &number
    let indent = ''
    if has_number_column
        let indent_len = max([len(string(line('$'))) + 1, 4])
        let indent = ' NR' . repeat(' ', indent_len - 3)
    endif
    let cur_line = policy == 'quoted_rfc' ? getline(1) : getline(line('.'))
    let cur_fields = rainbow_csv#preserving_smart_split(cur_line, delim, policy)[0]
    let status_labels = []
    if delim == "\t"
        let status_labels = rainbow_csv#generate_tab_statusline(&tabstop, len(delim), cur_fields)
    else
        let status_labels = rainbow_csv#generate_tab_statusline(1, len(delim), cur_fields)
    endif
    let max_len = winwidth(0)
    let cur_len = len(indent)
    let rb_statusline = '%#status_line_default_hl#' . indent
    let num_columns = len(status_labels) / 2
    for nf in range(num_columns)
        let color_id = nf % s:num_groups
        let column_name = status_labels[nf * 2]
        let space_filling = status_labels[nf * 2 + 1]
        let cur_len += len(column_name) + len(space_filling)
        if cur_len + 1 >= max_len 
            break
        endif
        let rb_statusline = rb_statusline . '%#status_color' . color_id . '#' . column_name . '%#status_line_default_hl#' . space_filling
    endfor
    let rb_statusline = s:status_escape_string(rb_statusline)
    execute "setlocal statusline=" . rb_statusline
    redraw!
    augroup StatusDisableGrp
        autocmd CursorMoved * call rainbow_csv#restore_statusline()
    augroup END
endfunc


func! s:get_rb_script_path_for_this_table()
    let rb_script_name = expand("%:t") . ".rbql"
    call s:ensure_storage_exists()
    let rb_script_path = s:rb_storage_dir . '/' . rb_script_name
    return rb_script_path
endfunc


func! s:generate_microlang_syntax(nfields)
    if s:get_meta_language() == "python"
        set ft=python
    else
        set ft=javascript
    endif

    for lnum in range(1, a:nfields)
        let color_num = (lnum - 1) % s:num_groups
        let cmd = 'syntax keyword rbql_color%d a%d'
        exe printf(cmd, color_num, lnum)
        let cmd = 'syntax keyword rbql_color%d b%d'
        exe printf(cmd, color_num, lnum)
    endfor

    syntax match RbCmd "\c \@<=ORDER \+BY \@="
    syntax match RbCmd "\c\(^ *\)\@<=SELECT\( \+TOP \+[0-9]\+\)\?\( \+DISTINCT\( \+COUNT\)\?\)\? \@="
    syntax match RbCmd "\c\(^ *\)\@<=UPDATE\( \+SET\)\? \@="
    syntax match RbCmd "\c \@<=WHERE \@="
    syntax match RbCmd "\c \@<=DESC\( *$\)\@="
    syntax match RbCmd "\c \@<=ASC\( *$\)\@="
    syntax match RbCmd "\c \@<=\(\(\(STRICT \+\)\?LEFT \+\)\|\(INNER \+\)\)\?JOIN \+[^ ]\+ \+ON \@="
endfunc


func! s:make_select_line(num_fields)
    let select_line = 'select '
    let new_rows = []
    for nf in range(1, a:num_fields)
        let select_line = select_line . 'a' . nf
        if nf < a:num_fields
            let select_line = select_line . ', '
        endif
    endfor
    return select_line
endfunc


func! s:make_rbql_demo(num_fields, rbql_welcome_path)
    let select_line = s:make_select_line(a:num_fields)
    let lines = readfile(a:rbql_welcome_path)
    let query_line_num = 1
    for lnum in range(len(lines))
        let patched = substitute(lines[lnum], '###SELECT_PLACEHOLDER###', select_line, "g")
        if patched != lines[lnum]
            let query_line_num = lnum + 1
            let lines[lnum] = patched
        endif
    endfor
    call setline(1, lines)
    call cursor(query_line_num, 1)
    w
endfunc


func! rainbow_csv#select_from_file()
    let [delim, policy] = rainbow_csv#get_current_dialect()

    let meta_language = s:get_meta_language()

    if meta_language == "python" && !s:EnsurePythonInitialization()
        echoerr "Python interpreter not found. Unable to run in this mode."
        return 0
    endif

    if meta_language == "js" && !s:EnsureJavaScriptInitialization()
        echoerr "Node.js interpreter not found. Unable to run in this mode."
        return 0
    endif

    if exists("b:selected_buf") && buflisted(b:selected_buf)
        execute "bd " . b:selected_buf
    endif

    let buf_number = bufnr("%")
    let buf_path = resolve(expand("%:p"))

    let rb_script_path = s:get_rb_script_path_for_this_table()
    let already_exists = filereadable(rb_script_path)

    let num_fields = len(rainbow_csv#preserving_smart_split(getline(1), delim, policy)[0])

    call rainbow_csv#set_statusline_columns()

    let splitbelow_before = &splitbelow
    set splitbelow
    execute "split " . fnameescape(rb_script_path)
    if bufnr("%") == buf_number
        echoerr "Something went wrong"
        return
    endif
    if !splitbelow_before
        set nosplitbelow
    endif

    let b:table_path = buf_path
    let b:table_buf_number = buf_number
    let b:rainbow_select = 1

    if !exists("g:disable_rainbow_key_mappings")
        nnoremap <buffer> <F5> :RbRun<cr>
    endif

    call s:generate_microlang_syntax(num_fields)
    if !already_exists
        if meta_language == "python"
            let rbql_welcome_py_path = s:script_folder_path . '/rbql_core/welcome_py.rbql'
            call s:make_rbql_demo(num_fields, rbql_welcome_py_path)
        else
            let rbql_welcome_js_path = s:script_folder_path . '/rbql_core/welcome_js.rbql'
            call s:make_rbql_demo(num_fields, rbql_welcome_js_path)
        endif
    endif
endfunc


func! rainbow_csv#copy_file_content_to_buf(src_file_path, dst_buf_no)
    bd!
    redraw!
    echo "executing..."
    execute "buffer " . a:dst_buf_no
    call rainbow_csv#clear_current_buf_content()
    let lines = readfile(a:src_file_path)
    call setline(1, lines)
endfunc


func! s:ShowImportantMessage(msg_header, msg_lines)
    echohl ErrorMsg
    echomsg a:msg_header
    echohl None
    for msg in a:msg_lines
        echomsg msg
    endfor
    call input("Press ENTER to continue...")
endfunc


func! rainbow_csv#parse_report(report_content)
    let lines = split(a:report_content, "\n")
    let psv_warning_report = ''
    let psv_error_report = ''
    let psv_query_status = (len(lines) > 0 && len(lines[0]) > 0) ? lines[0] : 'Unknown error'
    let psv_dst_table_path = len(lines) > 1 ? lines[1] : ''
    let report = join(lines[2:], "\n")
    if psv_query_status == "OK"
        let psv_warning_report = report
    else
        let psv_error_report = report
    endif
    return [psv_query_status, psv_error_report, psv_warning_report, psv_dst_table_path]
endfunc


func! s:get_output_format_params(input_delim, input_policy)
    let out_format = exists('g:rbql_output_format') ? g:rbql_output_format : 'input'
    if out_format == 'csv'
        return [',', 'quoted']
    endif
    if out_format == 'tsv'
        return ["\t", 'simple']
    endif
    return [a:input_delim, a:input_policy]
endfunc


func! s:converged_select(table_buf_number, rb_script_path, query_buf_nr)
    let meta_language = s:get_meta_language()

    if meta_language == "python" && !s:EnsurePythonInitialization()
        echoerr "Python interpreter not found. Unable to run in this mode."
        return 0
    endif

    if meta_language == "js" && !s:EnsureJavaScriptInitialization()
        echoerr "Node.js interpreter not found. Unable to run in this mode."
        return 0
    endif

    let rbql_encoding = exists('g:rbql_encoding') ? g:rbql_encoding : 'utf-8'
    if rbql_encoding != 'utf-8' && rbql_encoding != 'latin-1'
        echoerr "Unsupported rbql encoding. Must be 'utf-8' or 'latin-1'"
        return 0
    endif

    let table_filetype = getbufvar(a:table_buf_number, "&ft")
    let input_dialect = rainbow_csv#ft_to_dialect(table_filetype)
    if !len(input_dialect)
        echoerr "File is not a rainbow table"
        return 0
    endif
    let input_delim = input_dialect[0]
    let input_policy = input_dialect[1]

    let table_path = expand("#" . a:table_buf_number . ":p")
    if table_path == ""
        " For unnamed buffers. E.g. can happen for stdin-read buffer: `cat data.tsv | vim -`
        let tmp_file_name = "tmp_table_" .  strftime("%Y_%m_%d_%H_%M_%S") . ".txt"
        let table_path = s:rb_storage_dir . "/" . tmp_file_name
        execute "w " . table_path
    endif

    let psv_query_status = 'Unknown error'
    let psv_error_report = 'Something went wrong'
    let psv_warning_report = ''
    let psv_dst_table_path = ''

    redraw!
    echo "executing..."
    let table_path_esc = s:py_source_escape(table_path)
    let rb_script_path_esc = s:py_source_escape(a:rb_script_path)
    let input_delim_escaped = s:py_source_escape(input_delim)
    let [out_delim, out_policy] = s:get_output_format_params(input_delim, input_policy)
    let out_delim_escaped = s:py_source_escape(out_delim)
    let py_call = 'vim_rbql.run_execute("' . table_path_esc . '", "' . rb_script_path_esc . '", "' . rbql_encoding . '", "' . input_delim_escaped . '", "' . input_policy . '", "' . out_delim_escaped . '", "' . out_policy . '")'
    if meta_language == "js"
        let rbql_executable_path = s:script_folder_path . '/rbql_core/vim_rbql.js'
        let cmd_args = ['node', shellescape(rbql_executable_path), shellescape(table_path), shellescape(a:rb_script_path), rbql_encoding, shellescape(input_delim), input_policy, shellescape(out_delim), out_policy]
        let cmd = join(cmd_args, ' ')
        let report_content = system(cmd)
        let [psv_query_status, psv_error_report, psv_warning_report, psv_dst_table_path] = rainbow_csv#parse_report(report_content)
    elseif s:system_python_interpreter != ""
        let rbql_executable_path = s:script_folder_path . '/rbql_core/vim_rbql.py'
        let cmd_args = [s:system_python_interpreter, shellescape(rbql_executable_path), shellescape(table_path), shellescape(a:rb_script_path), rbql_encoding, shellescape(input_delim), input_policy, shellescape(out_delim), out_policy]
        let cmd = join(cmd_args, ' ')
        let report_content = system(cmd)
        let [psv_query_status, psv_error_report, psv_warning_report, psv_dst_table_path] = rainbow_csv#parse_report(report_content)
    elseif has("python3")
        exe 'python3 ' . py_call
    elseif s:has_python_27()
        exe 'python ' . py_call
    else
        call s:ShowImportantMessage("Error", ["Python not found, vim must have 'python' or 'python3' feature installed to run in this mode"])
        return 0
    endif

    if psv_query_status != "OK"
        call s:ShowImportantMessage(psv_query_status, [psv_error_report])
        return 0
    endif

    if a:query_buf_nr != -1
        execute "bd! " . a:query_buf_nr
    endif

    if index(split(psv_warning_report, "\n"), 'Output has multiple fields: using "CSV" output format instead of "Monocolumn"') == -1
        call s:update_table_record(psv_dst_table_path, out_delim, out_policy)
    else
        call s:update_table_record(psv_dst_table_path, ',', 'quoted')
    endif
    execute "e " . fnameescape(psv_dst_table_path)

    let b:self_path = psv_dst_table_path
    let b:root_table_buf_number = a:table_buf_number
    let b:root_table_name = fnamemodify(table_path, ":t")
    let b:self_buf_number = bufnr("%")
    call setbufvar(a:table_buf_number, 'selected_buf', b:self_buf_number)

    if !exists("g:disable_rainbow_key_mappings")
        nnoremap <buffer> <F7> :call rainbow_csv#copy_file_content_to_buf(b:self_path, b:root_table_buf_number)<cr>
    endif

    if len(psv_warning_report)
        let warnings = split(psv_warning_report, "\n")
        for wnum in range(len(warnings))
            let warnings[wnum] = 'Warning: ' . warnings[wnum]
        endfor
        call s:ShowImportantMessage("Completed with WARNINGS!", warnings)
    endif
    return 1
endfunc


func! rainbow_csv#set_table_name_for_buffer(table_name)
    let table_path = resolve(expand("%:p"))
    let new_record = [a:table_name, table_path]
    let records = s:try_read_index(s:table_names_settings)
    let records = s:update_records(records, a:table_name, new_record)
    if len(records) > 100
        call remove(records, 0)
    endif
    call s:write_index(records, s:table_names_settings)
endfunction


func! s:run_cmd_query(query)
    let rb_script_path = s:get_rb_script_path_for_this_table()
    call writefile([a:query], rb_script_path)
    let table_buf_number = bufnr("%")
    call s:converged_select(table_buf_number, rb_script_path, -1)
endfunction


func! rainbow_csv#run_select_cmd_query(query_string)
    let query = 'SELECT ' . a:query_string
    call s:run_cmd_query(query)
endfunction


func! rainbow_csv#run_update_cmd_query(query_string)
    let query = 'UPDATE ' . a:query_string
    call s:run_cmd_query(query)
endfunction


func! rainbow_csv#finish_query_editing()
    if !exists("b:rainbow_select")
        echoerr "Execute from rainbow query buffer"
        return
    endif
    w
    let rb_script_path = expand("%:p")
    let query_buf_nr = bufnr("%")
    let table_buf_number = b:table_buf_number
    call s:converged_select(table_buf_number, rb_script_path, query_buf_nr)
endfunc


func! rainbow_csv#generate_rainbow_syntax(delim)
    let syntax_lines = []
    let regex_delim = escape(a:delim, s:magic_chars)
    let char_class_delim = s:char_class_escape(a:delim)
    let groupid = s:num_groups - 1
    while groupid >= 0
        let next_group_id = groupid + 1 < s:num_groups ? groupid + 1 : 0
        let cmd = 'syntax match column%d /.\{-}\(%s\|$\)/ nextgroup=column%d'
        call add(syntax_lines, printf(cmd, groupid, regex_delim, next_group_id))
        let groupid -= 1
    endwhile
    return syntax_lines
endfunc


func! rainbow_csv#generate_escaped_rainbow_syntax(delim)
    let syntax_lines = []
    let regex_delim = escape(a:delim, s:magic_chars)
    let char_class_delim = s:char_class_escape(a:delim)
    let groupid = s:num_groups - 1
    while groupid >= 0
        let next_group_id = groupid + 1 < s:num_groups ? groupid + 1 : 0
        let cmd = 'syntax match column%d /.\{-}\(%s\|$\)/ nextgroup=escaped_column%d,column%d'
        call add(syntax_lines, printf(cmd, groupid, regex_delim, next_group_id, next_group_id))
        let cmd = 'syntax match escaped_column%d / *"\([^"]*""\)*[^"]*" *\(%s\|$\)/ nextgroup=escaped_column%d,column%d'
        call add(syntax_lines, printf(cmd, groupid, regex_delim, next_group_id, next_group_id))
        let groupid -= 1
    endwhile
    return syntax_lines
endfunc


func! rainbow_csv#generate_escaped_rfc_rainbow_syntax(delim)
    let syntax_lines = []
    let regex_delim = escape(a:delim, s:magic_chars)
    let char_class_delim = s:char_class_escape(a:delim)
    let groupid = s:num_groups - 1
    while groupid >= 0
        let next_group_id = groupid + 1 < s:num_groups ? groupid + 1 : 0
        let cmd = 'syntax match column%d /.\{-}\(%s\|$\)/ nextgroup=escaped_column%d,column%d'
        call add(syntax_lines, printf(cmd, groupid, regex_delim, next_group_id, next_group_id))
        let cmd = 'syntax match escaped_column%d / *"\(\([^"]\|\n\)*""\)*\([^"]\|\n\)*" *\(%s\|$\)/ nextgroup=escaped_column%d,column%d'
        call add(syntax_lines, printf(cmd, groupid, regex_delim, next_group_id, next_group_id))
        let groupid -= 1
    endwhile
    return syntax_lines
endfunc


func! rainbow_csv#generate_whitespace_syntax()
    let syntax_lines = []
    let groupid = s:num_groups - 1
    while groupid >= 0
        let next_group_id = groupid + 1 < s:num_groups ? groupid + 1 : 0
        let cmd = 'syntax match column%d / *.\{-}\(  *\|$\)/ nextgroup=column%d'
        call add(syntax_lines, printf(cmd, groupid, next_group_id))
        let groupid -= 1
    endwhile
    return syntax_lines
endfunc


func! rainbow_csv#ensure_syntax_exists(rainbow_ft, delim, policy)
    let syntax_code = ""
    if a:policy == 'quoted'
        let syntax_lines = rainbow_csv#generate_escaped_rainbow_syntax(a:delim)
    elseif a:policy == 'quoted_rfc'
        let syntax_lines = rainbow_csv#generate_escaped_rfc_rainbow_syntax(a:delim)
    elseif a:policy == 'simple'
        let syntax_lines = rainbow_csv#generate_rainbow_syntax(a:delim)
    elseif a:policy == 'whitespace'
        let syntax_lines = rainbow_csv#generate_whitespace_syntax()
    else
        echoerr 'bad delim policy: ' . a:policy
    endif
    let syntax_file_path = s:script_folder_path . '/syntax/' . a:rainbow_ft . '.vim'
    call writefile(syntax_lines, syntax_file_path)
endfunc


func! rainbow_csv#do_set_rainbow_filetype(rainbow_ft)
    let b:originial_ft = &ft
    execute "set ft=" . a:rainbow_ft
endfunc


func! rainbow_csv#set_rainbow_filetype(delim, policy)
    let rainbow_ft = rainbow_csv#dialect_to_ft(a:delim, a:policy)
    if match(rainbow_ft, 'rcsv') == 0
        call rainbow_csv#ensure_syntax_exists(rainbow_ft, a:delim, a:policy)
    endif
    call rainbow_csv#do_set_rainbow_filetype(rainbow_ft)
endfunc


func! rainbow_csv#buffer_disable_rainbow_features()
    if (!exists("b:rainbow_features_enabled") || b:rainbow_features_enabled == 0)
        return
    endif
    let b:rainbow_features_enabled = 0

    augroup RainbowHintGrp
        autocmd! CursorMoved <buffer>
    augroup END
    if !exists("g:disable_rainbow_key_mappings")
        unmap <buffer> <F5>
    endif
endfunc


func! rainbow_csv#buffer_enable_rainbow_features(delim, policy)
    call rainbow_csv#buffer_disable_rainbow_features()

    let b:rainbow_features_enabled = 1

    set laststatus=2

    if &compatible == 1
        set nocompatible
    endif

    " maybe use setlocal number ?
    set number

    if !exists("g:disable_rainbow_key_mappings")
        nnoremap <buffer> <F5> :RbSelect<cr>
    endif

    let b:cached_virtual_header = s:read_virtual_header(a:delim, a:policy)

    highlight status_line_default_hl ctermbg=black guibg=black

    cnoreabbrev <expr> <buffer> Select rainbow_csv#set_statusline_columns() == "dummy" ? 'Select' : 'Select'
    cnoreabbrev <expr> <buffer> select rainbow_csv#set_statusline_columns() == "dummy" ? 'Select' : 'Select'
    cnoreabbrev <expr> <buffer> SELECT rainbow_csv#set_statusline_columns() == "dummy" ? 'Select' : 'Select'

    cnoreabbrev <expr> <buffer> Update rainbow_csv#set_statusline_columns() == "dummy" ? 'Update' : 'Update'
    cnoreabbrev <expr> <buffer> update rainbow_csv#set_statusline_columns() == "dummy" ? 'Update' : 'Update'
    cnoreabbrev <expr> <buffer> UPDATE rainbow_csv#set_statusline_columns() == "dummy" ? 'Update' : 'Update'

    augroup RainbowHintGrp
        autocmd! CursorMoved <buffer>
        if !exists("g:disable_rainbow_hover") || g:disable_rainbow_hover == 0
            autocmd CursorMoved <buffer> call rainbow_csv#provide_column_info_on_hover()
        endif
    augroup END
endfunc


function! rainbow_csv#get_visual_selection()
    " Taken from here: https://stackoverflow.com/a/6271254/2898283
    let [line_start, column_start] = getpos("'<")[1:2]
    let [line_end, column_end] = getpos("'>")[1:2]
    let lines = getline(line_start, line_end)
    if len(lines) == 0
        return ''
    endif
    let lines[-1] = lines[-1][: column_end - (&selection == 'inclusive' ? 1 : 2)]
    let lines[0] = lines[0][column_start - 1:]
    return join(lines, "\n")
endfunction


func! rainbow_csv#manual_set(arg_policy, is_multidelim)
    if a:is_multidelim
        let delim = rainbow_csv#get_visual_selection()
        let policy = 'simple'
        let max_delim_len = exists('g:max_multichar_delim_len') ? g:max_multichar_delim_len : 5
        if len(delim) > max_delim_len
            echoerr 'Multicharater delimiter is too long. Adjust g:max_multichar_delim_len or use a different separator'
            return
        endif
    else
        let delim = getline('.')[col('.') - 1]  
        let policy = a:arg_policy
    endif
    if policy == 'auto'
        if delim == ',' || delim == ';'
            let policy = 'quoted'
        elseif delim == ' '
            let policy = 'whitespace'
        else
            let policy = 'simple'
        endif
    endif
    if delim == '"' && policy == 'quoted'
        echoerr 'Double quote delimiter is incompatible with "quoted" policy'
        return
    endif
    call rainbow_csv#set_rainbow_filetype(delim, policy)
    let table_path = resolve(expand("%:p"))
    call s:update_table_record(table_path, delim, policy)
endfunc


func! rainbow_csv#manual_disable()
    if rainbow_csv#is_rainbow_table()
        let original_filetype = exists("b:originial_ft") ? b:originial_ft : ''
        execute "set ft=" . original_filetype
        let table_path = resolve(expand("%:p"))
        call s:update_table_record(table_path, '', 'disabled')
    endif
endfunc


func! rainbow_csv#handle_new_file()
    let table_extension = expand('%:e')
    if table_extension == 'tsv' || table_extension == 'tab'
        call rainbow_csv#do_set_rainbow_filetype('tsv')
        return
    endif

    let table_params = s:guess_table_params_from_content()
    if !len(table_params) && table_extension == 'csv'
        let table_params = s:guess_table_params_from_content_frequency_based()
    endif
    if !len(table_params)
        let b:rainbow_features_enabled = 0
        return
    endif
    call rainbow_csv#set_rainbow_filetype(table_params[0], table_params[1])
endfunc


func! rainbow_csv#handle_buffer_enter()
    if exists("b:rainbow_features_enabled")
        if b:rainbow_features_enabled
            " This is a workaround against Vim glitches. sometimes it 'forgets' to highlight the file even when ft=csv, see https://stackoverflow.com/questions/14779299/syntax-highlighting-randomly-disappears-during-file-saving
            " From the other hand it can discard highlight ":hi ... " rules from user config, so let's disable this for now
            " syntax enable
            " another hack instead of `syntax enable` which is kind of global
            let ft_power_cycle = &ft
            execute "set ft=" . ft_power_cycle
        endif
        return
    endif

    if exists("b:current_syntax")
        return
    endif

    let table_path = resolve(expand("%:p"))
    let table_params = s:get_table_record(table_path)
    if len(table_params)
        if table_params[1] == 'disabled' || table_params[1] == 'monocolumn'
            let b:rainbow_features_enabled = 0
        else
            call rainbow_csv#set_rainbow_filetype(table_params[0], table_params[1])
        endif
        return
    endif

    if exists("g:disable_rainbow_csv_autodetect") && g:disable_rainbow_csv_autodetect
        return
    endif

    call rainbow_csv#handle_new_file()
endfunc


func! rainbow_csv#handle_filetype_change()
    let [delim, policy] = rainbow_csv#get_current_dialect()
    if policy == 'monocolumn'
        call rainbow_csv#buffer_disable_rainbow_features()
        return
    endif
    call rainbow_csv#buffer_enable_rainbow_features(delim, policy)
endfunc
