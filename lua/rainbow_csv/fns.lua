-- "==============================================================================
-- "
-- " Description: Rainbow CSV
-- " Authors: Dmitry Ignatovich, ...
-- "
-- "==============================================================================

local function notify_err(msg)
	vim.notify(msg, vim.log.levels.ERROR)
end

local function notify_warn(msg)
	vim.notify(msg, vim.log.levels.WARN)
end

local M = {}

local max_columns = 30
if vim.g.rcsv_max_columns ~= nil then
	max_columns = vim.g.rcsv_max_columns
end

local rb_storage_dir = vim.env.HOME .. '/.rainbow_csv_storage'
if vim.g.rb_storage_dir ~= nil then
	rb_storage_dir = vim.g.rb_storage_dir
end

local table_names_settings = vim.env.HOME .. '/.rbql_table_names'
if vim.g.table_names_settings ~= nil then
	table_names_settings = vim.g.table_names_settings
end

local rainbow_table_index = vim.env.HOME .. '/.rbql_table_index'
if vim.g.rainbow_table_index ~= nil then
	rainbow_table_index = vim.g.rainbow_table_index
end

local script_folder_path = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h')

local python_env_initialized = false
local js_env_initialized = false
local system_python_interpreter = ''

local magic_chars = [[^*$.~/[]\]]

local named_syntax_map = {
	csv = { ',', 'quoted', '' },
	csv_semicolon = { ';', 'quoted', '' },
	tsv = { "\t", 'simple', '' },
	csv_pipe = { '|', 'simple', '' },
	csv_whitespace = { " ", 'whitespace', '' },
	rfc_csv = { ',', 'quoted_rfc', '' },
	rfc_semicolon = { ';', 'quoted_rfc', '' }
}

local autodetection_delims = { "\t", ",", ";", "|" }
if vim.g.rcsv_delimiters ~= nil then
	autodetection_delims = vim.g.rcsv_delimiters
end

local number_regex = [[^[0-9]\+\(\.[0-9]\+\)\?$]]
local non_numeric = -1

local align_progress_bar_position = 0
local progress_bar_size = 20

local num_groups = nil

local rainbow_hover_debounce_ms = 300
if vim.g.rainbow_hover_debounce_ms ~= nil then
	rainbow_hover_debounce_ms = vim.g.rainbow_hover_debounce_ms
end

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

local function lua_startswith(s, prefix)
	return s:sub(1, #prefix) == prefix
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

-- ripped from the neovim shared implementation, but validation is removed
local function vim_gsplit(s, sep, plain)
	local start = 1
	local done = false

	local function _pass(i, j, ...)
		if i then
			assert(j + 1 > start, 'Infinite loop detected')
			local seg = s:sub(start, i - 1)
			start = j + 1
			return seg, ...
		else
			done = true
			return s:sub(start)
		end
	end

	return function()
		if done or (s == '' and sep == '') then
			return
		end
		if sep == '' then
			if start == #s then
				done = true
			end
			return _pass(start + 1, start)
		end
		return _pass(s:find(sep, start, plain))
	end
end

-- ripped from the neovim shared implementation, but validation is removed
local function vim_split(s, sep, kwargs)
	local plain
	local trimempty = false

	kwargs = kwargs or {}
	plain = kwargs.plain
	trimempty = kwargs.trimempty

	local t = {}
	local skip = trimempty
	for c in vim_gsplit(s, sep, plain) do
		if c ~= '' then
			skip = false
		end

		if not skip then
			table.insert(t, c)
		end
	end

	if trimempty then
		for i = #t, 1, -1 do
			if t[i] ~= '' then
				break
			end
			table.remove(t, i)
		end
	end

	return t
end

local function lit_split(str, sep, keepempty)
	-- internal use of lit_split relies on plain = true to avoid calling escape()
	-- a bunch of times
	if keepempty == nil then
		return vim_split(str, sep, { plain = true, trimempty = true })
	end
	return vim_split(str, sep, { plain = true, trimempty = not keepempty })
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


local function get_auto_policy_for_delim(delim)
	if delim == ',' or delim == ';' then
		return 'quoted'
	elseif delim == ' ' then
		return 'whitespace'
	else
		return 'simple'
	end
end

local function has_custom_links()
	if vim.g.rcsv_colorlinks ~= nil then
		return #vim.g.rcsv_colorlinks > 1
	else
		return false
	end
end

local function init_groups_from_links()
	local link_groups = { 'String', 'Comment', 'NONE', 'Special', 'Identifier', 'Type', 'Question', 'CursorLineNr',
		'ModeMsg', 'Title' }
	if has_custom_links() then
		link_groups = vim.g.rcsv_colorlinks
	end
	for index, value in ipairs(link_groups) do
		vim.cmd.highlight { 'link', 'status_color' .. index - 1, value }
		vim.cmd.highlight { 'link', 'rbql_color' .. index - 1, value }
		vim.cmd.highlight { 'link', 'column' .. index - 1, value }
		vim.cmd.highlight { 'link', 'escaped_column' .. index - 1, value }
	end
	num_groups = #link_groups
end

local function has_custom_colors()
	if vim.g.rcsv_colorpairs ~= nil then
		return #vim.g.rcsv_colorpairs > 1
	else
		return false
	end
end

local function use_system_python()
	if vim.g.rbql_use_system_python then
		return vim.g.rbql_use_system_python == 1
	else
		return false
	end
end

local function get_rbql_with_headers()
	if vim.g.rbql_with_headers then
		return vim.g.rbql_with_headers == 1
	else
		return false
	end
end

local function init_groups_from_colors()
	local pairs = { { 'red', 'red' },
		{ 'green',       'green' },
		{ 'blue',        'blue' },
		{ 'magenta',     'magenta' },
		{ 'NONE',        'NONE' },
		{ 'darkred',     'darkred' },
		{ 'darkblue',    'darkblue' },
		{ 'darkgreen',   'darkgreen' },
		{ 'darkmagenta', 'darkmagenta' },
		{ 'darkcyan',    'darkcyan' } }
	if has_custom_colors() then
		pairs = vim.g.rcsv_colorpairs
	end
	for index, value in ipairs(pairs) do
		vim.cmd.highlight { 'status_color' .. index - 1, 'ctermfg=' .. value[1], 'guifg=' .. value[2], 'ctermbg=black',
			'guibg=black' }
		vim.cmd.highlight { 'rbql_color' .. index - 1, 'ctermfg=' .. value[1], 'guifg=' .. value[2] }
		vim.cmd.highlight { 'column' .. index - 1, 'ctermfg=' .. value[1], 'guifg=' .. value[2] }
		vim.cmd.highlight { 'escaped_column' .. index - 1, 'ctermfg=' .. value[1], 'guifg=' .. value[2] }
	end
	num_groups = #pairs
end

M.init_rb_color_groups = function()
	-- todo not sure how to check this is ported correctly
	if vim.g.syntax_on ~= 1 or has_custom_colors() then
		init_groups_from_colors()
	else
		init_groups_from_links()
	end

	vim.cmd.highlight { 'link', 'escaped_startcolumn', 'column0' }
	vim.cmd.highlight { 'RbCmd', 'ctermbg=blue', 'guibg=blue' }
end


vim.api.nvim_create_autocmd({ 'VimEnter', 'ColorScheme' }, {
	group = vim.api.nvim_create_augroup('RainbowCsvPluginInitAuGrp', { clear = true }),
	pattern = '*',
	callback = function() M.init_rb_color_groups() end
})

local function try_read_lines(src_path)
	local lines = {}
	if vim.fn.filereadable(src_path) == 1 then
		lines = vim.fn.readfile(src_path)
	end
	return lines
end

local function try_read_index(src_path)
	local lines = try_read_lines(src_path)
	local records = {}

	for _, line in ipairs(lines) do
		local fields = lit_split(line, ' ', true)
		table.insert(records, fields)
	end

	return records
end

local function write_index(records, dst_path)
	local lines = {}
	for _, record in ipairs(records) do
		local new_line = lua_join(record, '\t')
		table.insert(lines, new_line)
	end
	vim.fn.writefile(lines, dst_path)
end

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

local function index_encode_delim(delim)
	if delim == '\t' then
		return 'TAB'
	end
	if #delim > 1 then
		local result = string.gsub(delim, [[\\]], [[\\\\]])
		result = string.gsub(result, [[\t]], [[\\t]])
		return 'multichar:' .. result
	end
	return delim
end

local function index_decode_delim(encoded_delim)
	if encoded_delim == 'TAB' then
		return '\t'
	end
	if lua_startswith(encoded_delim, 'multichar:') then
		local result = string.sub(encoded_delim, #'multichar:' + 1)
		result = string.gsub(result, [[\\t]], [[\t']])
		result = string.gsub(result, [[\\\\]], [[\\]])
		return result
	end
	return encoded_delim
end

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

local function get_auto_comment_prefix()
	if vim.g.rainbow_comment_prefix ~= nil then
		return vim.g.rainbow_comment_prefix
	else
		return ''
	end
end

local function get_table_record(table_path)
	if #table_path == 0 then
		return {}
	end
	local records = try_read_index(rainbow_table_index)
	for _, record in ipairs(records) do
		if #record >= 3 and record[1] == table_path then
			local delim = index_decode_delim(record[2])
			local policy = record[3]
			local comment_prefix
			if #record > 3 then
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

local function string_to_hex(src)
	local bytes = { string.byte(src, 1, #src) }
	local result = ''
	for _, b in ipairs(bytes) do
		result = result .. string.format('%x', b)
	end
	return result
end

local function hex_to_string(src)
	local result = ''
	for nt = 1, #src, 2 do
		-- todo later when i'm less lazy
		result = result .. vim.fn.nr2char(vim.fn.str2nr(string.sub(src, nt, nt + 1), 16))
	end
	return result
end

M.dialect_to_ft = function(delim, policy, comment_prefix)
	for ft, delim_policy in pairs(named_syntax_map) do
		if delim == delim_policy[1] and policy == delim_policy[2] and comment_prefix == delim_policy[3] then
			return ft
		end
	end
	return lua_join({ 'rcsv', string_to_hex(delim), policy, string_to_hex(comment_prefix) }, '_')
end

M.ft_to_dialect = function(ft_val)
	if named_syntax_map[ft_val] then
		return named_syntax_map[ft_val]
	end
	local ft_parts = lit_split(ft_val, '_')
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
		notify_err(string.format('bad delim policy: %s', policy))
	end
	if comment_prefix ~= '' then
		local regex_comment_prefix = lua_escape(comment_prefix, magic_chars)
		table.insert(syntax_lines, 'syntax match Comment /^' .. regex_comment_prefix .. '.*$/')
	end
	local syntax_file_path = script_folder_path .. '/syntax/' .. rainbow_ft .. '.vim'
	vim.fn.writefile(syntax_lines, syntax_file_path)
end

M.generate_named_dialects = function()
	for ft, delim_policy in pairs(named_syntax_map) do
		M.ensure_syntax_exists(ft, delim_policy[1], delim_policy[2], delim_policy[3])
	end
end

M.get_current_dialect = function()
	-- todo this should be fine but might not be
	return M.ft_to_dialect(vim.o.filetype)
end

M.is_rainbow_table = function()
	return M.get_current_dialect()[2] ~= 'monocolumn'
end

M.is_rainbow_table_or_was_just_disabled = function()
	return vim.b.rainbow_features_enabled == true
end

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
		-- local regex_delim = lua_escape(delim, magic_chars)
		names = lit_split(line, delim)
	end
	return names
end

M.dbg_set_system_python_interpreter = function(interpreter)
	system_python_interpreter = interpreter
end

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

local function py_source_escape(src)
	local dst = string.gsub(src, [[\\]], [[\\\\]])
	dst = string.gsub(dst, [[\t]], [[\\t]])
	dst = string.gsub(dst, '"', [[\\"]])
	return dst
end

local function char_class_escape(src)
	if src == ']' then
		return '\\]'
	end
	if src == '\\' then
		return '\\\\'
	end
	return src
end

local function test_coverage()
	if vim.g.rbql_dbg_test_coverage ~= true then
		return false
	end
	return vim.fn.reltime()[2] % 2 == 1
end

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

local function EnsurePythonInitialization()
	if python_env_initialized then
		return true
	end
	local py_home_dir = py_source_escape(script_folder_path .. '/rbql_core')
	if vim.fn.has('python3') == 1 and not use_system_python() and not test_coverage() then
		vim.cmd('py3 import sys')
		vim.cmd('py3 import vim')
		vim.cmd([[exe 'python3 sys.path.insert(0, "]] .. py_home_dir .. [[")']])
		vim.cmd('py3 import vim_rbql')
	elseif has_python_27() and not use_system_python() and not test_coverage() then
		vim.cmd('py import sys')
		vim.cmd('py import vim')
		vim.cmd([[exe 'python sys.path.insert(0, "]] .. py_home_dir .. [[")']])
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

local function ensure_storage_exists()
	if vim.fn.isdirectory(rb_storage_dir) == 0 then
		vim.fn.mkdir(rb_storage_dir, 'p')
	end
end

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

M.strip_spaces = function(input_string)
	local _, start = input_string:find('^ +')
	local endof, _ = input_string:find(' +$')
	if start == nil then
		start = 0
	end
	if endof == nil then
		return input_string:sub(start + 1)
	end
	return input_string:sub(start + 1, endof - 1)
end


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

M.preserving_quoted_split = function(line, delim)
	-- todo hot function
	local src = line
	if string.find(src, '"') == nil then
		return lit_split(src, delim, true), false
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
					return result, true
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
	return result, has_warning
end

M.quoted_split = function(line, delim)
	local quoted_fields, _ = M.preserving_quoted_split(line, delim)
	return M.unescape_quoted_fields(quoted_fields)
end

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

M.smart_split = function(line, delim, policy)
	-- todo hot function
	local stripped = M.rstrip(line)
	if policy == 'monocolumn' then
		return stripped
	elseif policy == 'quoted' or policy == 'quoted_rfc' then
		return M.quoted_split(stripped, delim)
	elseif policy == 'simple' then
		return lit_split(stripped, delim, true)
	elseif policy == 'whitespace' then
		return M.whitespace_split(line, false)
	else
		notify_err 'bad delim policy'
	end
end

M.preserving_smart_split = function(line, delim, policy)
	-- todo hot function
	local stripped = M.rstrip(line)
	if policy == 'monocolumn' then
		return { stripped }, false
	elseif policy == 'quoted' or policy == 'quoted_rfc' then
		return M.preserving_quoted_split(stripped, delim)
	elseif policy == 'simple' then
		return lit_split(stripped, delim, true), false
	elseif policy == 'whitespace' then
		return M.whitespace_split(line, true), false
	else
		notify_err 'bad delim policy'
	end
end

M.csv_lint = function()
	local delim, policy, comment_prefix = unpack(M.get_current_dialect())
	if policy == 'monocolumn' then
		notify_err 'CSVLint is available only for highlighted CSV files'
		return
	elseif policy == 'quoted_rfc' then
		-- TODO implement
		notify_err 'CSVLint is not implemented yet for rfc_csv'
		return
	end
	local lastLineNo = vim.fn.line('$')
	local num_fields = 0
	for linenum = 1, lastLineNo, 1 do
		local line = vim.fn.getline(linenum)
		if comment_prefix ~= '' and lua_startswith(line, comment_prefix) then
			goto next
		end
		local fields, has_warning = M.preserving_smart_split(line, delim, policy)
		if has_warning then
			notify_err(string.format('Line %d has formatting error: double quote chars are not consistent',
				linenum))
			return
		end
		local num_fields_cur = #fields
		if num_fields == 0 then
			num_fields = num_fields_cur
		end
		if num_fields ~= num_fields_cur then
			notify_err(string.format(
				'Number of fields is not consistent: e.g. line 1 has %d fields, and line %d has %d fields', num_fields, linenum,
				num_fields_cur))
			return
		end
		::next::
	end
	vim.cmd.echomsg '"CSVLint: OK"'
end

local num_regex = vim.regex(number_regex)
M.update_subcomponent_stats = function(field, is_first_line, max_field_components_lens)
	-- todo hottest function
	-- local field_length = vim.fn.strdisplaywidth(field)
	local field_length = vim.api.nvim_strwidth(field) -- should be equivalent and runs faster
	if field_length > max_field_components_lens[1] then
		max_field_components_lens[1] = field_length
	end
	if max_field_components_lens[2] == non_numeric then
		return
	end
	-- local pos = vim.fn.match(field, number_regex)
	local ismatch = num_regex:match_str(field)
	-- if pos == -1 then
	if ismatch == nil then
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

local function display_progress_bar(cur_progress_pos)
	local progress_display_str = 'Processing... [' ..
			string.rep('#', cur_progress_pos) .. string.rep(' ', progress_bar_size - cur_progress_pos) .. ']'
	vim.cmd.redraw()
	vim.cmd.echo(string.format('%q', progress_display_str))
end

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

local function calc_column_stats(delim, policy, comment_prefix)
	local column_stats = {}
	local lastLineNo = vim.fn.line('$')
	local is_first_line = true
	local chunkSize = 100
	local lastProgress = 0
	for chunkStart = 1, lastLineNo, chunkSize do
		local progress = math.floor((chunkStart / lastLineNo) * (progress_bar_size / 2))
		if progress > lastProgress then
			lastProgress = progress
			display_progress_bar(progress)
		end
		local chunk = vim.api.nvim_buf_get_lines(0, chunkStart - 1, chunkStart + chunkSize, false)
		for chunkIdx = 1, #chunk, 1 do
			local fields, has_warning = M.preserving_smart_split(chunk[chunkIdx], delim, policy)
			if comment_prefix ~= '' and lua_startswith(chunk[chunkIdx], comment_prefix) then
				goto next
			end
			if has_warning then
				return { column_stats, chunkStart + chunkIdx - 1 }
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
	end
	return { column_stats, 0 }
end

M.align_field = function(field, is_first_line, max_field_components_lens, is_last_column)
	-- todo hottest function
	local extra_readability_whitespace_length = 1
	local clean_field = M.strip_spaces(field)
	local field_length = vim.api.nvim_strwidth(clean_field)
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
			local delta_length = math.max(max_field_components_lens[1] - field_length, 0)
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

M.csv_align = function()
	vim.cmd.setlocal 'nowrap' -- todo there is a much better place for this
	local delim, policy, comment_prefix = unpack(M.get_current_dialect())
	if policy == 'monocolumn' then
		notify_err 'RainbowAlign is available only for highlighted CSV files'
		return
	elseif policy == 'quoted_rfc' then
		notify_err 'RainbowAlign not available for "rfc_csv" filetypes, consider using "csv" instead'
		return
	end
	local column_stats, first_failed_line = unpack(calc_column_stats(delim, policy, comment_prefix))
	if first_failed_line ~= 0 then
		notify_err('Unable to align: Inconsistent double quotes at line ' .. first_failed_line)
		return
	end
	column_stats = M.adjust_column_stats(column_stats)
	if #column_stats == 0 then
		notify_err 'Unable to align: Internal Rainbow CSV Error'
		return
	end
	local has_edit = false
	local is_first_line = true

	local lastLineNo = vim.fn.line('$')
	local chunkSize = 100
	local lastProgress = math.floor(progress_bar_size / 2) - 1;
	for chunkStart = 1, lastLineNo, chunkSize do
		local progress = math.floor((chunkStart / lastLineNo + 0.5) * progress_bar_size / 2)
		if progress > lastProgress then
			lastProgress = progress
			display_progress_bar(progress)
		end
		local chunk = vim.api.nvim_buf_get_lines(0, chunkStart - 1, chunkStart + chunkSize, false)
		for chunkIdx = 1, #chunk, 1 do
			local has_line_edit = false
			if comment_prefix ~= '' and lua_startswith(chunk[chunkIdx], comment_prefix) then
				goto next
			end
			local fields, _ = M.preserving_smart_split(chunk[chunkIdx], delim, policy)
			for fnum = 1, #fields, 1 do
				if fnum > #column_stats then
					notify_err 'bad off by one in csv_align'
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
				chunk[chunkIdx] = updated_line
				has_edit = true
			end
			is_first_line = false
			::next::
		end
		vim.api.nvim_buf_set_lines(0, chunkStart - 1, chunkStart + chunkSize, false, chunk)
	end
	if not has_edit then
		notify_warn 'File is already aligned'
	end
end

M.csv_shrink = function()
	local delim, policy, comment_prefix = unpack(M.get_current_dialect())
	if policy == 'monocolumn' then
		notify_err 'RainbowAlign is available only for highlighted CSV files'
		return
	elseif policy == 'quoted_rfc' then
		notify_err 'RainbowAlign not available for "rfc_csv" filetypes, consider using "csv" instead'
		return
	end
	local lastLineNo = vim.fn.line('$')
	local has_edit = false

	local chunkSize = 100
	local lastProgress = math.floor(progress_bar_size / 2) - 1;
	for chunkStart = 1, lastLineNo, chunkSize do
		local progress = math.floor((chunkStart / lastLineNo) * (progress_bar_size / 2) + 0.5)
		if progress > lastProgress then
			lastProgress = progress
			display_progress_bar(progress)
		end
		local chunk = vim.api.nvim_buf_get_lines(0, chunkStart - 1, chunkStart + chunkSize, false)
		for chunkIdx = 1, #chunk, 1 do
			local has_line_edit = false
			if comment_prefix ~= '' and lua_startswith(chunk[chunkIdx], comment_prefix) then
				goto next
			end
			local fields, has_warning = M.preserving_smart_split(chunk[chunkIdx], delim, policy)
			if has_warning then
				notify_err('Unable to shrink: Inconsistent double quotes at line ' .. chunkStart + chunkIdx - 1)
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
				chunk[chunkIdx] = updated_line
				has_edit = true
			end
			::next::
		end
		vim.api.nvim_buf_set_lines(0, chunkStart - 1, chunkStart + chunkSize, false, chunk)
	end
	if not has_edit then
		notify_warn 'File is already shrinked'
	end
end

M.get_csv_header = function(delim, policy, comment_prefix)
	if vim.b.cached_virtual_header ~= nil and #vim.b.cached_virtual_header > 0 then
		return vim.b.cached_virtual_header
	end
	local max_lines_to_check = math.min(vim.fn.line("$"), 20)
	for linenum = 1, max_lines_to_check, 1 do
		local line = vim.fn.getline(linenum)
		if comment_prefix ~= '' and lua_startswith(line, comment_prefix) then
		else
			return M.smart_split(line, delim, policy)
		end
	end
	return {}
end

local function get_col_num_single_line(fields, delim, offset)
	local col_num = 0
	local kb_pos = vim.fn.col('.')
	local cpos = offset + #fields[col_num + 1] + #delim
	while kb_pos > cpos and col_num + 1 < #fields do
		col_num = col_num + 1
		cpos = cpos + #fields[col_num + 1] + #delim
	end
	return col_num
end

local function do_get_col_num_rfc_lines(cur_line, delim, start_line, end_line, expected_num_fields)
	local record_lines = vim.api.nvim_buf_get_lines(0, start_line, end_line + 1, true) -- todo this impl doesn't match getline()
	local record_str = lua_join(record_lines, '\n')
	local fields, has_warning = M.preserving_smart_split(record_str, delim, 'quoted_rfc')
	if has_warning or #fields ~= expected_num_fields then
		return {}
	end
	local cursor_line_offset = cur_line - start_line
	local current_line_offset = 0
	local col_num = 0
	while col_num < #fields do
		current_line_offset = current_line_offset + #lit_split(fields[col_num + 1], '\n', true) - 1
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
		local splitcol = lit_split(fields[col_num + 1], '\n', true)
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

local function find_unbalanced_lines_around(cur_line)
	local start_line = -1
	local end_line = -1
	local multiline_search_range = 10
	if vim.g.multiline_search_range ~= nil then
		multiline_search_range = vim.g.multiline_search_range
	end
	local lnmb = math.max(1, cur_line - multiline_search_range)
	local lnme = math.min(vim.fn.line('$'), cur_line + multiline_search_range)
	while lnmb < lnme do
		if #lit_split(vim.fn.getline(lnmb), '"', true) % 2 == 0 then
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

local function get_col_num_rfc_basic_even_case(line, delim, expected_num_fields)
	local fields, has_warning = M.preserving_smart_split(line, delim, 'quoted_rfc')
	if not has_warning and #fields == expected_num_fields then
		local col_num = get_col_num_single_line(fields, delim, 0)
		return { fields, col_num }
	end
	return {}
end

local function get_col_num_rfc_lines(line, delim, expected_num_fields)
	local cur_line = vim.api.nvim_get_current_line()
	local start_line, end_line = unpack(find_unbalanced_lines_around(cur_line))
	local even_number_of_dquotes = #lit_split(line, '"', true) % 2 == 1
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

-- debounce_state[key]:
--	0 = not debounced
--	1 = debounced
--	2 = invoked during debounce period, (cb will be fired)
local debounce_state = {}
local function check_debounce(name, debounce_ms, cb)
	if debounce_state[name] == nil or debounce_state[name] == 0 then
		debounce_state[name] = 1
		vim.defer_fn(function()
			if cb ~= nil and debounce_state[name] == 2 then
				debounce_state[name] = 0
				cb()
			else
				debounce_state[name] = 0
			end
		end, debounce_ms)
		return false
	else
		debounce_state[name] = 2
		return true
	end
end

M.provide_column_info_on_hover = function()
	if rainbow_hover_debounce_ms ~= 0 and check_debounce('provide_column_info_on_hover', rainbow_hover_debounce_ms, M.provide_column_info_on_hover) then
		return
	end

	local delim, policy, comment_prefix = unpack(M.get_current_dialect())
	if policy == 'monocolumn' then
		return
	end
	local line = vim.api.nvim_get_current_line()
	if #line < 1 then
		vim.cmd.echo '""'
		return
	end

	if comment_prefix ~= '' and lua_startswith(line, comment_prefix) then
		vim.cmd.echo '""'
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
			vim.cmd.echo '""'
			return
		end
		fields, col_num = unpack(report)
	else
		fields, _ = M.preserving_smart_split(line, delim, policy)
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
	vim.cmd.echo(string.format('%q', ui_message))
end

local function get_num_columns_if_delimited(delim, policy)
	local lastLineNo = math.min(vim.fn.line('$'), 100)
	if lastLineNo < 5 then
		return 0
	end
	local num_fields = 0
	local num_lines_tested = 0
	for linenum = 1, lastLineNo, 1 do
		local line = vim.fn.getline(linenum)
		local comment_prefix = get_auto_comment_prefix()
		if comment_prefix ~= '' and lua_startswith(line, comment_prefix) then
			goto next
		end
		num_lines_tested = num_lines_tested + 1
		local result, _ = M.preserving_smart_split(line, delim, policy)
		local num_fields_cur = #result
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

local function guess_table_params_from_content_frequency_based()
	local best_delim = ','
	local best_score = 0
	local lastLineNo = math.min(vim.fn.line('$'), 50)
	for _, delim in ipairs(autodetection_delims) do
		local score = 0
		for linenum = 1, lastLineNo, 1 do
			local line = vim.fn.getline(linenum)
			score = score + #lit_split(line, delim, true) - 1
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

M.clear_current_buf_content = function()
	vim.api.nvim_buf_set_lines(0, 0, -1, false, {})
end

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
			local regained = math.min(space_deficit, extra_len)
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

M.restore_statusline = function()
	if vim.b.statusline_before == nil then
		return
	end
	vim.api.nvim_create_augroup('StatusDisableGrp', { clear = true })
	local escaped_statusline = status_escape_string(vim.b.statusline_before)
	vim.cmd.set { 'statusline=' .. escaped_statusline }
	vim.b.statusline_before = nil
end

M.set_statusline_columns = function(eval_value)
	local delim, policy, comment_prefix = unpack(M.get_current_dialect())
	if vim.b.statusline_before == nil then
		vim.b.statusline_before = vim.o.statusline
	end
	local has_number_column = vim.o.number
	local indent = ''
	if has_number_column then
		local indent_len = math.max(#('' .. vim.fn.line('$')) + 1, 4)
		indent = ' NR' .. string.rep(' ', indent_len - 1) -- gutter width adjust
	end
	local cur_line
	if policy == 'quoted_rfc' then
		cur_line = vim.fn.getline(1)
	else
		cur_line = vim.api.nvim_get_current_line()
	end

	if comment_prefix ~= '' and lua_startswith(cur_line, comment_prefix) then
		return eval_value
	end

	local cur_fields, _ = M.preserving_smart_split(cur_line, delim, policy)
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
	vim.cmd.setlocal { 'statusline=' .. rb_statusline }

	vim.cmd.redraw { bang = true }
	vim.api.nvim_create_autocmd('CursorMoved', {
		group = vim.api.nvim_create_augroup('StatusDisableGrp', { clear = false }),
		pattern = '*',
		callback = M.restore_statusline
	})
	return eval_value
end

local function get_rb_script_path_for_this_table()
	local rb_script_name = vim.fn.expand('%:t') .. '.rbql'
	ensure_storage_exists()
	return rb_storage_dir .. '/' .. rb_script_name
end

local function generate_microlang_syntax(nfields)
	if get_meta_language() == 'python' then
		vim.o.ft = 'python'
	else
		vim.o.ft = 'javascript'
	end

	for lnum = 1, nfields, 1 do
		local color_num = (lnum - 1) % num_groups
		vim.cmd.syntax { 'keyword', 'rbql_color' .. color_num, 'a' .. lnum }
		vim.cmd.syntax { 'keyword', 'rbql_color' .. color_num, 'b' .. lnum }
	end

	vim.api.nvim_exec([[
    syntax match RbCmd "\c \@<=ORDER \+BY \@="
    syntax match RbCmd "\c\(^ *\)\@<=SELECT\( \+TOP \+[0-9]\+\)\?\( \+DISTINCT\( \+COUNT\)\?\)\? \@="
    syntax match RbCmd "\c\(^ *\)\@<=UPDATE\( \+SET\)\? \@="
    syntax match RbCmd "\c \@<=WHERE \@="
    syntax match RbCmd "\c \@<=DESC\( *$\)\@="
    syntax match RbCmd "\c \@<=ASC\( *$\)\@="
    syntax match RbCmd "\c \@<=\(\(\(STRICT \+\)\?LEFT \+\)\|\(INNER \+\)\)\?JOIN \+[^ ]\+ \+ON \@="
	]], false)
end

local function make_select_line(num_fields)
	local select_line = 'select '
	for nf = 1, num_fields, 1 do
		select_line = select_line .. 'a' .. nf
		if nf < num_fields then
			select_line = select_line .. ', '
		end
	end
	return select_line
end

local function make_rbql_demo(num_fields, rbql_welcome_path)
	local select_line = make_select_line(num_fields)
	local lines = vim.fn.readfile(rbql_welcome_path)
	local query_line_num = 1
	for lnum = 1, #lines, 1 do
		local patched = string.gsub(lines[lnum], '###SELECT_PLACEHOLDER###', select_line)
		if patched ~= lines[lnum] then
			query_line_num = lnum
			lines[lnum] = patched
		end
	end
	vim.api.nvim_buf_set_lines(0, 0, 0, false, lines)
	vim.fn.cursor(query_line_num, 1)
	vim.cmd.write()
end

M.select_from_file = function()
	local delim, policy, _ = unpack(M.get_current_dialect())

	local meta_language = get_meta_language()

	if meta_language == 'python' and not EnsurePythonInitialization() then
		notify_err 'Python interpreter not found. Unable to run in this mode.'
		return false
	end
	if meta_language == 'js' and not EnsureJavaScriptInitialization() then
		notify_err 'Node.js interpreter not found. Unable to run in this mode.'
		return false
	end

	if vim.b.selected_buf ~= nil and vim.fn.buflisted(vim.b.selected_buf) ~= 0 then
		vim.cmd.bdelete(vim.b.selected_buf)
	end

	local buf_number = vim.fn.bufnr('%')
	local buf_path = vim.fn.resolve(vim.fn.expand('%:p'))

	local rb_script_path = get_rb_script_path_for_this_table()
	local already_exists = vim.fn.filereadable(rb_script_path) == 1

	local result, _ = M.preserving_smart_split(vim.fn.getline(1), delim, policy)
	local num_fields = #result

	M.set_statusline_columns()

	local splitbelow_before = vim.o.splitbelow
	vim.cmd.set 'splitbelow'
	vim.cmd.split(vim.fn.fnameescape(rb_script_path))
	if vim.fn.bufnr('%') == buf_number then
		notify_err 'Something went wrong'
		return -- todo shouldn't this return a value?
	end
	if not splitbelow_before then
		vim.cmd.set 'nosplitbelow'
	end

	vim.b.table_path = buf_path
	vim.b.table_buf_number = buf_number
	vim.b.rainbow_select = true

	if vim.g.disable_rainbow_key_mappings == nil then
		vim.keymap.set('n', '<F5>', M.finish_query_editing, { noremap = true, buffer = true })
	end

	generate_microlang_syntax(num_fields)
	if not already_exists then
		local rbql_welcome_path
		if meta_language == 'python' then
			rbql_welcome_path = script_folder_path .. '/rbql_core/welcome_py.rbql'
		else
			rbql_welcome_path = script_folder_path .. '/rbql_core/welcome_js.rbql'
		end
		make_rbql_demo(num_fields, rbql_welcome_path)
	end
end

M.copy_file_content_to_buf = function(src_file_path, dst_buf_no)
	vim.cmd.bdelete { bang = true }
	vim.cmd.redraw { bang = true }
	vim.cmd.echo '"executing..."'
	vim.cmd.buffer(dst_buf_no)
	M.clear_current_buf_content()
	local lines = vim.fn.readfile(src_file_path)
	vim.api.nvim_buf_set_lines(dst_buf_no, 0, 0, true, lines)
end

local function ShowImportantMessage(msg_header, msg_lines)
	local lines = msg_header .. '\n' .. lua_join(msg_lines, '\n')
	notify_err(lines)
end

M.parse_report = function(report_content)
	local lines = lit_split(report_content, '\n')
	local psv_warning_report = ''
	local psv_error_report = ''
	local psv_query_status = 'Unknown error'
	if #lines > 0 and #lines[1] > 0 then
		psv_query_status = lines[1]
	end
	local psv_dst_table_path = ''
	if #lines > 1 then
		psv_dst_table_path = lines[2]
	end
	local report = lua_join(vim.list_slice(lines, 3), '\n')
	if psv_query_status == 'OK' then
		psv_warning_report = report
	else
		psv_error_report = report
	end
	return { psv_query_status, psv_error_report, psv_warning_report, psv_dst_table_path }
end

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

local function converged_select(table_buf_number, rb_script_path, query_buf_nr)
	local meta_language = get_meta_language()

	if meta_language == 'python' and not EnsurePythonInitialization() then
		notify_warn 'Python interpreter not found. Unable to run in this mode.'
		return false
	end
	if meta_language == 'js' and not EnsureJavaScriptInitialization() then
		notify_warn 'Node.js interpreter not found. Unable to run in this mode.'
		return false
	end

	local rbql_encoding = 'utf-8'
	if vim.g.rbql_encoding ~= nil then
		rbql_encoding = vim.g.rbql_encoding
	end
	if rbql_encoding ~= 'utf-8' and rbql_encoding ~= 'latin-1' then
		notify_warn "Unsupported rbql encoding. Must be 'utf-8' or 'latin-1'"
		return false
	end

	local table_filetype = vim.api.nvim_buf_get_option(table_buf_number, 'filetype')
	local input_dialect = M.ft_to_dialect(table_filetype)
	if #input_dialect == 0 then
		notify_warn 'File is not a rainbow table'
		return false
	end
	local input_delim = input_dialect[1]
	local input_policy = input_dialect[2]
	local input_comment_prefix = input_dialect[3]

	local table_path = vim.fn.expand('#' .. table_buf_number .. ':p')
	if table_path == '' then
		local tmp_file_name = 'tmp_table_' .. vim.fn.strftime('%Y_%m_%d_%H_%M_%S') .. '.txt'
		table_path = rb_storage_dir .. '/' .. tmp_file_name
		vim.cmd.write(string.format('%q', table_path))
	end

	local psv_query_status = 'Unknown error'
	local psv_error_report = 'Something went wrong'
	local psv_warning_report = ''
	local psv_dst_table_path = ''

	vim.cmd.redraw { bang = true }
	vim.cmd.echo '"executing..."'
	local table_path_esc = py_source_escape(table_path)
	local rb_script_path_esc = py_source_escape(rb_script_path)
	local input_delim_escaped = py_source_escape(input_delim)
	local out_delim, out_policy = unpack(get_output_format_params(input_delim, input_policy))
	local out_delim_escaped = py_source_escape(out_delim)
	local comment_prefix_escaped = py_source_escape(input_comment_prefix)
	local with_headers_py_tf = 'False'
	if get_rbql_with_headers() then
		with_headers_py_tf = 'True'
	end
	local py_call = lua_join(
		{ 'vim_rbql.run_execute("', table_path_esc, '", "', rb_script_path_esc, '", "', rbql_encoding,
			'", "', input_delim_escaped, '", "', input_policy, '", "', comment_prefix_escaped, '", "', out_delim_escaped,
			'", "',
			out_policy, '", ', with_headers_py_tf, ')' }, '')
	if meta_language == 'js' then
		local rbql_executable_path = script_folder_path .. '/rbql_core/vim_rbql.js'
		local cmd_args = { 'node', vim.fn.shellescape(rbql_executable_path), vim.fn.shellescape(table_path),
			vim.fn.shellescape(rb_script_path), rbql_encoding, vim.fn.shellescape(input_delim), input_policy,
			vim.fn.shellescape(input_comment_prefix), vim.fn.shellescape(out_delim), out_policy, with_headers_py_tf }
		local cmd = lua_join(cmd_args, ' ')
		local report_content = vim.fn.system(cmd)
		psv_query_status, psv_error_report, psv_warning_report, psv_dst_table_path = unpack(M.parse_report(report_content))
	elseif system_python_interpreter ~= "" then
		local rbql_executable_path = script_folder_path .. '/rbql_core/vim_rbql.py'
		local cmd_args = { system_python_interpreter, vim.fn.shellescape(rbql_executable_path),
			vim.fn.shellescape(table_path),
			vim.fn.shellescape(rb_script_path), rbql_encoding, vim.fn.shellescape(input_delim), input_policy,
			vim.fn.shellescape(input_comment_prefix), vim.fn.shellescape(out_delim), out_policy, with_headers_py_tf }
		local cmd = lua_join(cmd_args, ' ')
		local report_content = vim.fn.system(cmd)
		psv_query_status, psv_error_report, psv_warning_report, psv_dst_table_path = unpack(M.parse_report(report_content))
	elseif vim.fn.has('python3') ~= 0 or has_python_27() then
		vim.cmd.python3(py_call)
		-- variables set from python must be copied to lua scope
		psv_query_status = vim.g.psv_query_status
		psv_error_report = vim.g.psv_error_report
		psv_warning_report = vim.g.psv_warning_report
		psv_dst_table_path = vim.g.psv_dst_table_path
	else
		ShowImportantMessage('Error',
			{ "Python not found, vim must have 'python' or 'python3' feature installed to run in this mode" })
		return false
	end

	if psv_query_status ~= 'OK' then
		ShowImportantMessage(psv_query_status, { psv_error_report })
		return false
	end

	if query_buf_nr ~= -1 then
		vim.cmd.bdelete { query_buf_nr, bang = true }
	end

	if vim.fn.index(lit_split(psv_warning_report, '\n'),
				'Output has multiple fields: using "CSV" output format instead of "Monocolumn"') == -1 then
		update_table_record(psv_dst_table_path, out_delim, out_policy, '@auto_comment_prefix@')
	else
		update_table_record(psv_dst_table_path, ',', 'quoted', '@auto_comment_prefix@')
	end
	vim.cmd.edit(vim.fn.fnameescape(psv_dst_table_path))

	vim.b.self_path = psv_dst_table_path
	vim.b.root_table_buf_number = table_buf_number
	vim.b.root_table_name = vim.fn.fnamemodify(table_path, ':t')
	vim.b.self_buf_number = vim.fn.bufnr('%')
	vim.fn.setbufvar(table_buf_number, 'selected_buf', vim.b.self_buf_number)

	if vim.g.disable_rainbow_key_mappings == nil then
		vim.keymap.set('n', '<F7>', function()
			M.copy_file_content_to_buf(vim.b.self_path, vim.b.root_table_buf_number)
		end, { noremap = true, buffer = true })
	end

	if #psv_warning_report > 0 then
		local warnings = lit_split(psv_warning_report, '\n')
		for wnum = 1, #warnings, 1 do
			warnings[wnum] = 'Warning: ' .. warnings[wnum]
		end
		ShowImportantMessage('Completed with WARNINGS!', warnings)
	end
	return true
end

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

local function run_cmd_query(query)
	local rb_script_path = get_rb_script_path_for_this_table()
	vim.fn.writefile({ query }, rb_script_path)
	local table_buf_number = vim.fn.bufnr('%')
	converged_select(table_buf_number, rb_script_path, -1)
end

M.run_select_cmd_query = function(query_string)
	run_cmd_query('SELECT ' .. query_string)
end

M.run_update_cmd_query = function(query_string)
	run_cmd_query('UPDATE ' .. query_string)
end

M.finish_query_editing = function()
	if vim.b.rainbow_select == nil then
		notify_err 'Execute from rainbow query buffer'
		return
	end
	vim.cmd.write()
	local rb_script_path = vim.fn.expand('%:p')
	local query_buf_nr = vim.fn.bufnr('%')
	local table_buf_number = vim.b.table_buf_number
	converged_select(table_buf_number, rb_script_path, query_buf_nr)
end

M.generate_rainbow_syntax = function(delim)
	local syntax_lines = {}
	local regex_delim = lua_escape(delim, magic_chars)
	local groupid = num_groups - 1
	while groupid >= 0 do
		local next_group_id = 0
		if groupid + 1 < num_groups then
			next_group_id = groupid + 1
		end
		local cmd = [[syntax match column%d /.\{-}\(%s\|$\)/ nextgroup=column%d]]
		table.insert(syntax_lines, cmd:format(groupid, regex_delim, next_group_id))
		groupid = groupid - 1
	end
	return syntax_lines
end

M.generate_escaped_rainbow_syntax = function(delim)
	local syntax_lines = {}
	local regex_delim = lua_escape(delim, magic_chars)
	local groupid = num_groups - 1
	while groupid >= 0 do
		local next_group_id = 0
		if groupid + 1 < num_groups then
			next_group_id = groupid + 1
		end
		local cmd = [[syntax match column%d /.\{-}\(%s\|$\)/ nextgroup=escaped_column%d,column%d]]
		table.insert(syntax_lines, cmd:format(groupid, regex_delim, next_group_id, next_group_id))
		cmd = [[syntax match escaped_column%d / *"\([^"]*""\)*[^"]*" *\(%s\|$\)/ nextgroup=escaped_column%d,column%d]]
		table.insert(syntax_lines, cmd:format(groupid, regex_delim, next_group_id, next_group_id))
		groupid = groupid - 1
	end
	return syntax_lines
end

M.generate_escaped_rfc_rainbow_syntax = function(delim)
	local syntax_lines = {}
	local regex_delim = lua_escape(delim, magic_chars)
	local groupid = num_groups - 1
	while groupid >= 0 do
		local next_group_id = 0
		if groupid + 1 < num_groups then
			next_group_id = groupid + 1
			local cmd = [[syntax match column%d /.\{-}\(%s\|$\)/ nextgroup=escaped_column%d,column%d]]
			table.insert(syntax_lines, cmd:format(groupid, regex_delim, next_group_id, next_group_id))
			cmd =
			[[syntax match escaped_column%d / *"\(\([^"]\|\n\)*""\)*\([^"]\|\n\)*" *\(%s\|$\)/ nextgroup=escaped_column%d,column%d]]
			table.insert(syntax_lines, cmd:format(groupid, regex_delim, next_group_id, next_group_id))
			groupid = groupid - 1
		end
	end
	return syntax_lines
end

M.generate_whitespace_syntax = function()
	local syntax_lines = {}
	local groupid = num_groups - 1
	while groupid >= 0 do
		local next_group_id = 0
		if groupid + 1 < num_groups then
			next_group_id = groupid + 1
		end
		local cmd = ([[syntax match column%d / *.\{-}\(  *\|$\)/ nextgroup=column%d]]):format(groupid, next_group_id)
		table.insert(syntax_lines, cmd)
		groupid = groupid - 1
	end
	return syntax_lines
end

M.do_set_rainbow_filetype = function(rainbow_ft)
	vim.b.originial_ft = vim.b.ft
	vim.cmd.set('ft=' .. rainbow_ft)
end

M.set_rainbow_filetype = function(delim, policy, comment_prefix)
	local rainbow_ft = M.dialect_to_ft(delim, policy, comment_prefix)
	if rainbow_ft:find('rcsv', 1, true) ~= nil then
		M.ensure_syntax_exists(rainbow_ft, delim, policy, comment_prefix)
	end
	M.do_set_rainbow_filetype(rainbow_ft)
end

M.buffer_disable_rainbow_features = function()
	vim.b.rainbow_features_enabled = false
	vim.api.nvim_create_augroup('RainbowHintGrp', { clear = true })
	if vim.g.disable_rainbow_key_mappings == nil then
		vim.keymap.del('n', '<F5>', { buffer = true })
	end
end

M.buffer_enable_rainbow_features = function()
	if M.is_rainbow_table_or_was_just_disabled() then
		M.buffer_disable_rainbow_features()
	end

	vim.b.rainbow_features_enabled = true

	if vim.g.disable_rainbow_statusline ~= 1 then
		vim.cmd.set 'laststatus=2'
	end

	vim.cmd.setlocal 'number'

	if vim.g.disable_rainbow_key_mappings == nil then
		vim.keymap.set('n', '<F5>', M.select_from_file, { noremap = true, buffer = true })
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
			notify_err 'Multicharater delimiter is too long. Adjust g:max_multichar_delim_len or use a different separator'
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
		notify_err 'Double quote delimiter is incompatible with "quoted" policy'
		return
	end
	notify_warn('delim = "' .. delim .. '"')
	M.set_rainbow_filetype(delim, policy, get_auto_comment_prefix())
	local table_path = vim.fn.resolve(vim.fn.expand('%:p'))
	update_table_record(table_path, delim, policy, '@auto_comment_prefix@')
end

M.manual_disable = function()
	if M.is_rainbow_table() then
		local original_filetype = ''
		if vim.b.originial_ft ~= nil then
			original_filetype = vim.b.originial_ft
		end
		vim.cmd.set('ft=' .. original_filetype)
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
	notify_err 'Not implemented'
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
	notify_err 'Not implemented'
end

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

M.handle_buffer_enter = function()
	if num_groups == nil then
		M.init_rb_color_groups()
	end

	if vim.b.rainbow_features_enabled ~= nil then
		if vim.b.rainbow_features_enabled then
			local ft_power_cycle = vim.o.ft
			vim.cmd.set('ft=' .. ft_power_cycle)
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

	if vim.g.disable_rainbow_csv_autodetect ~= nil and vim.g.disable_rainbow_csv_autodetect ~= 0 then
		return
	end

	M.handle_new_file()
end

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
