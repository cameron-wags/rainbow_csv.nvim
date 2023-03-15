-- ==============================================================================
--
--  Description: Rainbow CSV
--  Authors: Dmitry Ignatovich, ...
--
-- ==============================================================================

local M = {}

M.setup = function()
	local fns = require 'rainbow_csv.fns'

	local function mkcmd(name, cb, opts)
		if opts == nil then
			vim.api.nvim_create_user_command(name, cb, {})
		else
			vim.api.nvim_create_user_command(name, cb, opts)
		end
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
	mkcmd('RbRun', function() fns.finish_query_editing() end)

	mkcmd('Select', function(param) fns.run_select_cmd_query(param.args) end, { nargs = '+' })
	mkcmd('Update', function(param) fns.run_update_cmd_query(param.args) end, { nargs = '+' })
	mkcmd('RainbowName', function(param) fns.set_table_name_for_buffer(param.args) end, { nargs = 1 })

	vim.api.nvim_create_augroup('RainbowInitAuGrp', { clear = true })
	vim.api.nvim_create_autocmd('Syntax', {
		pattern = '*',
		callback = fns.handle_syntax_change,
	})
	vim.api.nvim_create_autocmd('BufEnter', {
		pattern = '*',
		callback = fns.handle_buffer_enter,
	})
end

return M
