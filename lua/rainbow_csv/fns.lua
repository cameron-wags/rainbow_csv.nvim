-- "==============================================================================
-- "
-- " Description: Rainbow CSV
-- " Authors: Dmitry Ignatovich, ...
-- "
-- "==============================================================================
local M = {}

-- let s:max_columns = exists('g:rcsv_max_columns') ? g:rcsv_max_columns : 30
local max_columns = 30
if vim.g.rcsv_max_columns ~= nil then
	max_columns = vim.g.rcsv_max_columns
end

-- let s:rb_storage_dir = exists('g:rb_storage_dir') ? g:rb_storage_dir : $HOME . '/.rainbow_csv_storage'
local rb_storage_dir = vim.env.HOME .. '/.rainbow_csv_storage'
if vim.g.rb_storage_dir ~= nil then
	rb_storage_dir = vim.g.rb_storage_dir
end

-- let s:table_names_settings = exists('g:table_names_settings') ? g:table_names_settings : $HOME . '/.rbql_table_names'
local table_names_settings = vim.env.HOME .. '/.rbql_table_names'
if vim.g.table_names_settings ~= nil then
	table_names_settings = vim.g.table_names_settings
end

-- let s:rainbow_table_index = exists('g:rainbow_table_index') ? g:rainbow_table_index : $HOME . '/.rbql_table_index'
local rainbow_table_index = vim.env.HOME .. '/.rbql_table_index'
if vim.g.rainbow_table_index ~= nil then
	rainbow_table_index = vim.g.rainbow_table_index
end

-- let s:script_folder_path = expand('<sfile>:p:h:h')
local script_folder_path = vim.fn.expand('<sfile>:p:h:h')
-- let s:python_env_initialized = 0
local python_env_initialized = false
-- let s:js_env_initialized = 0
local js_env_initialized = false
-- let s:system_python_interpreter = ''
local system_python_interpreter = ''

-- let s:magic_chars = '^*$.~/[]\'
local magic_chars = [[^*$.~/[]\]]

-- let s:named_syntax_map = {'csv': [',', 'quoted', ''], 'csv_semicolon': [';', 'quoted', ''], 'tsv': ["\t", 'simple', ''], 'csv_pipe': ['|', 'simple', ''], 'csv_whitespace': [" ", 'whitespace', ''], 'rfc_csv': [',', 'quoted_rfc', ''], 'rfc_semicolon': [';', 'quoted_rfc', '']}
local named_syntax_map = {
	csv = { ',', 'quoted', '' },
	csv_semicolon = { ';', 'quoted', '' },
	tsv = { "\t", 'simple', '' },
	csv_pipe = { '|', 'simple', '' },
	csv_whitespace = { " ", 'whitespace', '' },
	rfc_csv = { ',', 'quoted_rfc', '' },
	rfc_semicolon = { ';', 'quoted_rfc', '' }
}

-- let s:autodetection_delims = exists('g:rcsv_delimiters') ? g:rcsv_delimiters : ["\t", ",", ";", "|"]
local autodetection_delims = { "\t", ",", ";", "|" }
if vim.g.rcsv_delimiters ~= nil then
	autodetection_delims = vim.g.rcsv_delimiters
end

-- let s:number_regex = '^[0-9]\+\(\.[0-9]\+\)\?$'
local number_regex = [[^[0-9]\+\(\.[0-9]\+\)\?$]]
-- let s:non_numeric = -1
local non_numeric = -1

-- let s:align_progress_bar_position = 0
local align_progress_bar_position = 0
-- let s:progress_bar_size = 20
local progress_bar_size = 20

local num_groups = nil

-- " Vim has 2 different variables: filetype and syntax. syntax is a subset of filetype
-- " We need to use both of them.


-- start vim fn rewrites
local function lua_strpart(str, start, count)
	if count == nil then
		return string.sub(str, start + 1)
	else
		return string.sub(str, start + 1, start + count)
	end
end

local function lua_stridx(haystack, needle, start)
	local result
	if start == nil then
		result = string.find(haystack, needle, 1, true)
	else
		result = string.find(haystack, needle, start + 1, true)
	end
	if result == nil then
		return -1
	else
		return result - 1
	end
end

local function lua_charat(str, idx)
	return string.sub(str, idx + 1, idx + 1)
end

local escape_lkp = {}
local function lua_escape(str, targets)
	local try = escape_lkp[str .. targets]
	if try ~= nil then
		return try
	end
	local result = vim.fn.escape(str, targets)
	escape_lkp[str .. targets] = result
	return result
end

local function lua_join(list, sep)
	if sep == nil then
		return table.concat(list, ' ')
	else
		return table.concat(list, sep)
	end
end

-- " XXX Use :syntax command to list all current syntax groups
-- " XXX Use :highlight command to list all current highlight groups


-- " TODO fix update -> Update switch it also occures with this `:echo "update "` -> `:echo "Update "` scenario. but only with csv files!
-- " It might be possible  to modify set_statusline_columns() to read current
-- " command line text and if it starts with "select" indeed, then replace
-- " (return special flag) otherwise do not replace by ternary expression

-- " TODO implement select -> Select switch for monocolumn files
-- "
-- " TODO support comment prefixes

-- " TODO implement csv_lint for "rfc_csv" dialect


-- func! s:get_auto_policy_for_delim(delim)
--     if a:delim == ',' || a:delim == ';'
--         return 'quoted'
--     elseif a:delim == ' '
--         return 'whitespace'
--     else
--         return 'simple'
--     endif
-- endfunc
local function get_auto_policy_for_delim(delim)
	if delim == ',' or delim == ';' then
		return 'quoted'
	elseif delim == ' ' then
		return 'whitespace'
	else
		return 'simple'
	end
end

-- func! s:has_custom_links()
--     return exists('g:rcsv_colorlinks') && len(g:rcsv_colorlinks) > 1
-- endfunc
local function has_custom_links()
	if vim.g.rcsv_colorlinks then
		return #vim.g.rcsv_colorlinks > 1
	else
		return false
	end
end

-- func! s:init_groups_from_links()
--     let link_groups = ['String', 'Comment', 'NONE', 'Special', 'Identifier', 'Type', 'Question', 'CursorLineNr', 'ModeMsg', 'Title']
--     if s:has_custom_links()
--         let link_groups = g:rcsv_colorlinks
--     endif
--     for gi in range(len(link_groups))
--         let cmd = 'highlight link status_color%d %s'
--         exe printf(cmd, gi, link_groups[gi])
--         let cmd = 'highlight link rbql_color%d %s'
--         exe printf(cmd, gi, link_groups[gi])
--         let cmd = 'highlight link column%d %s'
--         exe printf(cmd, gi, link_groups[gi])
--         let cmd = 'highlight link escaped_column%d %s'
--         exe printf(cmd, gi, link_groups[gi])
--     endfor
--     let s:num_groups = len(link_groups)
-- endfunc
local function init_groups_from_links()
	local link_groups = { 'String', 'Comment', 'NONE', 'Special', 'Identifier', 'Type', 'Question', 'CursorLineNr',
		'ModeMsg', 'Title' }
	if has_custom_links() then
		link_groups = vim.g.rcsv_colorlinks
	end
	for index, value in ipairs(link_groups) do
		vim.cmd('highlight link status_color' .. index - 1 .. ' ' .. value)
		vim.cmd('highlight link rbql_color' .. index - 1 .. ' ' .. value)
		vim.cmd('highlight link column' .. index - 1 .. ' ' .. value)
		vim.cmd('highlight link escaped_column' .. index - 1 .. ' ' .. value)
	end
	num_groups = #link_groups
end

-- func! s:has_custom_colors()
--     return exists('g:rcsv_colorpairs') && len(g:rcsv_colorpairs) > 1
-- endfunc
local function has_custom_colors()
	if vim.g.rcsv_colorpairs then
		return #vim.g.rcsv_colorpairs > 1
	else
		return false
	end
end

-- func! s:use_system_python()
--     return exists('g:rbql_use_system_python') ? g:rbql_use_system_python : 0
-- endfunc
local function use_system_python()
	if vim.g.rbql_use_system_python then
		return vim.g.rbql_use_system_python
	else
		return false
	end
end

-- func! s:get_rbql_with_headers()
--     return exists('g:rbql_with_headers') ? g:rbql_with_headers : 0
-- endfunc
local function get_rbql_with_headers()
	if vim.g.rbql_with_headers then
		return vim.g.rbql_with_headers
	else
		return false
	end
end

-- func! s:init_groups_from_colors()
--     let pairs = [['red', 'red'], ['green', 'green'], ['blue', 'blue'], ['magenta', 'magenta'], ['NONE', 'NONE'], ['darkred', 'darkred'], ['darkblue', 'darkblue'], ['darkgreen', 'darkgreen'], ['darkmagenta', 'darkmagenta'], ['darkcyan', 'darkcyan']]
--     if s:has_custom_colors()
--         let pairs = g:rcsv_colorpairs
--     endif
--     for gi in range(len(pairs))
--         let cmd = 'highlight status_color%d ctermfg=%s guifg=%s ctermbg=black guibg=black'
--         exe printf(cmd, gi, pairs[gi][0], pairs[gi][1])
--         let cmd = 'highlight rbql_color%d ctermfg=%s guifg=%s'
--         exe printf(cmd, gi, pairs[gi][0], pairs[gi][1])
--         let cmd = 'highlight column%d ctermfg=%s guifg=%s'
--         exe printf(cmd, gi, pairs[gi][0], pairs[gi][1])
--         let cmd = 'highlight escaped_column%d ctermfg=%s guifg=%s'
--         exe printf(cmd, gi, pairs[gi][0], pairs[gi][1])
--     endfor
--     let s:num_groups = len(pairs)
-- endfunc
local function init_groups_from_colors()
	local pairs = { { 'red', 'red' },
		{ 'green', 'green' },
		{ 'blue', 'blue' },
		{ 'magenta', 'magenta' },
		{ 'NONE', 'NONE' },
		{ 'darkred', 'darkred' },
		{ 'darkblue', 'darkblue' },
		{ 'darkgreen', 'darkgreen' },
		{ 'darkmagenta', 'darkmagenta' },
		{ 'darkcyan', 'darkcyan' } }
	if has_custom_colors() then
		pairs = vim.g.rcsv_colorpairs
	end
	for index, value in ipairs(pairs) do
		vim.cmd('highlight status_color' ..
			index - 1 .. ' ctermfg=' .. value[1] .. ' guifg=' .. value[2] .. ' ctermbg=black guibg = black')
		vim.cmd('highlight rbql_color' .. index - 1 .. ' ctermfg=' .. value[1] .. ' guifg=' .. value[2])
		vim.cmd('highlight column' .. index - 1 .. ' ctermfg=' .. value[1] .. ' guifg=' .. value[2])
		vim.cmd('highlight escaped_column' .. index - 1 .. ' ctermfg=' .. value[1] .. ' guifg=' .. value[2])
	end
	num_groups = #pairs
end

-- func! rainbow_csv#init_rb_color_groups()
--     if !exists("g:syntax_on") || s:has_custom_colors()
--         call s:init_groups_from_colors()
--     else
--         call s:init_groups_from_links()
--     endif
--     highlight link escaped_startcolumn column0

--     highlight RbCmd ctermbg=blue guibg=blue
-- endfunc
M.init_rb_color_groups = function()
	-- todo not sure how to check this is ported correctly
	if vim.g.syntax_on ~= 1 or has_custom_colors() then
		init_groups_from_colors()
	else
		init_groups_from_links()
	end

	vim.cmd('highlight link escaped_startcolumn column0')
	vim.cmd('highlight RbCmd ctermbg=blue guibg=blue')
end



-- augroup RainbowCsvPluginInitAuGrp
--     " We need this autocmd only for users who has g:rcsv_colorpairs customization enabled and who set custom colorscheme manually or in .vimrc.
--     autocmd!
--     " If someone sets syntax on VimEnter autocmd, it will overwrite the color groups, so we restore them back here
--     autocmd VimEnter * call rainbow_csv#init_rb_color_groups()
--     autocmd ColorScheme * call rainbow_csv#init_rb_color_groups()
-- augroup END
vim.api.nvim_create_autocmd({ 'VimEnter', 'ColorScheme' }, {
	group = vim.api.nvim_create_augroup('RainbowCsvPluginInitAuGrp', { clear = true }),
	pattern = '*',
	callback = function() M.init_rb_color_groups() end
})


-- func! s:try_read_lines(src_path)
--     let lines = []
--     if (filereadable(a:src_path))
--         let lines = readfile(a:src_path)
--     endif
--     return lines
-- endfunc
local function try_read_lines(src_path)
	local lines = {}
	if vim.fn.filereadable(src_path) == 1 then
		lines = vim.fn.readfile(src_path)
	end
	return lines
end

-- func! s:try_read_index(src_path)
--     let lines = s:try_read_lines(a:src_path)
--     let records = []
--     for line in lines
--         let fields = split(line, "\t", 1)
--         call add(records, fields)
--     endfor
--     return records
-- endfunc
local function try_read_index(src_path)
	local lines = try_read_lines(src_path)
	local records = {}

	for _, line in ipairs(lines) do
		local fields = vim.fn.split(line, ' ', 1)
		table.insert(records, fields)
	end

	return records
end

-- func! s:write_index(records, dst_path)
--     let lines = []
--     for record in a:records
--         let new_line = join(record, "\t")
--         call add(lines, new_line)
--     endfor
--     call writefile(lines, a:dst_path)
-- endfunc
local function write_index(records, dst_path)
	local lines = {}
	for _, record in ipairs(records) do
		local new_line = lua_join(record, '\t')
		table.insert(lines, new_line)
	end
	vim.fn.writefile(lines, dst_path)
end

-- func! s:update_records(records, key, new_record)
--     let old_idx = -1
--     for ir in range(len(a:records))
--         let record = a:records[ir]
--         if len(record) && record[0] == a:key
--             let old_idx = ir
--         endif
--     endfor
--     if old_idx != -1
--         call remove(a:records, old_idx)
--     endif
--     call add(a:records, a:new_record)
--     return a:records
-- endfunc
local function update_records(records, key, new_record)
	-- todo this function mutates records
	local old_idx = -1
	for ir, record in ipairs(records) do
		if #record and record[1] == key then
			old_idx = ir
		end
	end
	if old_idx == -1 then
		table.remove(records, old_idx)
	end
	table.insert(records, new_record)
	return records
end

-- func! s:index_encode_delim(delim)
--     " We need this ugly function to keep backward-compatibility with old single-char delim format
--     if a:delim == "\t"
--         return 'TAB'
--     endif
--     if len(a:delim) > 1
--         let result = substitute(a:delim, '\\', '\\\\', "g")
--         let result = substitute(result, '\t', '\\t', "g")
--         return 'multichar:' . result
--     endif
--     return a:delim
-- endfunc
local function index_encode_delim(delim)
	if delim == "\t" then
		return 'TAB'
	end
	if #delim > 1 then
		local result = string.gsub(delim, [[\\]], [[\\\\]])
		result = string.gsub(result, [[\t]], [[\\t]])
		return 'multichar:' .. result
	end
	return delim
end

-- func! s:index_decode_delim(encoded_delim)
--     if a:encoded_delim == "TAB"
--         return "\t"
--     endif
--     if stridx(a:encoded_delim, 'multichar:') == 0
--         let result = strpart(a:encoded_delim, len('multichar:'))
--         let result = substitute(result, '\\t', '\t', 'g')
--         let result = substitute(result, '\\\\', '\\', 'g')
--         return result
--     endif
--     return a:encoded_delim
-- endfunc
local function index_decode_delim(encoded_delim)
	if encoded_delim == 'TAB' then
		return '\t'
	end
	if string.find(encoded_delim, 'multichar:') then
		local result = string.sub(encoded_delim, #'multichar:' + 1)
		result = string.gsub(result, [[\\t]], [[\t']])
		result = string.gsub(result, [[\\\\]], [[\\]])
		return result
	end
	return encoded_delim
end

-- func! s:update_table_record(table_path, delim, policy, comment_prefix)
--     if !len(a:table_path)
--         " For tmp buffers e.g. `cat table.csv | vim -`
--         return
--     endif
--     if stridx(a:comment_prefix, "\t") != -1
--         return " Failsafe to preserve index structure. No one will use comment prefix with tab anyway
--     endif
--     let encoded_delim = s:index_encode_delim(a:delim)
--     let new_record = [a:table_path, encoded_delim, a:policy, a:comment_prefix]
--     let records = s:try_read_index(s:rainbow_table_index)
--     let records = s:update_records(records, a:table_path, new_record)
--     if len(records) > 100
--         call remove(records, 0)
--     endif
--     call s:write_index(records, s:rainbow_table_index)
-- endfunc
local function update_table_record(table_path, delim, policy, comment_prefix)
	if #table_path == 0 or string.find(comment_prefix, '\t') ~= nil then
		return
	end
	local encoded_delim = index_encode_delim(delim)
	local new_record = { table_path, encoded_delim, policy, comment_prefix }
	local records = try_read_index(rainbow_table_index)
	records = update_records(records, table_path, new_record)
	if #records > 100 then
		table.remove(records, 1)
	end
	write_index(records, rainbow_table_index)
end

-- func! s:get_auto_comment_prefix()
--     return exists('g:rainbow_comment_prefix') ? g:rainbow_comment_prefix : ''
-- endfunc
local function get_auto_comment_prefix()
	if vim.g.rainbow_comment_prefix ~= nil then
		return vim.g.rainbow_comment_prefix
	else
		return ''
	end
end

-- func! s:get_table_record(table_path)
--     if !len(a:table_path)
--         return []
--     endif
--     let records = s:try_read_index(s:rainbow_table_index)
--     for record in records
--         if len(record) >= 3 && record[0] == a:table_path
--             let delim = s:index_decode_delim(record[1])
--             let policy = record[2]
--             let comment_prefix = len(record) > 3 ? record[3] : s:get_auto_comment_prefix()
--             if comment_prefix == '@auto_comment_prefix@'
--                 let comment_prefix = s:get_auto_comment_prefix()
--             endif
--             return [delim, policy, comment_prefix]
--         endif
--     endfor
--     return []
-- endfunc
local function get_table_record(table_path)
	if #table_path == 0 then
		return {}
	end
	local records = try_read_index(rainbow_table_index)
	for _, record in ipairs(records) do
		if #record >= 3 and record[1] == table_path then
			local delim = index_encode_delim(record[2])
			local policy = record[3]
			local comment_prefix
			if #record > 3 then -- todo port correctly
				comment_prefix = record[4]
			else
				comment_prefix = get_auto_comment_prefix()
			end
			if comment_prefix == '@auto_comment_prefix@' then
				comment_prefix = get_auto_comment_prefix()
			end
			return { delim, policy, comment_prefix }
		end
	end
	return {}
end

-- func! s:string_to_hex(src)
--     let result = ''
--     for nt in range(len(a:src))
--         let result .= printf("%x", char2nr(a:src[nt]))
--     endfor
--     return result
-- endfunc
local function string_to_hex(src)
	local bytes = { string.byte(src, 1, #src) }
	local result = ''
	for _, b in ipairs(bytes) do
		result = result .. string.format('%x', b)
	end
	return result
end

-- func! s:hex_to_string(src)
--     let result = ''
--     let nt = 0
--     while nt < len(a:src)
--         let result .= nr2char(str2nr(strpart(a:src, nt, 2), 16))
--         let nt += 2
--     endwhile
--     return result
-- endfunc
local function hex_to_string(src)
	local result = ''
	for nt = 1, #src, 2 do
		-- todo later when i'm less lazy
		result = result .. vim.fn.nr2char(vim.fn.str2nr(string.sub(src, nt, nt + 1), 16))
	end
	return result
end

-- func! rainbow_csv#dialect_to_ft(delim, policy, comment_prefix)
--     for [ft, delim_policy] in items(s:named_syntax_map)
--         if a:delim == delim_policy[0] && a:policy == delim_policy[1] && a:comment_prefix == delim_policy[2]
--             return ft
--         endif
--     endfor
--     return join(['rcsv', s:string_to_hex(a:delim), a:policy, s:string_to_hex(a:comment_prefix)], '_')
-- endfunc
M.dialect_to_ft = function(delim, policy, comment_prefix)
	for ft, delim_policy in pairs(named_syntax_map) do
		if delim == delim_policy[1] and policy == delim_policy[2] and comment_prefix == delim_policy[3] then
			return ft
		end
	end
	return lua_join({ 'rcsv', string_to_hex(delim), policy, string_to_hex(comment_prefix) }, '_')
end


-- func! rainbow_csv#ft_to_dialect(ft_val)
--     if has_key(s:named_syntax_map, a:ft_val)
--         return s:named_syntax_map[a:ft_val]
--     endif
--     let ft_parts = split(a:ft_val, '_')
--     if len(ft_parts) < 3 || ft_parts[0] != 'rcsv'
--         return ['', 'monocolumn', '']
--     endif
--     let comment_prefix = len(ft_parts) == 4 ? s:hex_to_string(ft_parts[3]) : ''
--     return [s:hex_to_string(ft_parts[1]), ft_parts[2], comment_prefix]
-- endfunc
M.ft_to_dialect = function(ft_val)
	if named_syntax_map[ft_val] then
		return named_syntax_map[ft_val]
	end
	local ft_parts = vim.fn.split(ft_val, '_')
	if #ft_parts < 3 or ft_parts[1] ~= 'rcsv' then
		return { '', 'monocolumn', '' }
	end
	local comment_prefix
	if #ft_parts == 4 then
		comment_prefix = hex_to_string(ft_parts[4])
	else
		comment_prefix = ''
	end
	return { hex_to_string(ft_parts[2]), ft_parts[3], comment_prefix }
end


-- func! rainbow_csv#ensure_syntax_exists(rainbow_ft, delim, policy, comment_prefix)
--     if a:policy == 'quoted'
--         let syntax_lines = rainbow_csv#generate_escaped_rainbow_syntax(a:delim)
--     elseif a:policy == 'quoted_rfc'
--         let syntax_lines = rainbow_csv#generate_escaped_rfc_rainbow_syntax(a:delim)
--     elseif a:policy == 'simple'
--         let syntax_lines = rainbow_csv#generate_rainbow_syntax(a:delim)
--     elseif a:policy == 'whitespace'
--         let syntax_lines = rainbow_csv#generate_whitespace_syntax()
--     else
--         echoerr 'bad delim policy: ' . a:policy
--     endif
--     if a:comment_prefix != ''
--         let regex_comment_prefix = escape(a:comment_prefix, s:magic_chars)
--         call add(syntax_lines, 'syntax match Comment /^' . regex_comment_prefix . '.*$/')
--     endif
--     let syntax_file_path = s:script_folder_path . '/syntax/' . a:rainbow_ft . '.vim'
--     call writefile(syntax_lines, syntax_file_path)
-- endfunc
M.ensure_syntax_exists = function(rainbow_ft, delim, policy, comment_prefix)
	local syntax_lines = {}
	if policy == 'quoted' then
		syntax_lines = M.generate_escaped_rainbow_syntax(delim)
	elseif policy == 'quoted_rfc' then
		syntax_lines = M.generate_escaped_rfc_rainbow_syntax(delim)
	elseif policy == 'simple' then
		syntax_lines = M.generate_rainbow_syntax(delim)
	elseif policy == 'whitespace' then
		syntax_lines = M.generate_whitespace_syntax()
	else
		vim.cmd.echoerr('bad delim policy: ' .. 'policy')
	end
	if comment_prefix ~= '' then
		local regex_comment_prefix = lua_escape(comment_prefix, magic_chars)
		table.insert(syntax_lines, 'syntax match Comment /^' .. regex_comment_prefix .. '.*$/')
	end
	local syntax_file_path = script_folder_path .. '/syntax/' .. rainbow_ft .. '.vim'
	vim.fn.writefile(syntax_lines, syntax_file_path)
end


-- func! rainbow_csv#generate_named_dialects() " This is an externally-invoked function which is used to pre-generate well-known syntax files
--     for [ft, delim_policy] in items(s:named_syntax_map)
--         call rainbow_csv#ensure_syntax_exists(ft, delim_policy[0], delim_policy[1], delim_policy[2])
--     endfor
-- endfunc
M.generate_named_dialects = function()
	for ft, delim_policy in pairs(named_syntax_map) do
		M.ensure_syntax_exists(ft, delim_policy[1], delim_policy[2], delim_policy[3])
	end
end


-- func! rainbow_csv#get_current_dialect()
--     " Using &syntax instead of &ft here because they can have different value i.e. after manual syntax assignment set syntax = ...
--     let current_ft = &syntax
--     return rainbow_csv#ft_to_dialect(current_ft)
-- endfunc
M.get_current_dialect = function()
	-- todo this should be fine but might not be
	return M.ft_to_dialect(vim.o.filetype)
end


-- func! rainbow_csv#is_rainbow_table()
--     return rainbow_csv#get_current_dialect()[1] != 'monocolumn'
-- endfunc
M.is_rainbow_table = function()
	return M.get_current_dialect()[2] ~= 'monocolumn'
end


-- func! rainbow_csv#is_rainbow_table_or_was_just_disabled()
--     return (exists("b:rainbow_features_enabled") && b:rainbow_features_enabled == 1)
-- endfunc
M.is_rainbow_table_or_was_just_disabled = function()
	return vim.b.rainbow_features_enabled == true
end


-- func! s:get_meta_language()
--     let lang_lw = 'python'
--     if exists("g:rbql_meta_language")
--         let lang_lw = tolower(g:rbql_meta_language)
--     endif
--     if exists("g:rbql_backend_language")
--         let lang_lw = tolower(g:rbql_backend_language)
--     endif
--     if lang_lw == 'javascript'
--         let lang_lw = 'js'
--     endif
--     return lang_lw
-- endfunc
local function get_meta_language()
	local lang_lw = 'python'
	if vim.g.rbql_meta_language ~= nil then
		lang_lw = string.lower(vim.g.rbql_meta_language)
	end
	if vim.g.rbql_backend_language ~= nil then
		lang_lw = string.lower(vim.g.rbql_backend_language)
	end
	if lang_lw == 'javascript' then
		lang_lw = 'js'
	end
	return lang_lw
end

-- func! s:has_python_27()
--     if !has("python")
--         return 0
--     endif
--     py import sys
--     if pyeval('sys.version_info[1]') < 7
--         return 0
--     endif
--     return 1
-- endfunc
local function has_python_27()
	-- todo verify this
	if vim.fn.has('python') ~= 1 then
		return false
	end
	vim.cmd('py import sys')
	if vim.fn.pyeval('sys.version_info[1]') < 7 then
		return false
	end
	return true
end

-- func! s:read_virtual_header(delim, policy)
--     " TODO rename and refactor into try_set_virtual_header() - without parameters, get delim and policy from the current filetype
--     let table_path = resolve(expand("%:p"))
--     let headerName = table_path . '.header'
--     if (!filereadable(headerName))
--         return []
--     endif
--     let lines = readfile(headerName, '', 1)
--     if (!len(lines))
--         return []
--     endif
--     let line = lines[0]
--     let names = []
--     if a:policy == 'monocolumn'
--         let names = [line]
--     else
--         let regex_delim = escape(a:delim, s:magic_chars)
--         let names = split(line, regex_delim)
--     endif
--     return names
-- endfunc
local function read_virtual_header(delim, policy)
	local table_path = vim.fn.resolve(vim.fn.expand('%:p'))
	local headerName = table_path .. '.header'
	if vim.fn.filereadable(headerName) == 0 then
		return {}
	end
	local lines = vim.fn.readfile(headerName, '', 1)
	if #lines == 0 then
		return {}
	end
	local line = lines[1]
	local names = {}
	if policy == 'monocolumn' then
		names = { line } -- todo correct?
	else
		local regex_delim = lua_escape(delim, magic_chars)
		names = vim.fn.split(line, regex_delim)
	end
	return names
end

-- func! rainbow_csv#dbg_set_system_python_interpreter(interpreter)
--     let s:system_python_interpreter = a:interpreter
-- endfunction
M.dbg_set_system_python_interpreter = function(interpreter)
	system_python_interpreter = interpreter
end


-- func! rainbow_csv#find_python_interpreter()
--     " Checking `python3` first, because `python` could be theorethically linked to python 2.6
--     let py3_version = tolower(system('python3 --version'))
--     if (v:shell_error == 0 && match(py3_version, 'python 3\.') == 0)
--         let s:system_python_interpreter = 'python3'
--         return s:system_python_interpreter
--     endif
--     let py_version = tolower(system('python --version'))
--     if (v:shell_error == 0 && (match(py_version, 'python 2\.7') == 0 || match(py_version, 'python 3\.') == 0))
--         let s:system_python_interpreter = 'python'
--         return s:system_python_interpreter
--     endif
--     let s:system_python_interpreter = ''
--     return s:system_python_interpreter
-- endfunc
M.find_python_interpreter = function()
	local ret = vim.api.nvim_exec([[
        func! s:find_python_interpreter()
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
        echo s:find_python_interpreter()
    ]], true)
	system_python_interpreter = ret
	return system_python_interpreter
end

-- function! s:py_source_escape(src)
--     " Strings in 'substitute' must follow esoteric rules, see `:help substitute()`
--     let dst = substitute(a:src, '\\', '\\\\', "g")
--     let dst = substitute(dst, '\t', '\\t', "g")
--     let dst = substitute(dst, '"', '\\"', "g")
--     return dst
-- endfunc
local function py_source_escape(src)
	-- todo these string literals are not equivalent to the vimscript ones
	local dst = string.gsub(src, [[\\]], [[\\\\]])
	dst = string.gsub(dst, [[\t]], [[\\t]])
	dst = string.gsub(dst, '"', [[\\"]])
	return dst
end

-- function! s:char_class_escape(src)
--     if a:src == ']'
--         return '\]'
--     endif
--     if a:src == '\'
--         return '\\'
--     endif
--     return a:src
-- endfunc
local function char_class_escape(src)
	if src == ']' then
		return '\\]'
	end
	if src == '\\' then
		return '\\\\'
	end
	return src
end

-- function! s:test_coverage()
--     if !exists("g:rbql_dbg_test_coverage")
--         return 0
--     endif
--     return reltime()[1] % 2
-- endfunc
local function test_coverage()
	if vim.g.rbql_dbg_test_coverage ~= true then
		return false
	end
	return vim.fn.reltime()[2] % 2 == 1
end

-- function! s:EnsureJavaScriptInitialization()
--     if (s:js_env_initialized)
--         return 1
--     endif
--     let js_version = tolower(system('node --version'))
--     if (v:shell_error != 0)
--         return 0
--     endif
--     let s:js_env_initialized = 1
--     return 1
-- endfunction
local function EnsureJavaScriptInitialization()
	if js_env_initialized then
		return true
	end
	if os.execute('node --version') ~= 0 then
		return false
	end
	js_env_initialized = true
	return true
end

-- function! s:EnsurePythonInitialization()
--     if (s:python_env_initialized)
--         return 1
--     endif
--     let py_home_dir = s:script_folder_path . '/rbql_core'
--     let py_home_dir = s:py_source_escape(py_home_dir)
--     if has("python3") && !s:use_system_python() && !s:test_coverage()
--         py3 import sys
--         py3 import vim
--         exe 'python3 sys.path.insert(0, "' . py_home_dir . '")'
--         py3 import vim_rbql
--     elseif s:has_python_27() && !s:use_system_python() && !s:test_coverage()
--         py import sys
--         py import vim
--         exe 'python sys.path.insert(0, "' . py_home_dir . '")'
--         py import vim_rbql
--     else
--         call rainbow_csv#find_python_interpreter()
--         if s:system_python_interpreter == ""
--             return 0
--         endif
--     endif
--     let s:python_env_initialized = 1
--     return 1
-- endfunction
local function EnsurePythonInitialization()
	if python_env_initialized then
		return true
	end
	local py_home_dir = py_source_escape(script_folder_path .. '/rbql_core')
	if vim.fn.has('python3') == 1 and not use_system_python() and not test_coverage() then
		vim.cmd('py3 import sys')
		vim.cmd('py3 import vim')
		vim.cmd("exe 'python3 sys.path.insert(0, \"'" .. py_home_dir .. "\")'")
		vim.cmd('py3 import vim_rbql')
	elseif has_python_27() and not use_system_python() and not test_coverage() then
		vim.cmd('py import sys')
		vim.cmd('py import vim')
		vim.cmd("exe 'python sys.path.insert(0, \"'" .. py_home_dir .. "\")'")
		vim.cmd('py import vim_rbql')
	else
		M.find_python_interpreter()
		if system_python_interpreter == '' then
			return false
		end
	end
	python_env_initialized = true
	return true
end

-- func! s:ensure_storage_exists()
--     if !isdirectory(s:rb_storage_dir)
--         call mkdir(s:rb_storage_dir, "p")
--     endif
-- endfunc
local function ensure_storage_exists()
	if vim.fn.isdirectory(rb_storage_dir) == 0 then
		vim.fn.mkdir(rb_storage_dir, 'p')
	end
end

-- func! rainbow_csv#rstrip(line)
--     let result = a:line
--     if len(result) && result[len(result) - 1] == "\n"
--         let result = strpart(result, 0, len(result) - 1)
--     endif
--     if len(result) && result[len(result) - 1] == "\r"
--         let result = strpart(result, 0, len(result) - 1)
--     endif
--     return result
-- endfunc
M.rstrip = function(line)
	-- todo hot call
	local result = line
	if #result > 0 and string.sub(result, -1) == '\n' then
		result = string.sub(result, 1, -2)
	end
	if #result > 0 and string.sub(result, -1) == '\r' then
		result = string.sub(result, 1, -2)
	end
	return result
end


-- function! rainbow_csv#strip_spaces(input_string)
--     return substitute(a:input_string, '^ *\(.\{-}\) *$', '\1', '')
-- endfunction
M.strip_spaces = function(input_string)
	local lstrip = string.gsub(input_string, '^ *([^ ])', '%1', 1)
	return string.gsub(lstrip, '([^ ]) *$', '%1', 1)
end


-- func! rainbow_csv#unescape_quoted_fields(src)
--     let res = a:src
--     for nt in range(len(res))
--         let res[nt] = rainbow_csv#strip_spaces(res[nt])
--         if len(res[nt]) >= 2 && res[nt][0] == '"'
--             let res[nt] = strpart(res[nt], 1, len(res[nt]) - 2)
--         endif
--         let res[nt] = substitute(res[nt], '""', '"', 'g')
--     endfor
--     return res
-- endfunc
M.unescape_quoted_fields = function(src)
	-- todo mutates parameter
	local res = src
	for nt, _ in ipairs(res) do
		res[nt] = M.strip_spaces(res[nt])
		if #res[nt] >= 2 and string.sub(res[nt], 1, 1) == '"' then
			res[nt] = lua_strpart(res[nt], 1, #res[nt] - 2)
		end
		res[nt] = string.gsub(res[nt], '""', '"')
	end
	return res
end

-- vim.cmd([[
-- func! rainbow_csv#preserving_quoted_split(line, delim)
--     let src = a:line
--     if stridx(src, '"') == -1
--         " Optimization for majority of lines
--         let regex_delim = escape(a:delim, s:magic_chars)
--         return [split(src, regex_delim, 1), 0]
--     endif
--     let result = []
--     let cidx = 0
--     let has_warning = 0
--     while cidx < len(src)
--         let uidx = cidx
--         while uidx < len(src) && src[uidx] == ' '
--             let uidx += 1
--         endwhile
--         if src[uidx] == '"'
--             let uidx += 1
--             while 1
--                 let uidx = stridx(src, '"', uidx)
--                 if uidx == -1
--                     call add(result, strpart(src, cidx))
--                     return [result, 1]
--                 endif
--                 let uidx += 1
--                 if uidx < len(src) && src[uidx] == '"'
--                     let uidx += 1
--                     continue
--                 endif
--                 while uidx < len(src) && src[uidx] == ' '
--                     let uidx += 1
--                 endwhile
--                 if uidx >= len(src) || src[uidx] == a:delim
--                     call add(result, strpart(src, cidx, uidx - cidx))
--                     let cidx = uidx + 1
--                     break
--                 endif
--                 let has_warning = 1
--             endwhile
--         else
--             let uidx = stridx(src, a:delim, uidx)
--             if uidx == -1
--                 let uidx = len(src)
--             endif
--             let field = strpart(src, cidx, uidx - cidx)
--             let cidx = uidx + 1
--             call add(result, field)
--             let has_warning = has_warning || stridx(field, '"') != -1
--         endif
--     endwhile
--     if src[len(src) - 1] == a:delim
--         call add(result, '')
--     endif
--     return [result, has_warning]
-- endfunc
-- ]])

M.preserving_quoted_split = function(line, delim)
	-- todo hot function
	local src = line
	if string.find(src, '"') == nil then
		local regex_delim = lua_escape(delim, magic_chars)
		return { vim.fn.split(src, regex_delim, 1), false }
	end
	local result = {}
	local cidx = 0
	local has_warning = false
	while cidx < #src do
		local uidx = cidx
		while uidx < #src and lua_charat(src, uidx) == ' ' do
			uidx = uidx + 1
		end
		if lua_charat(src, uidx) == '"' then
			uidx = uidx + 1
			while true do
				uidx = lua_stridx(src, '"', uidx)
				if uidx == -1 then
					table.insert(result, lua_strpart(src, cidx))
					return { result, true }
				end
				uidx = uidx + 1
				if uidx < #src and lua_charat(src, uidx) == '"' then
					uidx = uidx + 1
					goto continue
				end
				while uidx < #src and lua_charat(src, uidx) == ' ' do
					uidx = uidx + 1
				end
				if uidx >= #src or lua_charat(src, uidx) == delim then
					table.insert(result, lua_strpart(src, cidx, uidx - cidx))
					cidx = uidx + 1
					goto done
				end
				has_warning = true
				::continue::
			end
			::done::
		else
			uidx = lua_stridx(src, delim, uidx)
			if uidx == -1 then
				uidx = #src
			end
			local field = lua_strpart(src, cidx, uidx - cidx)
			cidx = uidx + 1
			table.insert(result, field)
			has_warning = has_warning or string.find(field, '"') ~= nil
		end
	end
	if string.sub(src, -1) == delim then
		table.insert(result, '')
	end
	return { result, has_warning }
end

-- func! rainbow_csv#quoted_split(line, delim)
--     let quoted_fields = rainbow_csv#preserving_quoted_split(a:line, a:delim)[0]
--     let clean_fields = rainbow_csv#unescape_quoted_fields(quoted_fields)
--     return clean_fields
-- endfunc
M.quoted_split = function(line, delim)
	local quoted_fields = M.preserving_quoted_split(line, delim)[1]
	return M.unescape_quoted_fields(quoted_fields)
end


-- func! rainbow_csv#whitespace_split(line, preserve_whitespaces)
--     let result = []
--     let cidx = 0
--     while cidx < len(a:line)
--         let uidx = cidx
--         while uidx < len(a:line) && a:line[uidx] == ' '
--             let uidx += 1
--         endwhile
--         let startidx = uidx
--         while uidx < len(a:line) && a:line[uidx] != ' '
--             let uidx += 1
--         endwhile
--         if uidx == startidx
--             if a:preserve_whitespaces && len(result)
--                 let startidx = cidx
--                 let result[len(result) - 1] = result[len(result) - 1] . strpart(a:line, startidx, uidx - startidx)
--             endif
--             break
--         endif
--         if a:preserve_whitespaces
--             let startidx = len(result) ? cidx + 1 : cidx
--         endif
--         let field = strpart(a:line, startidx, uidx - startidx)
--         let cidx = uidx
--         call add(result, field)
--     endwhile
--     if len(result) == 0
--         if a:preserve_whitespaces
--             call add(result, a:line)
--         else
--             call add(result, '')
--         endif
--     endif
--     return result
-- endfunc
M.whitespace_split = function(line, preserve_whitespaces)
	local result = {}
	local cidx = 0
	while cidx < #line do
		local uidx = cidx
		while uidx < #line and lua_charat(line, uidx) == ' ' do
			uidx = uidx + 1
		end
		local startidx = uidx
		while uidx < #line and lua_charat(line, uidx) ~= ' ' do
			uidx = uidx + 1
		end
		if uidx == startidx then
			if preserve_whitespaces and #result > 0 then
				startidx = cidx
				result[#result] = result[#result] .. lua_strpart(line, startidx, uidx - startidx)
			end
			goto done
		end
		if preserve_whitespaces then
			if #result > 0 then
				startidx = cidx + 1
			else
				startidx = cidx
			end
		end
		local field = lua_strpart(line, startidx, uidx - startidx)
		cidx = uidx
		table.insert(result, field)
	end
	::done::
	if #result == 0 then
		if preserve_whitespaces then
			table.insert(result, line)
		else
			table.insert(result, '')
		end
	end
	return result
end

-- func! rainbow_csv#smart_split(line, delim, policy)
--     let stripped = rainbow_csv#rstrip(a:line)
--     if a:policy == 'monocolumn'
--         return [stripped]
--     elseif a:policy == 'quoted' || a:policy == 'quoted_rfc'
--         return rainbow_csv#quoted_split(stripped, a:delim)
--     elseif a:policy == 'simple'
--         let regex_delim = escape(a:delim, s:magic_chars)
--         return split(stripped, regex_delim, 1)
--     elseif a:policy == 'whitespace'
--         return rainbow_csv#whitespace_split(a:line, 0)
--     else
--         echoerr 'bad delim policy'
--     endif
-- endfunc
M.smart_split = function(line, delim, policy)
	-- todo hot function
	local stripped = M.rstrip(line)
	if policy == 'monocolumn' then
		return stripped
	elseif policy == 'quoted' or policy == 'quoted_rfc' then
		return M.quoted_split(stripped, delim)
	elseif policy == 'simple' then
		local regex_delim = lua_escape(delim, magic_chars)
		return vim.fn.split(stripped, regex_delim, 1) -- todo maybe port split()
	elseif policy == 'whitespace' then
		return M.whitespace_split(line, false)
	else
		vim.cmd("echoerr'bad delim policy'")
	end
end


-- func! rainbow_csv#preserving_smart_split(line, delim, policy)
--     let stripped = rainbow_csv#rstrip(a:line)
--     if a:policy == 'monocolumn'
--         return [[stripped], 0]
--     elseif a:policy == 'quoted' || a:policy == 'quoted_rfc'
--         return rainbow_csv#preserving_quoted_split(stripped, a:delim)
--     elseif a:policy == 'simple'
--         let regex_delim = escape(a:delim, s:magic_chars)
--         return [split(stripped, regex_delim, 1), 0]
--     elseif a:policy == 'whitespace'
--         return [rainbow_csv#whitespace_split(a:line, 1), 0]
--     else
--         echoerr 'bad delim policy'
--     endif
-- endfunc
M.preserving_smart_split = function(line, delim, policy)
	-- todo hot function
	local stripped = M.rstrip(line)
	if policy == 'monocolumn' then
		return { { stripped }, false }
	elseif policy == 'quoted' or policy == 'quoted_rfc' then
		return M.preserving_quoted_split(stripped, delim)
	elseif policy == 'simple' then
		local regex_delim = lua_escape(delim, magic_chars)
		return { vim.fn.split(stripped, regex_delim, 1), false }
	elseif policy == 'whitespace' then
		return { M.whitespace_split(line, true), false }
	else
		vim.cmd("echoerr 'bad delim policy'")
	end
end


-- func! rainbow_csv#csv_lint()
--     let [delim, policy, comment_prefix] = rainbow_csv#get_current_dialect()
--     if policy == 'monocolumn'
--         echoerr "CSVLint is available only for highlighted CSV files"
--         return
--     endif
--     if policy == 'quoted_rfc'
--         " TODO implement
--         echoerr "CSVLint is not implemented yet for rfc_csv"
--         return
--     endif
--     let lastLineNo = line("$")
--     let num_fields = 0
--     for linenum in range(1, lastLineNo)
--         let line = getline(linenum)
--         if a:comment_prefix != '' && stridx(line, a:comment_prefix) == 0 " Using stridx is less efficient than using 'startswith', since we try to match at every position, but vimscript doesn't have 'startswith'
--             continue
--         endif
--         let [fields, has_warning] = rainbow_csv#preserving_smart_split(line, delim, policy)
--         if has_warning
--             echoerr printf("Line %s has formatting error: double quote chars are not consistent", linenum)
--             return
--         endif
--         let num_fields_cur = len(fields)
--         if !num_fields
--             let num_fields = num_fields_cur
--         endif
--         if (num_fields != num_fields_cur)
--             echoerr printf("Number of fields is not consistent: e.g. line 1 has %s fields, and line %s has %s fields", num_fields, linenum, num_fields_cur)
--             return
--         endif
--     endfor
--     echomsg "CSVLint: OK"
-- endfunc
M.csv_lint = function()
	local delim, policy, comment_prefix = unpack(M.get_current_dialect())
	if policy == 'monocolumn' then
		vim.cmd('echoerr "CSVLint is available only for highlighted CSV files"')
		return
	elseif policy == 'quoted_rfc' then
		-- TODO implement
		vim.cmd('echoerr "CSVLint is not implemented yet for rfc_csv"')
		return
	end
	local lastLineNo = vim.fn.line('$')
	local num_fields = 0
	for linenum = 1, lastLineNo, 1 do
		local line = vim.fn.getline(linenum)
		if comment_prefix ~= '' and lua_stridx(line, comment_prefix) == 0 then
			goto next
		end
		local fields, has_warning = unpack(M.preserving_smart_split(line, delim, policy))
		if has_warning then
			vim.cmd('echoerr "Line ' .. linenum .. ' has formatting error: double quote chars are not consistent"')
			return
		end
		local num_fields_cur = #fields
		if num_fields == 0 then
			num_fields = num_fields_cur
		end
		if num_fields ~= num_fields_cur then
			vim.cmd('echoerr "Number of fields is not consistent: e.g. line 1 has ' ..
				num_fields .. ' fields, and line ' .. linenum .. ' has ' .. num_fields_cur .. ' fields"')
			return
		end
		::next::
	end
	vim.cmd('echomsg "CSVLint: OK"')
end

-- vim.api.nvim_exec([[
-- func! rainbow_csv#update_subcomponent_stats(field, is_first_line, max_field_components_lens)
--     " Extract overall field length and length of integer and fractional parts of the field if it represents a number.
--     " Here `max_field_components_lens` is a tuple: (max_field_length, max_integer_part_length, max_fractional_part_length)
--     let field_length = strdisplaywidth(a:field)
--     if field_length > a:max_field_components_lens[0]
--         let a:max_field_components_lens[0] = field_length
--     endif
--     if a:max_field_components_lens[1] == s:non_numeric
--         " Column is not a number, early return.
--         return
--     endif
--     let pos = match(a:field, s:number_regex)
--     if pos == -1
--         if !a:is_first_line && field_length " Checking field_length here allows numeric columns to have some of the fields empty.
--             " We only mark the column as non-header if we know that this is not a header line.
--             let a:max_field_components_lens[1] = s:non_numeric
--             let a:max_field_components_lens[2] = s:non_numeric
--         endif
--         return
--     endif
--     let dot_pos = stridx(a:field, '.')
--     let cur_integer_part_length = dot_pos == -1 ? field_length : dot_pos
--     if cur_integer_part_length > a:max_field_components_lens[1]
--         let a:max_field_components_lens[1] = cur_integer_part_length
--     endif
--     " Here cur_fractional_part_length includes the leading dot too.
--     let cur_fractional_part_length = dot_pos == -1 ? 0 : field_length - dot_pos
--     if cur_fractional_part_length > a:max_field_components_lens[2]
--         let a:max_field_components_lens[2] = cur_fractional_part_length
--     endif
-- endfunc
-- ]])
M.update_subcomponent_stats = function(field, is_first_line, max_field_components_lens)
	-- todo hottest function
	local field_length = vim.fn.strdisplaywidth(field)
	if field_length > max_field_components_lens[1] then
		max_field_components_lens[1] = field_length
	end
	if max_field_components_lens[2] == non_numeric then
		return
	end
	local pos = vim.fn.match(field, number_regex)
	if pos == -1 then
		if not is_first_line and field_length > 0 then
			max_field_components_lens[2] = non_numeric
			max_field_components_lens[3] = non_numeric
		end
		return
	end
	local dot_pos = lua_stridx(field, '.')
	local cur_integer_part_length
	if dot_pos == -1 then
		cur_integer_part_length = field_length
	else
		cur_integer_part_length = dot_pos
	end
	if cur_integer_part_length > max_field_components_lens[2] then
		max_field_components_lens[2] = cur_integer_part_length
	end
	local cur_fractional_part_length
	if dot_pos == -1 then
		cur_fractional_part_length = 0
	else
		cur_fractional_part_length = field_length - dot_pos
	end
	if cur_fractional_part_length > max_field_components_lens[3] then
		max_field_components_lens[3] = cur_fractional_part_length
	end
end


-- vim.api.nvim_exec([[
-- func! s:display_progress_bar(cur_progress_pos)
--     let progress_display_str = 'Processing... [' . repeat('#', a:cur_progress_pos) . repeat(' ', s:progress_bar_size - a:cur_progress_pos) . ']'
--     redraw | echo progress_display_str
-- endfunc
-- ]])
local function display_progress_bar(cur_progress_pos)
	local progress_display_str = 'Processing... [' ..
			string.rep('#', cur_progress_pos) .. string.rep(' ', progress_bar_size - cur_progress_pos) .. ']'
	vim.cmd('redraw | echo "' .. progress_display_str .. '"')
end

-- vim.api.nvim_exec([[
-- func! rainbow_csv#adjust_column_stats(column_stats)
--     " Ensure that numeric components max widths are consistent with non-numeric (header) width.
--     let adjusted_stats = []
--     for column_stat in a:column_stats
--         if column_stat[1] <= 0
--             let column_stat[1] = -1
--             let column_stat[2] = -1
--         endif
--         if column_stat[1] > 0
--             " The sum of integer and float parts can be bigger than the max width, e.g. here:
--             " value
--             " 0.12
--             " 1234
--             if (column_stat[1] + column_stat[2] > column_stat[0])
--                 let column_stat[0] = column_stat[1] + column_stat[2]
--             endif
--             " This is needed when the header is wider than numeric components and/or their sum.
--             if (column_stat[0] - column_stat[2] > column_stat[1])
--                 let column_stat[1] = column_stat[0] - column_stat[2]
--             endif
--             " Sanity check.
--             if (column_stat[0] != column_stat[1] + column_stat[2])
--                 " Assertion Error, this can never happen.
--                 return []
--             endif
--         endif
--         call add(adjusted_stats, column_stat)
--     endfor
--     return adjusted_stats
-- endfunc
-- ]])
M.adjust_column_stats = function(column_stats)
	local adjusted_stats = {}
	for idx = 1, #column_stats, 1 do
		if column_stats[idx][2] <= 0 then
			column_stats[idx][2] = -1
			column_stats[idx][3] = -1
		end
		if column_stats[idx][2] > 0 then
			if column_stats[idx][2] + column_stats[idx][3] > column_stats[idx][1] then
				column_stats[idx][1] = column_stats[idx][2] + column_stats[idx][3]
			end
			if column_stats[idx][1] - column_stats[idx][3] > column_stats[idx][2] then
				column_stats[idx][2] = column_stats[idx][1] - column_stats[idx][3]
			end
			if column_stats[idx][1] ~= column_stats[idx][2] + column_stats[idx][3] then
				return {}
			end
		end
		table.insert(adjusted_stats, column_stats[idx])
	end
	return adjusted_stats
end


-- vim.api.nvim_exec([[
-- func! s:calc_column_stats(delim, policy, comment_prefix, progress_bucket_size)
--     " Result `column_stats` is a list of (max_total_len, max_int_part_len, max_fractional_part_len) tuples.
--     let column_stats = []
--     let lastLineNo = line("$")
--     let is_first_line = 1
--     for linenum in range(1, lastLineNo)
--         if (a:progress_bucket_size && linenum % a:progress_bucket_size == 0)
--             let s:align_progress_bar_position = s:align_progress_bar_position + 1
--             call s:display_progress_bar(s:align_progress_bar_position)
--         endif
--         let line = getline(linenum)
--         let [fields, has_warning] = rainbow_csv#preserving_smart_split(line, a:delim, a:policy)
--         if a:comment_prefix != '' && stridx(line, a:comment_prefix) == 0
--             continue
--         endif
--         if has_warning
--             return [column_stats, linenum]
--         endif
--         for fnum in range(len(fields))
--             let field = rainbow_csv#strip_spaces(fields[fnum])
--             if len(column_stats) <= fnum
--                 call add(column_stats, [0, 0, 0])
--             endif
--             call rainbow_csv#update_subcomponent_stats(field, is_first_line, column_stats[fnum])
--         endfor
--         let is_first_line = 0
--     endfor
--     return [column_stats, 0]
-- endfunc
-- ]])
local function calc_column_stats(delim, policy, comment_prefix, progress_bucket_size)
	local column_stats = {}
	local lastLineNo = vim.fn.line('$')
	local is_first_line = true
	for linenum = 1, lastLineNo, 1 do
		if progress_bucket_size > 0 and linenum % progress_bucket_size == 0 then
			align_progress_bar_position = align_progress_bar_position + 1
			display_progress_bar(align_progress_bar_position)
		end
		local line = vim.fn.getline(linenum)
		local fields, has_warning = unpack(M.preserving_smart_split(line, delim, policy))
		if comment_prefix ~= '' and lua_stridx(line, comment_prefix) == 0 then
			goto next
		end
		if has_warning then
			return { column_stats, linenum }
		end
		for fnum = 1, #fields, 1 do
			local field = M.strip_spaces(fields[fnum])
			if #column_stats <= fnum then
				table.insert(column_stats, { 0, 0, 0 })
			end
			M.update_subcomponent_stats(field, is_first_line, column_stats[fnum])
		end
		is_first_line = false
		::next::
	end
	return { column_stats, 0 }
end

-- vim.api.nvim_exec([[
-- func! rainbow_csv#align_field(field, is_first_line, max_field_components_lens, is_last_column)
--     " Align field, use max() to avoid negative delta_length which can happen theorethically due to async doc edit.
--     let extra_readability_whitespace_length = 1
--     let clean_field = rainbow_csv#strip_spaces(a:field)
--     let field_length = strdisplaywidth(clean_field)
--     if (a:max_field_components_lens[1] == s:non_numeric)
--         let delta_length = a:max_field_components_lens[0] - field_length > 0 ? a:max_field_components_lens[0] - field_length : 0
--         return a:is_last_column ? clean_field : clean_field . repeat(' ', delta_length + extra_readability_whitespace_length)
--     endif
--     if a:is_first_line
--         let pos = match(clean_field, s:number_regex)
--         if pos == -1
--             " The line must be a header - align it using max_width rule.
--             let delta_length = max([a:max_field_components_lens[0] - field_length, 0])
--             return a:is_last_column ? clean_field : clean_field . repeat(' ', delta_length + extra_readability_whitespace_length)
--         endif
--     endif
--     let dot_pos = stridx(clean_field, '.')
--     let cur_integer_part_length = dot_pos == -1 ? field_length : dot_pos
--     " Here cur_fractional_part_length includes the leading dot too.
--     let cur_fractional_part_length = dot_pos == -1 ? 0 : field_length - dot_pos
--     let integer_delta_length = a:max_field_components_lens[1] - cur_integer_part_length > 0 ? a:max_field_components_lens[1] - cur_integer_part_length : 0
--     let fractional_delta_length = a:max_field_components_lens[2] - cur_fractional_part_length > 0 ? a:max_field_components_lens[2] - cur_fractional_part_length : 0
--     let trailing_spaces = a:is_last_column ? '' : repeat(' ', fractional_delta_length + extra_readability_whitespace_length)
--     return repeat(' ', integer_delta_length) . clean_field . trailing_spaces
-- endfunc
-- ]])
M.align_field = function(field, is_first_line, max_field_components_lens, is_last_column)
	-- todo hottest function
	local extra_readability_whitespace_length = 1
	local clean_field = M.strip_spaces(field)
	local field_length = vim.fn.strdisplaywidth(clean_field) -- todo hot code, maybe refactor
	if max_field_components_lens[2] == non_numeric then
		local delta_length
		if max_field_components_lens[1] - field_length > 0 then
			delta_length = max_field_components_lens[1] - field_length
		else
			delta_length = 0
		end
		if is_last_column then
			return clean_field
		else
			return clean_field .. string.rep(' ', delta_length + extra_readability_whitespace_length)
		end
	end
	if is_first_line then
		local pos = vim.fn.match(clean_field, number_regex)
		if pos == -1 then
			local delta_length = vim.fn.max({ max_field_components_lens[1] - field_length, 0 })
			if is_last_column then
				return clean_field
			else
				return clean_field .. string.rep(' ', delta_length + extra_readability_whitespace_length)
			end
		end
	end
	local dot_pos = lua_stridx(clean_field, '.')
	local cur_integer_part_length
	if dot_pos == -1 then
		cur_integer_part_length = field_length
	else
		cur_integer_part_length = dot_pos
	end
	local cur_fractional_part_length
	if dot_pos == -1 then
		cur_fractional_part_length = 0
	else
		cur_fractional_part_length = field_length - dot_pos
	end
	local integer_delta_length
	if max_field_components_lens[2] - cur_integer_part_length > 0 then
		integer_delta_length = max_field_components_lens[2] - cur_integer_part_length
	else
		integer_delta_length = 0
	end
	local fractional_delta_length
	if max_field_components_lens[3] - cur_fractional_part_length > 0 then
		fractional_delta_length = max_field_components_lens[3] - cur_fractional_part_length
	else
		fractional_delta_length = 0
	end
	local trailing_spaces
	if is_last_column then
		trailing_spaces = ''
	else
		trailing_spaces = string.rep(' ', fractional_delta_length + extra_readability_whitespace_length)
	end
	return string.rep(' ', integer_delta_length) .. clean_field .. trailing_spaces
end

-- vim.api.nvim_exec([[
-- func! rainbow_csv#csv_align()
--     " The first (statistic) pass of the function takes about 40% of runtime, the second (actual align) pass around 60% of runtime.
--     " Numeric-aware logic by itself adds about 50% runtime compared to the basic string-based field width alignment
--     " If there are lot of numeric columns this can additionally increase runtime by another 50% or more.
--     let show_progress_bar = wordcount()['bytes'] > 200000
--     let [delim, policy, comment_prefix] = rainbow_csv#get_current_dialect()
--     if policy == 'monocolumn'
--         echoerr "RainbowAlign is available only for highlighted CSV files"
--         return
--     endif
--     if policy == 'quoted_rfc'
--         echoerr 'RainbowAlign not available for "rfc_csv" filetypes, consider using "csv" instead'
--         return
--     endif
--     let lastLineNo = line("$")
--     let progress_bucket_size = (lastLineNo * 2) / s:progress_bar_size " multiply by 2 because we have two passes.
--     if !show_progress_bar || progress_bucket_size < 10
--         let progress_bucket_size = 0
--     endif
--     let s:align_progress_bar_position = 0
--     let [column_stats, first_failed_line] = s:calc_column_stats(delim, policy, comment_prefix, progress_bucket_size)
--     if first_failed_line != 0
--         echoerr 'Unable to allign: Inconsistent double quotes at line ' . first_failed_line
--         return
--     endif
--     let column_stats = rainbow_csv#adjust_column_stats(column_stats)
--     if !len(column_stats)
--         echoerr 'Unable to allign: Internal Rainbow CSV Error'
--         return
--     endif
--     let has_edit = 0
--     let is_first_line = 1
--     for linenum in range(1, lastLineNo)
--         if (progress_bucket_size && linenum % progress_bucket_size == 0)
--             let s:align_progress_bar_position = s:align_progress_bar_position + 1
--             call s:display_progress_bar(s:align_progress_bar_position)
--         endif
--         let has_line_edit = 0
--         let line = getline(linenum)
--         if comment_prefix != '' && stridx(line, comment_prefix) == 0
--             continue
--         endif
--         let fields = rainbow_csv#preserving_smart_split(line, delim, policy)[0]
--         for fnum in range(len(fields))
--             if fnum >= len(column_stats)
--                 break " Should never happen
--             endif
--             let is_last_column = fnum + 1 == len(column_stats)
--             let field = rainbow_csv#align_field(fields[fnum], is_first_line, column_stats[fnum], is_last_column)
--             if fields[fnum] != field
--                 let fields[fnum] = field
--                 let has_line_edit = 1
--             endif
--         endfor
--         if has_line_edit
--             let updated_line = join(fields, delim)
--             call setline(linenum, updated_line)
--             let has_edit = 1
--         endif
--         let is_first_line = 0
--     endfor
--     if !has_edit
--         echoerr "File is already aligned"
--     endif
-- endfunc
-- ]])
M.csv_align = function()
	local show_progress_bar = vim.fn.wordcount()['bytes'] > 200000
	local delim, policy, comment_prefix = unpack(M.get_current_dialect())
	if policy == 'monocolumn' then
		vim.cmd('echoerr "RainbowAlign is available only for highlighted CSV files"')
		return
	elseif policy == 'quoted_rfc' then
		vim.cmd('echoerr "RainbowAlign not available for \"rfc_csv\" filetypes, consider using \"csv\" instead"')
		return
	end
	local lastLineNo = vim.fn.line('$')
	local progress_bucket_size = (lastLineNo * 2) / progress_bar_size
	if not show_progress_bar or progress_bucket_size < 10 then
		progress_bucket_size = 0
	end
	align_progress_bar_position = 0
	local column_stats, first_failed_line = unpack(calc_column_stats(delim, policy, comment_prefix, progress_bucket_size))
	if first_failed_line ~= 0 then
		vim.cmd('echoerr "Unable to align: Inconsistent double quotes at line ' .. first_failed_line .. '"')
		return
	end
	column_stats = M.adjust_column_stats(column_stats)
	if #column_stats == 0 then
		vim.cmd('echoerr "Unable to align: Internal Rainbow CSV Error"')
		return
	end
	local has_edit = false
	local is_first_line = true
	for linenum = 1, lastLineNo, 1 do
		if progress_bucket_size > 0 and linenum % progress_bucket_size == 0 then
			align_progress_bar_position = align_progress_bar_position + 1
			display_progress_bar(align_progress_bar_position)
		end
		local has_line_edit = false
		local line = vim.fn.getline(linenum)
		if comment_prefix ~= '' and lua_stridx(line, comment_prefix) == 0 then
			goto next
		end
		local fields = M.preserving_smart_split(line, delim, policy)[1]
		for fnum = 1, #fields, 1 do
			if fnum > #column_stats then
				vim.notify('bad off by one in csv_align', vim.log.levels.ERROR, {})
				goto ibreak
			end
			local is_last_column = fnum == #column_stats
			local field = M.align_field(fields[fnum], is_first_line, column_stats[fnum], is_last_column)
			if fields[fnum] ~= field then
				fields[fnum] = field
				has_line_edit = true
			end
		end
		::ibreak::
		if has_line_edit then
			local updated_line = lua_join(fields, delim)
			vim.fn.setline(linenum, updated_line)
			has_edit = true
		end
		is_first_line = false
		::next::
	end
	if not has_edit then
		vim.cmd('echoerr "File is already aligned"')
	end
end


-- vim.api.nvim_exec([[
-- func! rainbow_csv#csv_shrink()
--     let [delim, policy, comment_prefix] = rainbow_csv#get_current_dialect()
--     if policy == 'monocolumn'
--         echoerr "RainbowShrink is available only for highlighted CSV files"
--         return
--     endif
--     if policy == 'quoted_rfc'
--         echoerr 'RainbowShrink not available for "rfc_csv" filetypes, consider using "csv" instead'
--         return
--     endif
--     let lastLineNo = line("$")
--     let has_edit = 0
--     let show_progress_bar = wordcount()['bytes'] > 200000
--     let progress_bucket_size = lastLineNo / s:progress_bar_size
--     if !show_progress_bar || progress_bucket_size < 10
--         let progress_bucket_size = 0
--     endif
--     let s:align_progress_bar_position = 0
--     for linenum in range(1, lastLineNo)
--         if (progress_bucket_size && linenum % progress_bucket_size == 0)
--             let s:align_progress_bar_position = s:align_progress_bar_position + 1
--             call s:display_progress_bar(s:align_progress_bar_position)
--         endif
--         let has_line_edit = 0
--         let line = getline(linenum)
--         if comment_prefix != '' && stridx(line, comment_prefix) == 0
--             continue
--         endif
--         let [fields, has_warning] = rainbow_csv#preserving_smart_split(line, delim, policy)
--         if has_warning
--             echoerr 'Unable to shrink: Inconsistent double quotes at line ' . linenum
--             return
--         endif
--         for fnum in range(len(fields))
--             let field = rainbow_csv#strip_spaces(fields[fnum])
--             if fields[fnum] != field
--                 let fields[fnum] = field
--                 let has_line_edit = 1
--             endif
--         endfor
--         if has_line_edit
--             let updated_line = join(fields, delim)
--             call setline(linenum, updated_line)
--             let has_edit = 1
--         endif
--     endfor
--     if !has_edit
--         echoerr "File is already shrinked"
--     endif
-- endfunc
-- ]])
M.csv_shrink = function()
	local delim, policy, comment_prefix = unpack(M.get_current_dialect())
	if policy == 'monocolumn' then
		vim.cmd('echoerr "RainbowAlign is available only for highlighted CSV files"')
		return
	elseif policy == 'quoted_rfc' then
		vim.cmd('echoerr "RainbowAlign not available for \"rfc_csv\" filetypes, consider using \"csv\" instead"')
		return
	end
	local lastLineNo = vim.fn.line('$')
	local has_edit = false
	local show_progress_bar = vim.fn.wordcount()['bytes'] > 200000
	local progress_bucket_size = (lastLineNo * 2) / progress_bar_size
	if not show_progress_bar or progress_bucket_size < 10 then
		progress_bucket_size = 0
	end
	align_progress_bar_position = 0
	for linenum = 1, lastLineNo, 1 do
		if progress_bucket_size > 0 and linenum % progress_bucket_size == 0 then
			align_progress_bar_position = align_progress_bar_position + 1
			display_progress_bar(align_progress_bar_position)
		end
		local has_line_edit = false
		local line = vim.fn.getline(linenum)
		if comment_prefix ~= '' and lua_stridx(line, comment_prefix) == 0 then
			goto next
		end
		local fields, has_warning = unpack(M.preserving_smart_split(line, delim, policy))
		if has_warning then
			vim.cmd('echoerr "Unable to shrink: Inconsistent double quotes at line ' .. linenum .. '"')
			return
		end
		for fnum = 1, #fields, 1 do
			local field = M.strip_spaces(fields[fnum])
			if fields[fnum] ~= field then
				fields[fnum] = field
				has_line_edit = true
			end
		end
		if has_line_edit then
			local updated_line = lua_join(fields, delim)
			vim.fn.setline(linenum, updated_line)
			has_edit = true
		end
		::next::
	end
	if not has_edit then
		vim.cmd('echoerr "File is already shrinked"')
	end
end


-- vim.api.nvim_exec([[
-- func! rainbow_csv#get_csv_header(delim, policy, comment_prefix)
--     if exists("b:cached_virtual_header") && len(b:cached_virtual_header)
--         return b:cached_virtual_header
--     endif
--     let max_lines_to_check = min([line("$"), 20])
--     for linenum in range(1, max_lines_to_check)
--         let line = getline(linenum)
--         if a:comment_prefix != '' && stridx(line, a:comment_prefix) == 0
--             continue
--         endif
--         return rainbow_csv#smart_split(line, a:delim, a:policy)
--     endfor
--     return []
-- endfunc
-- ]])
M.get_csv_header = function(delim, policy, comment_prefix)
	if vim.b.cached_virtual_header ~= nil and #vim.b.cached_virtual_header > 0 then
		return vim.b.cached_virtual_header
	end
	local max_lines_to_check = vim.fn.min({ vim.fn.line("$"), 20 })
	for linenum = 1, max_lines_to_check, 1 do
		local line = vim.fn.getline(linenum)
		if comment_prefix ~= '' and lua_stridx(line, comment_prefix) == 0 then
		else
			return M.smart_split(line, delim, policy)
		end
	end
	return {}
end


-- func! s:get_col_num_single_line(fields, delim, offset)
--     let col_num = 0
--     let kb_pos = col('.')
--     let cpos = a:offset + len(a:fields[col_num]) + len(a:delim)
--     while kb_pos > cpos && col_num + 1 < len(a:fields)
--         let col_num += 1
--         let cpos += len(a:fields[col_num]) + len(a:delim)
--     endwhile
--     return col_num
-- endfunc
local function get_col_num_single_line(fields, delim, offset)
	-- todo dubious
	local col_num = 0
	local kb_pos = vim.fn.col('.')
	local cpos = offset + #fields[col_num + 1] + #delim
	while kb_pos > cpos and col_num + 1 < #fields do
		col_num = col_num + 1
		cpos = cpos + #fields[col_num + 1] + #delim
	end
	return col_num
end

-- vim.cmd([[
-- func! s:do_get_col_num_rfc_lines(cur_line, delim, start_line, end_line, expected_num_fields)
--     let record_lines = getline(a:start_line, a:end_line)
--     let record_str = join(record_lines, "\n")
--     let [fields, has_warning] = rainbow_csv#preserving_smart_split(record_str, a:delim, 'quoted_rfc')
--     if has_warning || len(fields) != a:expected_num_fields
--         return []
--     endif
--     let cursor_line_offset = a:cur_line - a:start_line
--     let current_line_offset = 0
--     let col_num = 0
--     while col_num < len(fields)
--         let current_line_offset += len(split(fields[col_num], "\n", 1)) - 1
--         if current_line_offset >= cursor_line_offset
--             break
--         endif
--         let col_num += 1
--     endwhile
--     if current_line_offset > cursor_line_offset
--         return [fields, col_num]
--     endif
--     if current_line_offset < cursor_line_offset
--         " Should never happen
--         return []
--     endif
--     let length_of_previous_field_segment_on_cursor_line = 0
--     if current_line_offset > 0
--         let length_of_previous_field_segment_on_cursor_line = len(split(fields[col_num], "\n", 1)[-1]) + len(a:delim)
--         if col('.') <= length_of_previous_field_segment_on_cursor_line
--             return [fields, col_num]
--         else
--             let col_num += 1
--         endif
--     endif
--     let col_num = col_num + s:get_col_num_single_line(fields[col_num:], a:delim, length_of_previous_field_segment_on_cursor_line)
--     return [fields, col_num]
-- endfunc
-- ]])
local function do_get_col_num_rfc_lines(cur_line, delim, start_line, end_line, expected_num_fields)
	local record_lines = vim.api.nvim_buf_get_lines(0, start_line, end_line + 1, true) -- todo this impl doesn't match getline()
	local record_str = lua_join(record_lines, '\n')
	local fields, has_warning = unpack(M.preserving_smart_split(record_str, delim, 'quoted_rfc'))
	if has_warning or #fields ~= expected_num_fields then
		return {}
	end
	local cursor_line_offset = cur_line - start_line
	local current_line_offset = 0
	local col_num = 0
	while col_num < #fields do
		current_line_offset = current_line_offset + #vim.fn.split(fields[col_num + 1], '\n', 1) - 1
		if current_line_offset >= cursor_line_offset then
			goto done
		end
		col_num = col_num + 1
	end
	::done::
	if current_line_offset > cursor_line_offset then
		return { fields, col_num }
	end
	if current_line_offset < cursor_line_offset then
		return {}
	end
	local length_of_previous_field_segment_on_cursor_line = 0
	if current_line_offset > 0 then
		local splitcol = vim.fn.split(fields[col_num + 1], '\n', 1)
		length_of_previous_field_segment_on_cursor_line = #splitcol[#splitcol] + #delim
		if vim.fn.col('.') <= length_of_previous_field_segment_on_cursor_line then
			return { fields, col_num }
		else
			col_num = col_num + 1
		end
	end
	col_num = col_num +
			get_col_num_single_line(vim.list_slice(fields, col_num + 1), delim,
				length_of_previous_field_segment_on_cursor_line)
	return { fields, col_num }
end

-- vim.cmd([[
-- func! s:find_unbalanced_lines_around(cur_line)
--     let start_line = -1
--     let end_line = -1
--     let multiline_search_range = exists('g:multiline_search_range') ? g:multiline_search_range : 10
--     let lnmb = max([1, a:cur_line - multiline_search_range])
--     let lnme = min([line('$'), a:cur_line + multiline_search_range])
--     while lnmb < lnme
--         if len(split(getline(lnmb), '"', 1)) % 2 == 0
--             if lnmb < a:cur_line
--                 let start_line = lnmb
--             endif
--             if lnmb > a:cur_line
--                 let end_line = lnmb
--                 break
--             endif
--         endif
--         let lnmb += 1
--     endwhile
--     return [start_line, end_line]
-- endfunc
-- ]])
local function find_unbalanced_lines_around(cur_line)
	local start_line = -1
	local end_line = -1
	local multiline_search_range = 10
	if vim.g.multiline_search_range ~= nil then
		multiline_search_range = vim.g.multiline_search_range
	end
	local lnmb = vim.fn.max({ 1, cur_line - multiline_search_range })
	local lnme = vim.fn.min({ vim.fn.line('$'), cur_line + multiline_search_range })
	while lnmb < lnme do
		if #vim.fn.split(vim.fn.getline(lnmb), '"', 1) % 2 == 0 then
			if lnmb < cur_line then
				start_line = lnmb
			end
			if lnmb > cur_line then
				end_line = lnmb
				goto done
			end
		end
		lnmb = lnmb + 1
	end
	::done::
	return { start_line, end_line }
end

-- vim.cmd([[
-- func! s:get_col_num_rfc_basic_even_case(line, delim, expected_num_fields)
--     let [fields, has_warning] = rainbow_csv#preserving_smart_split(a:line, a:delim, 'quoted_rfc')
--     if !has_warning && len(fields) == a:expected_num_fields
--         let col_num = s:get_col_num_single_line(fields, a:delim, 0)
--         return [fields, col_num]
--     endif
--     return []
-- endfunc
-- ]])
local function get_col_num_rfc_basic_even_case(line, delim, expected_num_fields)
	local fields, has_warning = unpack(M.preserving_smart_split(line, delim, 'quoted_rfc'))
	if not has_warning and #fields == expected_num_fields then
		local col_num = get_col_num_single_line(fields, delim, 0)
		return { fields, col_num }
	end
	return {}
end

-- vim.cmd([[
-- func! s:get_col_num_rfc_lines(line, delim, expected_num_fields)
--     let cur_line = line('.')
--     let [start_line, end_line] = s:find_unbalanced_lines_around(cur_line)
--     let even_number_of_dquotes = len(split(a:line, '"', 1)) % 2 == 1
--     if even_number_of_dquotes
--         if start_line != -1 && end_line != -1
--             let report = s:do_get_col_num_rfc_lines(cur_line, a:delim, start_line, end_line, a:expected_num_fields)
--             if len(report)
--                 return report
--             endif
--         endif
--         return s:get_col_num_rfc_basic_even_case(a:line, a:delim, a:expected_num_fields)
--     else
--         if start_line != -1
--             let report = s:do_get_col_num_rfc_lines(cur_line, a:delim, start_line, cur_line, a:expected_num_fields)
--             if len(report)
--                 return report
--             endif
--         endif
--         if end_line != -1
--             let report = s:do_get_col_num_rfc_lines(cur_line, a:delim, cur_line, end_line, a:expected_num_fields)
--             if len(report)
--                 return report
--             endif
--         endif
--         return []
--     endif
-- endfunc
-- ]])
local function get_col_num_rfc_lines(line, delim, expected_num_fields)
	local cur_line = vim.api.nvim_get_current_line()
	local start_line, end_line = unpack(find_unbalanced_lines_around(cur_line))
	local even_number_of_dquotes = #vim.fn.split(line, '"', 1) % 2 == 1
	if even_number_of_dquotes then
		if start_line ~= -1 and end_line ~= -1 then
			local report = do_get_col_num_rfc_lines(cur_line, delim, start_line, end_line, expected_num_fields)
			if #report > 0 then
				return report
			end
		end
		return get_col_num_rfc_basic_even_case(line, delim, expected_num_fields)
	else
		if start_line ~= -1 then
			local report = do_get_col_num_rfc_lines(cur_line, delim, start_line, cur_line, expected_num_fields)
			if #report > 0 then
				return report
			end
		end
		if end_line ~= -1 then
			local report = do_get_col_num_rfc_lines(cur_line, delim, cur_line, end_line, expected_num_fields)
			if #report > 0 then
				return report
			end
		end
		return {}
	end
end

-- vim.cmd([[
-- func! rainbow_csv#provide_column_info_on_hover()
--     let [delim, policy, comment_prefix] = rainbow_csv#get_current_dialect()
--     if policy == 'monocolumn'
--         return
--     endif
--     let line = getline('.')
--
--     if comment_prefix != '' && stridx(line, comment_prefix) == 0
--         echo ""
--         return
--     endif
--
--     let header = rainbow_csv#get_csv_header(delim, policy, comment_prefix)
--     if !len(header)
--         return
--     endif
--     let fields = []
--     let col_num = 0
--     if policy == 'quoted_rfc'
--         let report = s:get_col_num_rfc_lines(line, delim, len(header))
--         if len(report) != 2
--             echo ''
--             return
--         endif
--         let [fields, col_num] = report
--     else
--         let fields = rainbow_csv#preserving_smart_split(line, delim, policy)[0]
--         let col_num = s:get_col_num_single_line(fields, delim, 0)
--     endif
--     let num_cols = len(fields)
--
--     let ui_message = printf('Col %s', col_num + 1)
--     let col_name = ''
--     if col_num < len(header)
--         let col_name = header[col_num]
--     endif
--
--     let max_col_name = 50
--     if len(col_name) > max_col_name
--         let col_name = strpart(col_name, 0, max_col_name) . '...'
--     endif
--     if col_name != ""
--         let ui_message = ui_message . printf(', %s', col_name)
--     endif
--     if len(header) != num_cols
--         let ui_message = ui_message . '; WARN: num of fields in Header and this line differs'
--     endif
--     if exists("b:root_table_name")
--         let ui_message = ui_message . printf('; F7: Copy to %s', b:root_table_name)
--     endif
--     echo ui_message
-- endfunc
-- ]])
M.provide_column_info_on_hover = function()
	local delim, policy, comment_prefix = unpack(M.get_current_dialect())
	if policy == 'monocolumn' then
		return
	end
	local line = vim.api.nvim_get_current_line()

	if comment_prefix ~= '' and lua_stridx(line, comment_prefix) == 0 then
		vim.cmd('echo ""')
		return
	end

	local header = M.get_csv_header(delim, policy, comment_prefix)
	if #header == 0 then
		return
	end
	local fields = {}
	local col_num = 0
	if policy == 'quoted_rfc' then
		local report = get_col_num_rfc_lines(line, delim, #header)
		if #report ~= 2 then
			vim.cmd('echo ""')
			return
		end
		fields, col_num = unpack(report)
	else
		fields = M.preserving_smart_split(line, delim, policy)[1]
		col_num = get_col_num_single_line(fields, delim, 0)
	end
	local num_cols = #fields

	local ui_message = string.format('Col %s', col_num + 1)
	local col_name = ''
	if col_num < #header then
		col_name = header[col_num + 1]
	end

	local max_col_name = 50
	if #col_name > max_col_name then
		col_name = lua_strpart(col_name, 0, max_col_name) .. '...'
	end
	if col_name ~= '' then
		ui_message = ui_message .. ', ' .. col_name
	end
	if #header ~= num_cols then
		ui_message = ui_message .. '; WARN: num of fields in Header and this line differs'
	end
	if vim.b.root_table_name ~= nil then
		ui_message = ui_message .. '; F7: Copy to ' .. vim.b.root_table_name
	end
	vim.cmd(string.format('echo %q', ui_message))
end

-- vim.cmd([[
-- func! s:get_num_columns_if_delimited(delim, policy)
--     let lastLineNo = min([line("$"), 100])
--     if (lastLineNo < 5)
--         return 0
--     endif
--     let num_fields = 0
--     let num_lines_tested = 0
--     for linenum in range(1, lastLineNo)
--         let line = getline(linenum)
--         let comment_prefix = s:get_auto_comment_prefix()
--         if comment_prefix != '' && stridx(line, comment_prefix) == 0
--             continue
--         endif
--         let num_lines_tested += 1
--         let num_fields_cur = len(rainbow_csv#preserving_smart_split(line, a:delim, a:policy)[0])
--         if !num_fields
--             let num_fields = num_fields_cur
--         endif
--         if (num_fields != num_fields_cur || num_fields < 2)
--             return 0
--         endif
--     endfor
--     if num_lines_tested < 5
--         return 0
--     endif
--     return num_fields
-- endfunc
-- ]])
local function get_num_columns_if_delimited(delim, policy)
	local lastLineNo = vim.fn.min({ vim.fn.line('$'), 100 })
	if lastLineNo < 5 then
		return 0
	end
	local num_fields = 0
	local num_lines_tested = 0
	for linenum = 1, lastLineNo, 1 do
		local line = vim.fn.getline(linenum)
		local comment_prefix = get_auto_comment_prefix()
		if comment_prefix ~= '' and lua_stridx(line, comment_prefix) == 0 then
			goto next
		end
		num_lines_tested = num_lines_tested + 1
		local num_fields_cur = #M.preserving_smart_split(line, delim, policy)[1]
		if num_fields == 0 then
			num_fields = num_fields_cur
		end
		if num_fields ~= num_fields_cur or num_fields < 2 then
			return 0
		end
		::next::
	end
	if num_lines_tested < 5 then
		return 0
	end
	return num_fields
end

-- vim.cmd([[
-- func! s:guess_table_params_from_content()
--     let best_dialect = []
--     let best_score = 1
--     for delim in s:autodetection_delims
--         let policy = s:get_auto_policy_for_delim(delim)
--         let score = s:get_num_columns_if_delimited(delim, policy)
--         if score > best_score
--             let best_dialect = [delim, policy]
--             let best_score = score
--         endif
--     endfor
--     if best_score > s:max_columns
--         return []
--     endif
--     return best_dialect
-- endfunc
-- ]])
local function guess_table_params_from_content()
	local best_dialect = {}
	local best_score = 1
	for _, delim in ipairs(autodetection_delims) do
		local policy = get_auto_policy_for_delim(delim)
		local score = get_num_columns_if_delimited(delim, policy)
		if score > best_score then
			best_dialect = { delim, policy }
			best_score = score
		end
	end
	if best_score > max_columns then
		return {}
	end
	return best_dialect
end

-- vim.cmd([[
-- func! s:guess_table_params_from_content_frequency_based()
--     let best_delim = ','
--     let best_score = 0
--     let lastLineNo = min([line("$"), 50])
--     for delim in s:autodetection_delims
--         let regex_delim = escape(delim, s:magic_chars)
--         let score = 0
--         for linenum in range(1, lastLineNo)
--             let line = getline(linenum)
--             let score += len(split(line, regex_delim, 1)) - 1
--         endfor
--         if score > best_score
--             let best_delim = delim
--             let best_score = score
--         endif
--     endfor
--     let best_policy = (best_delim == ',' || best_delim == ';') ? 'quoted' : 'simple'
--     return [best_delim, best_policy]
-- endfunc
-- ]])
local function guess_table_params_from_content_frequency_based()
	local best_delim = ','
	local best_score = 0
	local lastLineNo = vim.fn.min({ vim.fn.line('$'), 50 })
	for _, delim in ipairs(autodetection_delims) do
		local regex_delim = lua_escape(delim, magic_chars)
		local score = 0
		for linenum = 1, lastLineNo, 1 do
			local line = vim.fn.getline(linenum)
			score = score + #vim.fn.split(line, regex_delim, 1) - 1
		end
		if score > best_score then
			best_delim = delim
			best_score = score
		end
	end
	local best_policy = 'simple'
	if best_delim == ',' or best_delim == ';' then
		best_policy = 'quoted'
	end
	return { best_delim, best_policy }
end

-- func! rainbow_csv#clear_current_buf_content()
--     let nl = line("$")
--     call cursor(1, 1)
--     execute "delete " . nl
-- endfunc


-- vim.cmd([[
-- func! rainbow_csv#generate_tab_statusline(tabstop_val, delim_len, template_fields)
--     let result = []
--     let space_deficit = 0
--     for nf in range(len(a:template_fields))
--         let available_space = (a:delim_len + len(a:template_fields[nf]) / a:tabstop_val) * a:tabstop_val
--         let column_name = 'a' . string(nf + 1)
--         let extra_len = available_space - len(column_name) - 1
--         if extra_len < 0
--             let space_deficit -= extra_len
--             let extra_len = 0
--         else
--             let regained = min([space_deficit, extra_len])
--             let space_deficit -= regained
--             let extra_len -= regained
--         endif
--         let space_filling = repeat(' ', extra_len + 1)
--         if nf + 1 == len(a:template_fields)
--             let space_filling = ''
--         endif
--         call add(result, column_name)
--         call add(result, space_filling)
--     endfor
--     return result
-- endfunc
-- ]])
M.generate_tab_statusline = function(tabstop_val, delim_len, template_fields)
	local result = {}
	local space_deficit = 0
	for nf = 1, #template_fields, 1 do
		local available_space = (delim_len + #template_fields[nf] / tabstop_val) * tabstop_val
		local column_name = 'a' .. nf
		local extra_len = available_space - #column_name - 1
		if extra_len < 0 then
			space_deficit = space_deficit - extra_len
			extra_len = 0
		else
			local regained = vim.fn.min({ space_deficit, extra_len })
			space_deficit = space_deficit - regained
			extra_len = extra_len - regained
		end
		local space_filling = string.rep(' ', extra_len + 1)
		if nf == #template_fields then
			space_filling = ''
		end
		table.insert(result, column_name)
		table.insert(result, space_filling)
	end
	return result
end

-- vim.cmd([[
-- func! s:status_escape_string(src)
--     " Strings in 'substitute' must follow esoteric rules, see `:help substitute()`
--     let result = substitute(a:src, ' ', '\\ ', 'g')
--     let result = substitute(result, '"', '\\"', 'g')
--     let result = substitute(result, '|', '\\|', 'g')
--     return result
-- endfunc
-- ]])
local function status_escape_string(src)
	-- these feel very odd
	-- local result = string.gsub(src, ' ', [[\\ ]])
	-- result = string.gsub(result, '"', [[\\"]])
	-- result = string.gsub(result, '|', [[\\|]])
	-- return result
	local result = vim.fn.substitute(src, ' ', [[\\ ]], 'g')
	result = vim.fn.substitute(result, '"', [[\\"]], 'g')
	result = vim.fn.substitute(result, '|', [[\\|]], 'g')
	return result
end

-- vim.cmd([[
-- func! rainbow_csv#restore_statusline()
--     if !exists("b:statusline_before")
--         return
--     endif
--     augroup StatusDisableGrp
--         autocmd!
--     augroup END
--     let escaped_statusline = s:status_escape_string(b:statusline_before)
--     execute "set statusline=" . escaped_statusline
--     unlet b:statusline_before
-- endfunc
-- ]])
M.restore_statusline = function()
	if vim.b.statusline_before == nil then
		return
	end
	vim.api.nvim_exec([[
    augroup StatusDisableGrp
        autocmd!
    augroup END
	]], false)
	local escaped_statusline = status_escape_string(vim.b.statusline_before)
	vim.cmd('set statusline=' .. escaped_statusline)
	vim.b.statusline_before = nil
end

-- vim.cmd([[
-- func! rainbow_csv#set_statusline_columns()
--     let [delim, policy, comment_prefix] = rainbow_csv#get_current_dialect()
--     if !exists("b:statusline_before")
--         let b:statusline_before = &statusline
--     endif
--     let has_number_column = &number
--     let indent = ''
--     if has_number_column
--         let indent_len = max([len(string(line('$'))) + 1, 4])
--         let indent = ' NR' . repeat(' ', indent_len - 3)
--     endif
--     let cur_line = policy == 'quoted_rfc' ? getline(1) : getline(line('.'))
--
--     if comment_prefix != '' && stridx(cur_line, comment_prefix) == 0
--         return
--     endif
--
--     let cur_fields = rainbow_csv#preserving_smart_split(cur_line, delim, policy)[0]
--     let status_labels = []
--     if delim == "\t"
--         let status_labels = rainbow_csv#generate_tab_statusline(&tabstop, len(delim), cur_fields)
--     else
--         let status_labels = rainbow_csv#generate_tab_statusline(1, len(delim), cur_fields)
--     endif
--     let max_len = winwidth(0)
--     let cur_len = len(indent)
--     let rb_statusline = '%#status_line_default_hl#' . indent
--     let num_columns = len(status_labels) / 2
--     for nf in range(num_columns)
--         let color_id = nf % s:num_groups
--         let column_name = status_labels[nf * 2]
--         let space_filling = status_labels[nf * 2 + 1]
--         let cur_len += len(column_name) + len(space_filling)
--         if cur_len + 1 >= max_len
--             break
--         endif
--         let rb_statusline = rb_statusline . '%#status_color' . color_id . '#' . column_name . '%#status_line_default_hl#' . space_filling
--     endfor
--     let rb_statusline = s:status_escape_string(rb_statusline)
--     execute "setlocal statusline=" . rb_statusline
--     redraw!
--     augroup StatusDisableGrp
--         autocmd CursorMoved * call rainbow_csv#restore_statusline()
--     augroup END
-- endfunc
-- ]])
M.set_statusline_columns = function(eval_value)
	local delim, policy, comment_prefix = unpack(M.get_current_dialect())
	if vim.b.statusline_before == nil then
		vim.b.statusline_before = vim.o.statusline
	end
	local has_number_column = vim.o.number
	local indent = ''
	if has_number_column then
		local indent_len = vim.fn.max({ #('' .. vim.fn.line('$')) + 1, 4 })
		indent = ' NR' .. string.rep(' ', indent_len - 1) -- gutter width adjust
	end
	local cur_line
	if policy == 'quoted_rfc' then
		cur_line = vim.fn.getline(1)
	else
		cur_line = vim.fn.getline(vim.fn.line('.'))
	end

	if comment_prefix ~= '' and lua_stridx(cur_line, comment_prefix) == 0 then
		return eval_value
	end

	local cur_fields = M.preserving_smart_split(cur_line, delim, policy)[1]
	local status_labels = {}
	if delim == '\t' then
		status_labels = M.generate_tab_statusline(vim.o.tabstop, #delim, cur_fields)
	else
		status_labels = M.generate_tab_statusline(1, #delim, cur_fields)
	end
	local max_len = vim.fn.winwidth(0)
	local cur_len = #indent
	local rb_statusline = '%#status_line_default_hl#' .. indent
	local num_columns = #status_labels / 2
	for nf = 0, num_columns - 1, 1 do
		local color_id = nf % num_groups
		local column_name = status_labels[nf * 2 + 1]
		local space_filling = status_labels[nf * 2 + 2]
		cur_len = cur_len + #column_name + #space_filling
		if cur_len + 1 >= max_len then
			goto done
		end
		rb_statusline = lua_join({ rb_statusline, '%#status_color', color_id, '#', column_name, '%#status_line_default_hl#',
			space_filling }, '')
	end
	::done::
	rb_statusline = status_escape_string(rb_statusline)
	vim.notify(rb_statusline, vim.log.levels.INFO, {})
	vim.cmd('setlocal statusline=' .. rb_statusline)
	vim.cmd([[
		redraw!
    augroup StatusDisableGrp
        autocmd CursorMoved * lua require'rainbow_csv.fns'.restore_statusline()
    augroup END
	]])
	return eval_value
end

-- vim.cmd([[
-- func! s:get_rb_script_path_for_this_table()
--     let rb_script_name = expand("%:t") . ".rbql"
--     call s:ensure_storage_exists()
--     let rb_script_path = s:rb_storage_dir . '/' . rb_script_name
--     return rb_script_path
-- endfunc
-- ]])
local function get_rb_script_path_for_this_table()
	local rb_script_name = vim.fn.expand('%:t') .. '.rbql'
	ensure_storage_exists()
	return rb_storage_dir .. '/' .. rb_script_name
end

-- func! s:generate_microlang_syntax(nfields)
--     if s:get_meta_language() == "python"
--         set ft=python
--     else
--         set ft=javascript
--     endif

--     for lnum in range(1, a:nfields)
--         let color_num = (lnum - 1) % s:num_groups
--         let cmd = 'syntax keyword rbql_color%d a%d'
--         exe printf(cmd, color_num, lnum)
--         let cmd = 'syntax keyword rbql_color%d b%d'
--         exe printf(cmd, color_num, lnum)
--     endfor

--     syntax match RbCmd "\c \@<=ORDER \+BY \@="
--     syntax match RbCmd "\c\(^ *\)\@<=SELECT\( \+TOP \+[0-9]\+\)\?\( \+DISTINCT\( \+COUNT\)\?\)\? \@="
--     syntax match RbCmd "\c\(^ *\)\@<=UPDATE\( \+SET\)\? \@="
--     syntax match RbCmd "\c \@<=WHERE \@="
--     syntax match RbCmd "\c \@<=DESC\( *$\)\@="
--     syntax match RbCmd "\c \@<=ASC\( *$\)\@="
--     syntax match RbCmd "\c \@<=\(\(\(STRICT \+\)\?LEFT \+\)\|\(INNER \+\)\)\?JOIN \+[^ ]\+ \+ON \@="
-- endfunc


-- func! s:make_select_line(num_fields)
--     let select_line = 'select '
--     let new_rows = []
--     for nf in range(1, a:num_fields)
--         let select_line = select_line . 'a' . nf
--         if nf < a:num_fields
--             let select_line = select_line . ', '
--         endif
--     endfor
--     return select_line
-- endfunc


-- func! s:make_rbql_demo(num_fields, rbql_welcome_path)
--     let select_line = s:make_select_line(a:num_fields)
--     let lines = readfile(a:rbql_welcome_path)
--     let query_line_num = 1
--     for lnum in range(len(lines))
--         let patched = substitute(lines[lnum], '###SELECT_PLACEHOLDER###', select_line, "g")
--         if patched != lines[lnum]
--             let query_line_num = lnum + 1
--             let lines[lnum] = patched
--         endif
--     endfor
--     call setline(1, lines)
--     call cursor(query_line_num, 1)
--     w
-- endfunc


-- todo portme?
-- vim.cmd([[
-- func! rainbow_csv#select_from_file()
--     let [delim, policy, unused_comment_prefix] = rainbow_csv#get_current_dialect()

--     let meta_language = s:get_meta_language()

--     if meta_language == "python" && !s:EnsurePythonInitialization()
--         echoerr "Python interpreter not found. Unable to run in this mode."
--         return 0
--     endif

--     if meta_language == "js" && !s:EnsureJavaScriptInitialization()
--         echoerr "Node.js interpreter not found. Unable to run in this mode."
--         return 0
--     endif

--     if exists("b:selected_buf") && buflisted(b:selected_buf)
--         execute "bd " . b:selected_buf
--     endif

--     let buf_number = bufnr("%")
--     let buf_path = resolve(expand("%:p"))

--     let rb_script_path = s:get_rb_script_path_for_this_table()
--     let already_exists = filereadable(rb_script_path)

--     let num_fields = len(rainbow_csv#preserving_smart_split(getline(1), delim, policy)[0])

--     call rainbow_csv#set_statusline_columns()

--     let splitbelow_before = &splitbelow
--     set splitbelow
--     execute "split " . fnameescape(rb_script_path)
--     if bufnr("%") == buf_number
--         echoerr "Something went wrong"
--         return
--     endif
--     if !splitbelow_before
--         set nosplitbelow
--     endif

--     let b:table_path = buf_path
--     let b:table_buf_number = buf_number
--     let b:rainbow_select = 1

--     if !exists("g:disable_rainbow_key_mappings")
--         nnoremap <buffer> <F5> :RbRun<cr>
--     endif

--     call s:generate_microlang_syntax(num_fields)
--     if !already_exists
--         if meta_language == "python"
--             let rbql_welcome_py_path = s:script_folder_path . '/rbql_core/welcome_py.rbql'
--             call s:make_rbql_demo(num_fields, rbql_welcome_py_path)
--         else
--             let rbql_welcome_js_path = s:script_folder_path . '/rbql_core/welcome_js.rbql'
--             call s:make_rbql_demo(num_fields, rbql_welcome_js_path)
--         endif
--     endif
-- endfunc
-- ]])
M.select_from_file = function()
	vim.notify('Not implemented', vim.log.levels.ERROR, {})
end

-- func! rainbow_csv#copy_file_content_to_buf(src_file_path, dst_buf_no)
--     bd!
--     redraw!
--     echo "executing..."
--     execute "buffer " . a:dst_buf_no
--     call rainbow_csv#clear_current_buf_content()
--     let lines = readfile(a:src_file_path)
--     call setline(1, lines)
-- endfunc


-- func! s:ShowImportantMessage(msg_header, msg_lines)
--     echohl ErrorMsg
--     echomsg a:msg_header
--     echohl None
--     for msg in a:msg_lines
--         echomsg msg
--     endfor
--     call input("Press ENTER to continue...")
-- endfunc


-- func! rainbow_csv#parse_report(report_content)
--     let lines = split(a:report_content, "\n")
--     let psv_warning_report = ''
--     let psv_error_report = ''
--     let psv_query_status = (len(lines) > 0 && len(lines[0]) > 0) ? lines[0] : 'Unknown error'
--     let psv_dst_table_path = len(lines) > 1 ? lines[1] : ''
--     let report = join(lines[2:], "\n")
--     if psv_query_status == "OK"
--         let psv_warning_report = report
--     else
--         let psv_error_report = report
--     endif
--     return [psv_query_status, psv_error_report, psv_warning_report, psv_dst_table_path]
-- endfunc


-- vim.cmd([[
-- func! s:get_output_format_params(input_delim, input_policy)
--     let out_format = exists('g:rbql_output_format') ? g:rbql_output_format : 'input'
--     if out_format == 'csv'
--         return [',', 'quoted']
--     endif
--     if out_format == 'tsv'
--         return ["\t", 'simple']
--     endif
--     return [a:input_delim, a:input_policy]
-- endfunc
-- ]])
local function get_output_format_params(input_delim, input_policy)
	local out_format
	if vim.g.rbql_output_format ~= nil then
		out_format = vim.g.rbql_output_format
	else
		out_format = 'input'
	end
	if out_format == 'csv' then
		return { ',', 'quoted' }
	end
	if out_format == 'tsv' then
		return { '\t', 'simple' }
	end
	return { input_delim, input_policy }
end

-- portme
-- vim.cmd([[
-- func! s:converged_select(table_buf_number, rb_script_path, query_buf_nr)
--     let meta_language = s:get_meta_language()

--     if meta_language == "python" && !s:EnsurePythonInitialization()
--         echoerr "Python interpreter not found. Unable to run in this mode."
--         return 0
--     endif

--     if meta_language == "js" && !s:EnsureJavaScriptInitialization()
--         echoerr "Node.js interpreter not found. Unable to run in this mode."
--         return 0
--     endif

--     let rbql_encoding = exists('g:rbql_encoding') ? g:rbql_encoding : 'utf-8'
--     if rbql_encoding != 'utf-8' && rbql_encoding != 'latin-1'
--         echoerr "Unsupported rbql encoding. Must be 'utf-8' or 'latin-1'"
--         return 0
--     endif

--     let table_filetype = getbufvar(a:table_buf_number, "&syntax")
--     let input_dialect = rainbow_csv#ft_to_dialect(table_filetype)
--     if !len(input_dialect)
--         echoerr "File is not a rainbow table"
--         return 0
--     endif
--     let input_delim = input_dialect[0]
--     let input_policy = input_dialect[1]
--     let input_comment_prefix = input_dialect[2]

--     let table_path = expand("#" . a:table_buf_number . ":p")
--     if table_path == ""
--         " For unnamed buffers. E.g. can happen for stdin-read buffer: `cat data.tsv | vim -`
--         let tmp_file_name = "tmp_table_" .  strftime("%Y_%m_%d_%H_%M_%S") . ".txt"
--         let table_path = s:rb_storage_dir . "/" . tmp_file_name
--         execute "w " . table_path
--     endif

--     let psv_query_status = 'Unknown error'
--     let psv_error_report = 'Something went wrong'
--     let psv_warning_report = ''
--     let psv_dst_table_path = ''

--     redraw!
--     echo "executing..."
--     let table_path_esc = s:py_source_escape(table_path)
--     let rb_script_path_esc = s:py_source_escape(a:rb_script_path)
--     let input_delim_escaped = s:py_source_escape(input_delim)
--     let [out_delim, out_policy] = s:get_output_format_params(input_delim, input_policy)
--     let out_delim_escaped = s:py_source_escape(out_delim)
--     let comment_prefix_escaped = s:py_source_escape(input_comment_prefix)
--     let with_headers_py_tf = s:get_rbql_with_headers() ? 'True' : 'False'
--     let py_call = 'vim_rbql.run_execute("' . table_path_esc . '", "' . rb_script_path_esc . '", "' . rbql_encoding . '", "' . input_delim_escaped . '", "' . input_policy . '", "' . comment_prefix_escaped . '", "' . out_delim_escaped . '", "' . out_policy . '", ' . with_headers_py_tf . ')'
--     if meta_language == "js"
--         let rbql_executable_path = s:script_folder_path . '/rbql_core/vim_rbql.js'
--         let cmd_args = ['node', shellescape(rbql_executable_path), shellescape(table_path), shellescape(a:rb_script_path), rbql_encoding, shellescape(input_delim), input_policy, shellescape(input_comment_prefix), shellescape(out_delim), out_policy, with_headers_py_tf]
--         let cmd = join(cmd_args, ' ')
--         let report_content = system(cmd)
--         let [psv_query_status, psv_error_report, psv_warning_report, psv_dst_table_path] = rainbow_csv#parse_report(report_content)
--     elseif s:system_python_interpreter != ""
--         let rbql_executable_path = s:script_folder_path . '/rbql_core/vim_rbql.py'
--         let cmd_args = [s:system_python_interpreter, shellescape(rbql_executable_path), shellescape(table_path), shellescape(a:rb_script_path), rbql_encoding, shellescape(input_delim), input_policy, shellescape(input_comment_prefix), shellescape(out_delim), out_policy, with_headers_py_tf]
--         let cmd = join(cmd_args, ' ')
--         let report_content = system(cmd)
--         let [psv_query_status, psv_error_report, psv_warning_report, psv_dst_table_path] = rainbow_csv#parse_report(report_content)
--     elseif has("python3")
--         exe 'python3 ' . py_call
--     elseif s:has_python_27()
--         exe 'python ' . py_call
--     else
--         call s:ShowImportantMessage("Error", ["Python not found, vim must have 'python' or 'python3' feature installed to run in this mode"])
--         return 0
--     endif

--     if psv_query_status != "OK"
--         call s:ShowImportantMessage(psv_query_status, [psv_error_report])
--         return 0
--     endif

--     if a:query_buf_nr != -1
--         execute "bd! " . a:query_buf_nr
--     endif

--     if index(split(psv_warning_report, "\n"), 'Output has multiple fields: using "CSV" output format instead of "Monocolumn"') == -1
--         call s:update_table_record(psv_dst_table_path, out_delim, out_policy, '@auto_comment_prefix@')
--     else
--         call s:update_table_record(psv_dst_table_path, ',', 'quoted', '@auto_comment_prefix@')
--     endif
--     execute "e " . fnameescape(psv_dst_table_path)

--     let b:self_path = psv_dst_table_path
--     let b:root_table_buf_number = a:table_buf_number
--     let b:root_table_name = fnamemodify(table_path, ":t")
--     let b:self_buf_number = bufnr("%")
--     call setbufvar(a:table_buf_number, 'selected_buf', b:self_buf_number)

--     if !exists("g:disable_rainbow_key_mappings")
--         nnoremap <buffer> <F7> :call rainbow_csv#copy_file_content_to_buf(b:self_path, b:root_table_buf_number)<cr>
--     endif

--     if len(psv_warning_report)
--         let warnings = split(psv_warning_report, "\n")
--         for wnum in range(len(warnings))
--             let warnings[wnum] = 'Warning: ' . warnings[wnum]
--         endfor
--         call s:ShowImportantMessage("Completed with WARNINGS!", warnings)
--     endif
--     return 1
-- endfunc
-- ]])
local function converged_select(table_buf_number, rb_script_path, query_buf_nr)
	vim.notify('Not implemented', vim.log.levels.WARN, {})
end

-- vim.cmd([[
-- func! rainbow_csv#set_table_name_for_buffer(table_name)
--     let table_path = resolve(expand("%:p"))
--     let new_record = [a:table_name, table_path]
--     let records = s:try_read_index(s:table_names_settings)
--     let records = s:update_records(records, a:table_name, new_record)
--     if len(records) > 100
--         call remove(records, 0)
--     endif
--     call s:write_index(records, s:table_names_settings)
-- endfunction
-- ]])
M.set_table_name_for_buffer = function(table_name)
	local table_path = vim.fn.resolve(vim.fn.expand('%:p'))
	local new_record = { table_name, table_path }
	local records = try_read_index(table_names_settings)
	records = update_records(records, table_name, new_record)
	if #records > 100 then
		table.remove(records, 1)
	end
	write_index(records, table_names_settings)
end


-- vim.cmd([[
-- func! s:run_cmd_query(query)
--     let rb_script_path = s:get_rb_script_path_for_this_table()
--     call writefile([a:query], rb_script_path)
--     let table_buf_number = bufnr("%")
--     call s:converged_select(table_buf_number, rb_script_path, -1)
-- endfunction
-- ]])
local function run_cmd_query(query)
	local rb_script_path = get_rb_script_path_for_this_table()
	vim.fn.writefile({ query }, rb_script_path)
	local table_buf_number = vim.fn.bufnr('%')
	converged_select(table_buf_number, rb_script_path, -1)
end

-- vim.cmd([[
-- func! rainbow_csv#run_select_cmd_query(query_string)
--     let query = 'SELECT ' . a:query_string
--     call s:run_cmd_query(query)
-- endfunction
-- ]])
M.run_select_cmd_query = function(query_string)
	run_cmd_query('SELECT ' .. query_string)
end


-- vim.cmd([[
-- func! rainbow_csv#run_update_cmd_query(query_string)
--     let query = 'UPDATE ' . a:query_string
--     call s:run_cmd_query(query)
-- endfunction
-- ]])
M.run_update_cmd_query = function(query_string)
	run_cmd_query('UPDATE' .. query_string)
end

-- vim.cmd([[
-- func! rainbow_csv#finish_query_editing()
--     if !exists("b:rainbow_select")
--         echoerr "Execute from rainbow query buffer"
--         return
--     endif
--     w
--     let rb_script_path = expand("%:p")
--     let query_buf_nr = bufnr("%")
--     let table_buf_number = b:table_buf_number
--     call s:converged_select(table_buf_number, rb_script_path, query_buf_nr)
-- endfunc
-- ]])
M.finish_query_editing = function()
	if vim.b.rainbow_select == nil then
		vim.cmd('echoerr "Execute from rainbow query buffer"')
		return
	end
	vim.cmd('w')
	local rb_script_path
	vim.fn.expand('%:p')
	local query_buf_nr = vim.fn.bufnr('%')
	local table_buf_number = vim.b.table_buf_number
	converged_select(table_buf_number, rb_script_path, query_buf_nr)
end


-- func! rainbow_csv#generate_rainbow_syntax(delim)
--     let syntax_lines = []
--     let regex_delim = escape(a:delim, s:magic_chars)
--     let char_class_delim = s:char_class_escape(a:delim)
--     let groupid = s:num_groups - 1
--     while groupid >= 0
--         let next_group_id = groupid + 1 < s:num_groups ? groupid + 1 : 0
--         let cmd = 'syntax match column%d /.\{-}\(%s\|$\)/ nextgroup=column%d'
--         call add(syntax_lines, printf(cmd, groupid, regex_delim, next_group_id))
--         let groupid -= 1
--     endwhile
--     return syntax_lines
-- endfunc


-- func! rainbow_csv#generate_escaped_rainbow_syntax(delim)
--     let syntax_lines = []
--     let regex_delim = escape(a:delim, s:magic_chars)
--     let char_class_delim = s:char_class_escape(a:delim)
--     let groupid = s:num_groups - 1
--     while groupid >= 0
--         let next_group_id = groupid + 1 < s:num_groups ? groupid + 1 : 0
--         let cmd = 'syntax match column%d /.\{-}\(%s\|$\)/ nextgroup=escaped_column%d,column%d'
--         call add(syntax_lines, printf(cmd, groupid, regex_delim, next_group_id, next_group_id))
--         let cmd = 'syntax match escaped_column%d / *"\([^"]*""\)*[^"]*" *\(%s\|$\)/ nextgroup=escaped_column%d,column%d'
--         call add(syntax_lines, printf(cmd, groupid, regex_delim, next_group_id, next_group_id))
--         let groupid -= 1
--     endwhile
--     return syntax_lines
-- endfunc


-- func! rainbow_csv#generate_escaped_rfc_rainbow_syntax(delim)
--     let syntax_lines = []
--     let regex_delim = escape(a:delim, s:magic_chars)
--     let char_class_delim = s:char_class_escape(a:delim)
--     let groupid = s:num_groups - 1
--     while groupid >= 0
--         let next_group_id = groupid + 1 < s:num_groups ? groupid + 1 : 0
--         let cmd = 'syntax match column%d /.\{-}\(%s\|$\)/ nextgroup=escaped_column%d,column%d'
--         call add(syntax_lines, printf(cmd, groupid, regex_delim, next_group_id, next_group_id))
--         let cmd = 'syntax match escaped_column%d / *"\(\([^"]\|\n\)*""\)*\([^"]\|\n\)*" *\(%s\|$\)/ nextgroup=escaped_column%d,column%d'
--         call add(syntax_lines, printf(cmd, groupid, regex_delim, next_group_id, next_group_id))
--         let groupid -= 1
--     endwhile
--     return syntax_lines
-- endfunc


-- func! rainbow_csv#generate_whitespace_syntax()
--     let syntax_lines = []
--     let groupid = s:num_groups - 1
--     while groupid >= 0
--         let next_group_id = groupid + 1 < s:num_groups ? groupid + 1 : 0
--         let cmd = 'syntax match column%d / *.\{-}\(  *\|$\)/ nextgroup=column%d'
--         call add(syntax_lines, printf(cmd, groupid, next_group_id))
--         let groupid -= 1
--     endwhile
--     return syntax_lines
-- endfunc


-- func! rainbow_csv#do_set_rainbow_filetype(rainbow_ft)
--     let b:originial_ft = &ft
--     execute "set ft=" . a:rainbow_ft
-- endfunc
M.do_set_rainbow_filetype = function(rainbow_ft)
	vim.b.originial_ft = vim.b.ft
	vim.cmd('set ft=' .. rainbow_ft)
end


-- func! rainbow_csv#set_rainbow_filetype(delim, policy, comment_prefix)
--     let rainbow_ft = rainbow_csv#dialect_to_ft(a:delim, a:policy, a:comment_prefix)
--     if match(rainbow_ft, 'rcsv') == 0
--         call rainbow_csv#ensure_syntax_exists(rainbow_ft, a:delim, a:policy, a:comment_prefix)
--     endif
--     call rainbow_csv#do_set_rainbow_filetype(rainbow_ft)
-- endfunc
M.set_rainbow_filetype = function(delim, policy, comment_prefix)
	local rainbow_ft = M.dialect_to_ft(delim, policy, comment_prefix)
	if rainbow_ft:find('rcsv', 1, true) ~= nil then
		M.ensure_syntax_exists(rainbow_ft, delim, policy, comment_prefix)
	end
	M.do_set_rainbow_filetype(rainbow_ft)
end

-- func! rainbow_csv#buffer_disable_rainbow_features()
--     let b:rainbow_features_enabled = 0
--     augroup RainbowHintGrp
--         autocmd! CursorMoved <buffer>
--     augroup END
--     if !exists("g:disable_rainbow_key_mappings")
--         unmap <buffer> <F5>
--     endif
-- endfunc
M.buffer_disable_rainbow_features = function()
	vim.b.rainbow_features_enabled = false
	-- todo what
	vim.cmd([[
        augroup RainbowHintGrp
            autocmd! CursorMoved <buffer>
        augroup END
    ]])
	if vim.g.disable_rainbow_key_mappings == nil then
		vim.cmd('unmap <buffer> <F5>')
	end
end

-- vim.cmd([[
-- func! rainbow_csv#buffer_enable_rainbow_features()
--     if rainbow_csv#is_rainbow_table_or_was_just_disabled()
--         call rainbow_csv#buffer_disable_rainbow_features()
--     endif
--
--     let b:rainbow_features_enabled = 1
--
--     set laststatus=2
--
--     if &compatible == 1
--         set nocompatible
--     endif
--
--     " maybe use setlocal number ?
--     set number
--
--     if !exists("g:disable_rainbow_key_mappings")
--         nnoremap <buffer> <F5> :RbSelect<cr>
--     endif
--
--     highlight status_line_default_hl ctermbg=black guibg=black
--
--     cnoreabbrev <expr> <buffer> Select rainbow_csv#set_statusline_columns() == "dummy" ? 'Select' : 'Select'
--     cnoreabbrev <expr> <buffer> select rainbow_csv#set_statusline_columns() == "dummy" ? 'Select' : 'Select'
--     cnoreabbrev <expr> <buffer> SELECT rainbow_csv#set_statusline_columns() == "dummy" ? 'Select' : 'Select'
--
--     cnoreabbrev <expr> <buffer> Update rainbow_csv#set_statusline_columns() == "dummy" ? 'Update' : 'Update'
--     cnoreabbrev <expr> <buffer> update rainbow_csv#set_statusline_columns() == "dummy" ? 'Update' : 'Update'
--     cnoreabbrev <expr> <buffer> UPDATE rainbow_csv#set_statusline_columns() == "dummy" ? 'Update' : 'Update'
--
--     augroup RainbowHintGrp
--         autocmd! CursorMoved <buffer>
--         if !exists("g:disable_rainbow_hover") || g:disable_rainbow_hover == 0
--             autocmd CursorMoved <buffer> call rainbow_csv#provide_column_info_on_hover()
--         endif
--     augroup END
-- endfunc
-- ]])
M.buffer_enable_rainbow_features = function()
	if M.is_rainbow_table_or_was_just_disabled() then
		M.buffer_disable_rainbow_features()
	end

	vim.b.rainbow_features_enabled = true

	vim.cmd('set laststatus=2')

	if vim.o.compatible then
		vim.cmd('set nocompatible')
	end

	vim.cmd('set number')

	if vim.g.disable_rainbow_key_mappings == nil then
		vim.cmd('nnoremap <buffer> <F5> :RbSelect<cr>')
	end

	vim.api.nvim_exec([[
		cnoreabbrev <expr> <buffer> Select luaeval('require("rainbow_csv.fns").set_statusline_columns("Select")')
		cnoreabbrev <expr> <buffer> select luaeval('require("rainbow_csv.fns").set_statusline_columns("Select")')
		cnoreabbrev <expr> <buffer> SELECT luaeval('require("rainbow_csv.fns").set_statusline_columns("Select")')

		cnoreabbrev <expr> <buffer> Update luaeval('require("rainbow_csv.fns").set_statusline_columns("Update")')
		cnoreabbrev <expr> <buffer> update luaeval('require("rainbow_csv.fns").set_statusline_columns("Update")')
		cnoreabbrev <expr> <buffer> UPDATE luaeval('require("rainbow_csv.fns").set_statusline_columns("Update")')
	]], false)

	vim.api.nvim_create_autocmd('CursorMoved', {
		group = vim.api.nvim_create_augroup('RainbowHintGrp', { clear = true }),
		pattern = '<buffer>',
		callback = function()
			if vim.g.disable_rainbow_hover == nil or vim.g.disable_rainbow_hover == false then
				M.provide_column_info_on_hover()
			end
		end
	})
end

-- function! rainbow_csv#get_visual_selection()
--     " Taken from here: https://stackoverflow.com/a/6271254/2898283
--     let [line_start, column_start] = getpos("'<")[1:2]
--     let [line_end, column_end] = getpos("'>")[1:2]
--     let lines = getline(line_start, line_end)
--     if len(lines) == 0
--         return ''
--     endif
--     let lines[-1] = lines[-1][: column_end - (&selection == 'inclusive' ? 1 : 2)]
--     let lines[0] = lines[0][column_start - 1:]
--     return join(lines, "\n")
-- endfunction
M.get_visual_selection = function()
	local sel = vim.api.nvim_exec([[
        let [line_start, column_start] = getpos("'<")[1:2]
        let [line_end, column_end] = getpos("'>")[1:2]
        let lines = getline(line_start, line_end)
        if len(lines) != 0
            let lines[-1] = lines[-1][: column_end - (&selection == 'inclusive' ? 1 : 2)]
            let lines[0] = lines[0][column_start - 1:]
            echo join(lines, '\n')
        else
            echo ''
        endif
    ]], true)
	return sel
end

-- vim.cmd([[
-- func! rainbow_csv#manual_set(arg_policy, is_multidelim)
--     if a:is_multidelim
--         let delim = rainbow_csv#get_visual_selection()
--         let policy = 'simple'
--         let max_delim_len = exists('g:max_multichar_delim_len') ? g:max_multichar_delim_len : 10
--         if len(delim) > max_delim_len
--             echoerr 'Multicharater delimiter is too long. Adjust g:max_multichar_delim_len or use a different separator'
--             return
--         endif
--     else
--         let delim = getline('.')[col('.') - 1]
--         let policy = a:arg_policy
--     endif
--     if policy == 'auto'
--         let policy = s:get_auto_policy_for_delim(delim)
--     endif
--     if delim == '"' && policy == 'quoted'
--         echoerr 'Double quote delimiter is incompatible with "quoted" policy'
--         return
--     endif
--     call rainbow_csv#set_rainbow_filetype(delim, policy, s:get_auto_comment_prefix())
--     let table_path = resolve(expand("%:p"))
--     call s:update_table_record(table_path, delim, policy, '@auto_comment_prefix@')
-- endfunc
-- ]])
M.manual_set = function(arg_policy, is_multidelim)
	local policy, delim
	if is_multidelim then
		delim = M.get_visual_selection()
		policy = 'simple'
		local max_delim_len = 10
		if vim.g.max_multichar_delim_len ~= nil then
			max_delim_len = vim.g.max_multichar_delim_len
		end
		if #delim > max_delim_len then
			vim.cmd('echoerr "Multicharater delimiter is too long. Adjust g:max_multichar_delim_len or use a different separator"')
			return
		end
	else
		delim = lua_charat(vim.api.nvim_get_current_line(), vim.fn.col('.') - 1)
		policy = arg_policy
	end
	if policy == 'auto' then
		policy = get_auto_policy_for_delim(delim)
	end
	if delim == '"' and policy == 'quoted' then
		vim.cmd("echoerr 'Double quote delimiter is incompatible with \"quoted\" policy'")
		return
	end
	vim.notify('delim = "' .. delim .. '"', vim.log.levels.WARN, {})
	M.set_rainbow_filetype(delim, policy, get_auto_comment_prefix())
	local table_path = vim.fn.resolve(vim.fn.expand('%:p'))
	update_table_record(table_path, delim, policy, '@auto_comment_prefix@')
end

-- vim.cmd([[
-- func! rainbow_csv#manual_disable()
--     if rainbow_csv#is_rainbow_table()
--         let original_filetype = exists("b:originial_ft") ? b:originial_ft : ''
--         " The command below: set ft =...  will implicitly trigger syntax update -> rainbow_csv#handle_syntax_change() -> rainbow_csv#buffer_disable_rainbow_features()
--         execute "set ft=" . original_filetype
--     endif
-- endfunc
-- ]])
M.manual_disable = function()
	if M.is_rainbow_table() then
		local original_filetype = ''
		if vim.b.originial_ft ~= nil then
			original_filetype = vim.b.originial_ft
		end
		vim.cmd('set ft=' .. original_filetype)
	end
end

-- todo port?
-- vim.cmd([[
-- func! rainbow_csv#manual_set_comment_prefix(is_multi_comment_prefix)
--     let [delim, policy, _comment_prefix_old] = rainbow_csv#get_current_dialect()
--     if policy == 'monocolumn'
--         echoerr "Rainbow comment prefix can only be set for highlighted CSV files"
--         return
--     endif

--     if a:is_multi_comment_prefix
--         let comment_prefix = rainbow_csv#get_visual_selection()
--         let max_prefix_len = exists('g:max_comment_prefix_len') ? g:max_comment_prefix_len : 5
--         if len(comment_prefix) > max_prefix_len
--             echoerr 'Multicharater comment prefix is too long. Adjust g:max_comment_prefix_len or use a different comment prefix'
--             return
--         endif
--     else
--         let comment_prefix = getline('.')[col('.') - 1]
--     endif
--     if len(comment_prefix) <= 0
--         echoerr 'Comment prefix can not be empty'
--         return
--     endif
--     call rainbow_csv#set_rainbow_filetype(delim, policy, comment_prefix)
--     let table_path = resolve(expand("%:p"))
--     call s:update_table_record(table_path, delim, policy, comment_prefix)
-- endfunc
-- ]])
M.manual_set_comment_prefix = function(is_multi_comment_prefix)
	vim.notify('Not implemented', vim.log.levels.ERROR, {})
end

-- todo port?
-- vim.cmd([[
-- func! rainbow_csv#manual_disable_comment_prefix()
--     let [delim, policy, _comment_prefix_old] = rainbow_csv#get_current_dialect()
--     call rainbow_csv#set_rainbow_filetype(delim, policy, '')
--     let table_path = resolve(expand("%:p"))
--     call s:update_table_record(table_path, delim, policy, '')
-- endfunc
-- ]])
M.manual_disable_comment_prefix = function()
	vim.notify('Not implemented', vim.log.levels.ERROR, {})
end

-- vim.cmd([[
-- func! rainbow_csv#handle_new_file()
--     let table_extension = expand('%:e')
--     if table_extension == 'tsv' || table_extension == 'tab'
--         call rainbow_csv#do_set_rainbow_filetype('tsv')
--         return
--     endif
--
--     let table_params = s:guess_table_params_from_content()
--     if !len(table_params) && table_extension == 'csv'
--         let table_params = s:guess_table_params_from_content_frequency_based()
--     endif
--     if !len(table_params)
--         let b:rainbow_features_enabled = 0
--         return
--     endif
--     call rainbow_csv#set_rainbow_filetype(table_params[0], table_params[1], s:get_auto_comment_prefix())
-- endfunc
-- ]])
M.handle_new_file = function()
	local table_extension = vim.fn.expand('%:e')
	if table_extension == 'tsv' or table_extension == 'tab' then
		M.do_set_rainbow_filetype('tsv')
		return
	end

	local table_params = guess_table_params_from_content()
	if #table_params == 0 and table_extension == 'csv' then
		table_params = guess_table_params_from_content_frequency_based()
	end
	if #table_params == 0 then
		vim.b.rainbow_features_enabled = false
		return
	end
	M.set_rainbow_filetype(table_params[1], table_params[2], get_auto_comment_prefix())
end

-- vim.cmd([[
-- func! rainbow_csv#handle_buffer_enter()
--     if !exists("s:num_groups")
--         " Just to make sure that syntax was generated.
--         call rainbow_csv#init_rb_color_groups()
--     endif
--
--     if exists("b:rainbow_features_enabled")
--         if b:rainbow_features_enabled
--             " This is a workaround against Vim glitches. sometimes it 'forgets' to highlight the file even when ft=csv, see https://stackoverflow.com/questions/14779299/syntax-highlighting-randomly-disappears-during-file-saving
--             " From the other hand it can discard highlight ":hi ... " rules from user config, so let's disable this for now
--             " syntax enable
--             " another hack instead of `syntax enable` which is kind of global
--             " Maybe it is better to power-cycle syntax instead of ft?
--             let ft_power_cycle = &ft
--             execute "set ft=" . ft_power_cycle
--         endif
--         return
--     endif
--
--     if exists("b:current_syntax")
--         " This is actually problematic for files with first comment line with # comment prefix e.g. this file: RBQL/test/csv_files/university_ranking_with_comments.csv
--         " Because this check happens before index search the decision to highlight as rainbow will not be remembered on file reopen
--         " On the other hand this improves performance - we don't have to read the index file on each buffer enter.
--         " We can actually do a hybrid approach - set a flag on buffer that it has already been checked + keep the cached version of the index file in Vim's memory
--         " TODO consider doing this ^
--         "
--         " Actually it is desirable to handle this even on the very first file open. For some reason Vim treats files with non - .txt extension and '#' as the first character as 'conf' files
--         return
--     endif
--
--     let table_path = resolve(expand("%:p"))
--     let table_params = s:get_table_record(table_path)
--     if len(table_params)
--         " 'disabled' is just for backward compatibility, it is an alias to 'monocolumn'
--         if table_params[1] == 'disabled' || table_params[1] == 'monocolumn'
--             let b:rainbow_features_enabled = 0
--         else
--             call rainbow_csv#set_rainbow_filetype(table_params[0], table_params[1], table_params[2])
--         endif
--         return
--     endif
--
--     if exists("g:disable_rainbow_csv_autodetect") && g:disable_rainbow_csv_autodetect
--         return
--     endif
--
--     call rainbow_csv#handle_new_file()
-- endfunc
-- ]])
M.handle_buffer_enter = function()
	if num_groups == nil then
		M.init_rb_color_groups()
	end

	if vim.b.rainbow_features_enabled ~= nil then
		if vim.b.rainbow_features_enabled then
			local ft_power_cycle = vim.o.ft
			vim.cmd('set ft=' .. ft_power_cycle)
		end
		return
	end

	if vim.b.current_syntax ~= nil then
		return
	end

	local table_path = vim.fn.resolve(vim.fn.expand('%:p'))
	local table_params = get_table_record(table_path)
	if #table_params > 0 then
		if table_params[2] == 'disabled' or table_params[2] == 'monocolumn' then
			vim.b.rainbow_features_enabled = false
		else
			M.set_rainbow_filetype(table_params[1], table_params[2], table_params[3])
		end
		return
	end

	if vim.g.disable_rainbow_csv_autodetect ~= nil and vim.g.disable_rainbow_csv_autodetect then
		return
	end

	M.handle_new_file()
end

-- vim.cmd([[
-- func! rainbow_csv#handle_syntax_change()
--     let [delim, policy, comment_prefix] = rainbow_csv#get_current_dialect()
--     if policy == 'monocolumn' " If the new filetype is no longer rainbow:
--         if rainbow_csv#is_rainbow_table_or_was_just_disabled()
--             call rainbow_csv#buffer_disable_rainbow_features()
--             let table_path = resolve(expand("%:p"))
--             call s:update_table_record(table_path, '', 'monocolumn', '')
--         endif
--         return
--     endif
--     if !exists("s:num_groups")
--         " Just to make sure that syntax was generated.
--         call rainbow_csv#init_rb_color_groups()
--     endif
--
--     " We don't want to update_table_record() here because ft change could have been triggered by autodetection
--     " Even if it is manual, Vim itself doesn't save manual ft=<lang> selections, so if this plugin does it but only for csv, this could be a little inconsistent
--     " But we can actually do this: in autodetection set a special flag and immediately unset it here. If the flag is not set, than it was manual switch and we need to remember the choice
--     call rainbow_csv#buffer_enable_rainbow_features()
--     let b:cached_virtual_header = s:read_virtual_header(delim, policy)
-- endfunc
-- ]])
M.handle_syntax_change = function()
	local delim, policy, _ = unpack(M.get_current_dialect())
	if policy == 'monocolumn' then
		if M.is_rainbow_table_or_was_just_disabled() then
			M.buffer_disable_rainbow_features()
			local table_path = vim.fn.resolve(vim.fn.expand('%:p'))
			update_table_record(table_path, '', 'monocolumn', '')
		end
		return
	end
	if num_groups == nil then
		M.init_rb_color_groups()
	end

	M.buffer_enable_rainbow_features()
	vim.b.cached_virtual_header = read_virtual_header(delim, policy)
end

return M
