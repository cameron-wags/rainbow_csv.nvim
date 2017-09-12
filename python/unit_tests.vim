:source unit_lib.vim
:call InitTests()
:call RunUnitTests()

:call writefile(['Starting full integration tests'], g:rbql_test_log_path, 'a')

:e test_datasets/movies.tsv

:let g:rbql_meta_language = 'python'
:Select top 20 a1, * where a7.find('Adventure') != -1 order by int(a4) desc
:w ./movies.tsv.py.rs
:bd!

:let g:rbql_meta_language = 'js'
:Select top 20 a1, * where a7.indexOf('Adventure') != -1 order by a4 * 1.0 desc
:w ./movies.tsv.js.rs
:bd!

:let system_py_interpreter = rainbow_csv#find_python_interpreter()
:let log_msg = system_py_interpreter != '' ? system_py_interpreter : 'FAIL'
:call writefile([log_msg], g:rbql_test_log_path, 'a')

:let g:rbql_meta_language = 'python'
:Select top 20 a1, * where a7.find('Adventure') != -1 order by int(a4) desc
:w ./movies.tsv.system_py.py.rs
:bd!

:let g:rbql_meta_language = 'js'
:Select top 20 a1, * where a7.indexOf('Adventure') != -1 order by a4 * 1.0 desc
:w ./movies.tsv.system_py.js.rs
:bd!

:call writefile(['Finished full integration tests'], g:rbql_test_log_path, 'a')

:q!
