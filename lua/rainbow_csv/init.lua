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
command! RainbowDelimSimple call rainbow_csv#manual_set('simple', 0)
command! RainbowDelimQuoted call rainbow_csv#manual_set('quoted', 0)
command! RainbowMultiDelim call rainbow_csv#manual_set('simple', 1)
command! NoRainbowDelim call rainbow_csv#manual_disable()
command! RainbowNoDelim call rainbow_csv#manual_disable()

command! RainbowComment call rainbow_csv#manual_set_comment_prefix(0)
command! RainbowCommentMulti call rainbow_csv#manual_set_comment_prefix(1)
command! NoRainbowComment call rainbow_csv#manual_disable_comment_prefix()

command! RainbowLint call rainbow_csv#csv_lint()
command! CSVLint call rainbow_csv#csv_lint()
command! RainbowAlign lua require'rainbow_csv.fns'.csv_align()
command! RainbowShrink call rainbow_csv#csv_shrink()

command! RbSelect call rainbow_csv#select_from_file()
command! RbRun call rainbow_csv#finish_query_editing()
command! -nargs=+ Select call rainbow_csv#run_select_cmd_query(<q-args>)
command! -nargs=+ Update call rainbow_csv#run_update_cmd_query(<q-args>)
command! -nargs=1 RainbowName call rainbow_csv#set_table_name_for_buffer(<q-args>)
]], false)
