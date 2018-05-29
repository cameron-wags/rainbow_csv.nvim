:source unit_lib.vim
:call TestSplitRandomCsv()
:call RunUnitTests()

:call add(g:rbql_test_log_records, 'Starting full integration tests for python only')

:e test_datasets/movies.tsv

:let g:rbql_backend_language = 'python'
:Select top 20 a1, * where a7.find('Adventure') != -1 order by int(a4) desc
:sleep 1
:w! ./movies.tsv.py.rs
:bd!

:let system_py_interpreter = rainbow_csv#find_python_interpreter()
:let log_msg = system_py_interpreter != '' ? system_py_interpreter : 'FAIL'
:call add(g:rbql_test_log_records, log_msg)

:Select top 20 a1, * where a7.find('Adventure') != -1 order by int(a4) desc
:sleep 1
:w! ./movies.tsv.system_py.py.rs
:bd!

:e test_datasets/university_ranking.csv
:RbSelect
:%delete
:call setline(1, "Update set a3 = 'United States' where a3.find('of America') != -1")
:RbRun
:sleep 1
:w! ./university_ranking.rs.tsv
:bd!


:e unit_tests/movies_small.tsv
:let g:rbql_output_format='csv'
:Select *
:sleep 1
:w! ./movies_small.tsv.csv
:let g:rbql_output_format='tsv'
:Select *
:sleep 1
:w! ./movies_small.tsv.csv.tsv


:call add(g:rbql_test_log_records, 'Finished full integration tests')
:call writefile(g:rbql_test_log_records, "./vim_unit_tests.log")

:q!
