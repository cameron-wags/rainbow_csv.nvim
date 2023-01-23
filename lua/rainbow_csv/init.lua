-- ==============================================================================
--
--  Description: Rainbow CSV
--  Authors: Dmitry Ignatovich, ...
--
-- ==============================================================================

local rainbow_csv = require 'rainbow_csv.fns'

vim.api.nvim_exec([[
augroup RainbowInitAuGrp
    autocmd!
    " autocmd Syntax * call rainbow_csv#handle_syntax_change()
    autocmd Syntax * lua require'rainbow_csv.fns'.handle_syntax_change()
    " autocmd BufEnter * call rainbow_csv#handle_buffer_enter()
    autocmd BufEnter * lua require'rainbow_csv.fns'.handle_buffer_enter()
augroup END

" command! RainbowDelim call rainbow_csv#manual_set('auto', 0)
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
command! -nargs=+ Select call rainbow_csv#run_select_cmd_query(<q-args>)
command! -nargs=+ Update call rainbow_csv#run_update_cmd_query(<q-args>)
command! -nargs=1 RainbowName call rainbow_csv#set_table_name_for_buffer(<q-args>)
]], false)
