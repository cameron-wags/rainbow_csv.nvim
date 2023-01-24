-- ==============================================================================
--
--  Description: Rainbow CSV
--  Authors: Dmitry Ignatovich, ...
--
-- ==============================================================================

local M = {}

M.setup = function()
	local fns = require 'rainbow_csv.fns'

	local function mkcmd(name, cb)
		vim.api.nvim_create_user_command(name, cb, {})
	end

	mkcmd('RainbowDelim', function() fns.manual_set('auto', false) end)
	mkcmd('RainbowDelimSimple', function() fns.manual_set('simple', false) end)
	mkcmd('RainbowDelimQuoted', function() fns.manual_set('quoted', false) end)
	mkcmd('RainbowMultiDelim', function() fns.manual_set('simple', true) end)
	mkcmd('NoRainbowDelim', function() fns.manual_disable() end)
	mkcmd('RainbowNoDelim', function() fns.manual_disable() end)

	mkcmd('RainbowComment', function() fns.manual_set_comment_prefix(false) end)
	mkcmd('RainbowCommentMulti', function() fns.manual_set_comment_prefix(true) end)
	mkcmd('NoRainbowComment', function() fns.manual_disable_comment_prefix() end)

	mkcmd('RainbowLint', function() fns.csv_lint() end)
	mkcmd('CSVLint', function() fns.csv_lint() end)
	mkcmd('RainbowAlign', function() fns.csv_align() end)
	mkcmd('RainbowShrink', function() fns.csv_shrink() end)

	mkcmd('RbSelect', function() fns.select_from_file() end)
	mkcmd('RbRunk', function() fns.finish_query_editing() end)

	vim.api.nvim_exec([[
		augroup RainbowInitAuGrp
			autocmd!
			autocmd Syntax * lua require'rainbow_csv.fns'.handle_syntax_change()
			autocmd BufEnter * lua require'rainbow_csv.fns'.handle_buffer_enter()
		augroup END

		" command! -nargs=+ Select call rainbow_csv#run_select_cmd_query(<q-args>)
		" command! -nargs=+ Update call rainbow_csv#run_update_cmd_query(<q-args>)
		" command! -nargs=1 RainbowName call rainbow_csv#set_table_name_for_buffer(<q-args>)
	]], false)

	-- <q-args> may pose an issue, but we'll see
	vim.api.nvim_create_user_command('Select', function(param)
		fns.run_select_cmd_query(param.args)
	end, { nargs = '+' })
	vim.api.nvim_create_user_command('Update', function(param)
		fns.run_update_cmd_query(param.args)
	end, { nargs = '+' })
	vim.api.nvim_create_user_command('RainbowName', function(param)
		fns.set_table_name_for_buffer(param.args)
	end, { nargs = 1 })
end

return M
