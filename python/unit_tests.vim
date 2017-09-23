:source unit_lib.vim
:call TestSplitRandomCsv()
:call RunUnitTests()

:call add(g:rbql_test_log_records, 'Starting full integration tests')

:e test_datasets/movies.tsv

:let g:rbql_meta_language = 'python'
:Select top 20 a1, * where a7.find('Adventure') != -1 order by int(a4) desc
:w! ./movies.tsv.py.rs
:bd!

:let g:rbql_meta_language = 'js'
:Select top 20 a1, * where a7.indexOf('Adventure') != -1 order by a4 * 1.0 desc
:w! ./movies.tsv.js.rs
:bd!

:let system_py_interpreter = rainbow_csv#find_python_interpreter()
:let log_msg = system_py_interpreter != '' ? system_py_interpreter : 'FAIL'
:call add(g:rbql_test_log_records, log_msg)

:let g:rbql_meta_language = 'python'
:Select top 20 a1, * where a7.find('Adventure') != -1 order by int(a4) desc
:w! ./movies.tsv.system_py.py.rs
:bd!

:let g:rbql_meta_language = 'js'
:Select top 20 a1, * where a7.indexOf('Adventure') != -1 order by a4 * 1.0 desc
:w! ./movies.tsv.system_py.js.rs
:bd!


:let g:rbql_meta_language = 'python'
:RbSelect
:call setline(11, "Select top 20 a1, * where a7.find('Adventure') != -1 order by int(a4) desc")
:RbRun
:w! ./movies.tsv.f5_ui.py.rs
:bd!


:call add(g:rbql_test_log_records, 'Finished full integration tests')
:call writefile(g:rbql_test_log_records, "./vim_unit_tests.log")

:q!
