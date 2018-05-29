:source unit_lib.vim
:call TestSplitRandomCsv()
:call RunUnitTests()

:call add(g:rbql_test_log_records, 'Starting full integration tests')

:e test_datasets/movies.tsv

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
:bd!

:e unit_tests/universities.monocolumn
:let g:rbql_output_format='input'
:sleep 1
:RainbowMonoColumn
:sleep 1
:Select *
:sleep 1
:Select a1, a1
:fake_comand_just_to_press_enter
:sleep 1
:let log_msg = (b:rainbow_csv_policy == 'quoted' && b:rainbow_csv_delim == ',') ? 'OK: monocolumn -> CSV switch' : 'FAIL'
:call add(g:rbql_test_log_records, log_msg)


:call add(g:rbql_test_log_records, 'Finished full integration tests')
:call writefile(g:rbql_test_log_records, "./vim_unit_tests.log")

:q!
