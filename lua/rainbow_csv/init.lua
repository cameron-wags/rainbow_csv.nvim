-- ==============================================================================
--
--  Description: Rainbow CSV
--  Authors: Dmitry Ignatovich, ...
--
-- ==============================================================================

local M = {}

M.setup = function()
	local fns = require 'rainbow_csv.fns'

	vim.api.nvim_exec([[
		augroup RainbowInitAuGrp
			autocmd!
			autocmd Syntax * lua require'rainbow_csv.fns'.handle_syntax_change()
			autocmd BufEnter * lua require'rainbow_csv.fns'.handle_buffer_enter()
		augroup END

		command! RainbowDelim lua require'rainbow_csv.fns'.manual_set('auto', false)
		command! RainbowDelimSimple lua require'rainbow_csv.fns'.manual_set('simple', false)
		command! RainbowDelimQuoted lua require'rainbow_csv.fns'.manual_set('quoted', false)
		command! RainbowMultiDelim lua require'rainbow_csv.fns'.manual_set('simple', true)
		command! NoRainbowDelim lua require'rainbow_csv.fns'.manual_disable()
		command! RainbowNoDelim lua require'rainbow_csv.fns'.manual_disable()

		command! RainbowComment lua require'rainbow_csv.fns'.manual_set_comment_prefix(false)
		command! RainbowCommentMulti lua require'rainbow_csv.fns'.manual_set_comment_prefix(true)
		command! NoRainbowComment lua require'rainbow_csv.fns'.manual_disable_comment_prefix()

		command! RainbowLint lua require'rainbow_csv.fns'.csv_lint()
		command! CSVLint lua require'rainbow_csv.fns'.csv_lint()
		command! RainbowAlign lua require'rainbow_csv.fns'.csv_align()
		command! RainbowShrink lua require'rainbow_csv.fns'.csv_shrink()

		command! RbSelect lua require'rainbow_csv.fns'.select_from_file()
		command! RbRun lua require'rainbow_csv.fns'.finish_query_editing()
		" command! -nargs=+ Select call rainbow_csv#run_select_cmd_query(<q-args>)
		" command! -nargs=+ Update call rainbow_csv#run_update_cmd_query(<q-args>)
		" command! -nargs=1 RainbowName call rainbow_csv#set_table_name_for_buffer(<q-args>)
	]], false)

	-- <q-args> may pose an issue, but we'll see
	vim.api.nvim_create_user_command('Select', function(_, args)
		fns.run_select_cmd_query(args)
	end, { nargs = '+' })
	vim.api.nvim_create_user_command('Update', function(_, args)
		fns.run_update_cmd_query(args)
	end, { nargs = '+' })
	vim.api.nvim_create_user_command('RainbowName', function(_, args)
		fns.set_table_name_for_buffer(args)
	end, { nargs = 1 })
end

return M
