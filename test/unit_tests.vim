:source unit_lib.vim
:call TestSplitRandomCsv()
:call RunUnitTests()

:call add(g:rbql_test_log_records, 'Starting full integration tests')

:e ../rbql_core/test/csv_files/movies.tsv

:let g:rbql_backend_language = 'python'
:Select top 20 a1, * where a7.find('Adventure') != -1 order by int(a4) desc
:sleep 1
:w! ./movies.tsv.py.rs
:bd!

:let g:rbql_backend_language = 'js'
:Select top 20 a1, * where a7.indexOf('Adventure') != -1 order by a4 * 1.0 desc
:sleep 1
:w! ./movies.tsv.js.rs
:bd!

:let system_py_interpreter = rainbow_csv#find_python_interpreter()
:let log_msg = system_py_interpreter != '' ? system_py_interpreter : 'FAIL'
:call add(g:rbql_test_log_records, log_msg)

:let g:rbql_backend_language = 'python'
:Select top 20 a1, * where a7.find('Adventure') != -1 order by int(a4) desc
:sleep 1
:w! ./movies.tsv.system_py.py.rs
:bd!

:let g:rbql_backend_language = 'js'
:Select top 20 a1, * where a7.indexOf('Adventure') != -1 order by a4 * 1.0 desc
:sleep 1
:w! ./movies.tsv.system_py.js.rs
:bd!

:let g:rbql_output_format='tsv'

:let g:rbql_backend_language = 'python'
:e ./university_ranking.csv
:RbSelect
:%delete
:call setline(1, "Update set a3 = 'United States' where a3.find('of America') != -1")
:RbRun
:sleep 1
:w! ./university_ranking.rs.tsv
:bd!


:e ../rbql_core/test/csv_files/movies_small.tsv
:let g:rbql_output_format='csv'
:Select *
:sleep 1
:w! ./movies_small.tsv.csv
:let g:rbql_output_format='tsv'
:Select *
:sleep 1
:w! ./movies_small.tsv.csv.tsv
:bd!

:e ../rbql_core/test/csv_files/universities.monocolumn
:let g:rbql_output_format='input'
:sleep 1
:Select *
:sleep 1
:let g:rbql_output_format='csv'
:Select a1, a1
:sleep 1
:let log_msg = (&ft == 'csv') ? 'OK' : 'FAIL'
:call add(g:rbql_test_log_records, log_msg)

:e ../rbql_core/test/csv_files/movies_multichar_separator.txt
:sleep 1
:call rainbow_csv#set_rainbow_filetype('~#~', 'simple')
:sleep 1
:Select a2, COUNT(*) GROUP BY a2
:sleep 1
:let num_lines = line('$')
:let log_msg = (num_lines == 5) ? 'OK' : 'FAIL'
:call add(g:rbql_test_log_records, log_msg)


:e ../rbql_core/test/csv_files/synthetic_rfc_newline_data.csv
:sleep 1
:set ft=rfc_csv
:sleep 1
:Select a3, a2, a2 + ' adjusted', a1
:sleep 1
:let file_size = getfsize(expand(@%))
:let log_msg = (file_size == 544) ? 'OK' : 'FAIL'
:call add(g:rbql_test_log_records, log_msg)


:call add(g:rbql_test_log_records, 'Finished full integration tests')
:call writefile(g:rbql_test_log_records, "./vim_unit_tests.log")

:q!
