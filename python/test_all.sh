#!/usr/bin/env bash

cleanup_tmp_files() {
    rm movies.tsv.py.rs 2> /dev/null
    rm movies.tsv.js.rs 2> /dev/null
    rm movies.tsv.system_py.py.rs 2> /dev/null
    rm movies.tsv.system_py.js.rs 2> /dev/null
    rm university_ranking.rs.tsv 2> /dev/null
    rm vim_unit_tests.log 2> /dev/null
    rm random_ut.csv 2> /dev/null
    rm vim_debug.log 2> /dev/null
    rm movies_small.tsv.csv 2> /dev/null
    rm movies_small.tsv.csv.tsv 2> /dev/null
}

vim=vim
skip_python_ut="False"

while test ${#} -gt 0
do
  if [ $1 == "--vim" ]; then
      shift
      vim=$1
      shift
  elif [ $1 == "--skip_python_ut" ]; then
      shift
      skip_python_ut="True"
  else
      echo "Error. Unknown parameter: $1" 1>&2
      shift
      exit 1
  fi
done


if [ $skip_python_ut == "False" ]; then
    python -m unittest test_rbql
    python3 -m unittest test_rbql
else
    echo "Skipping python unit tests"
fi

cleanup_tmp_files

has_node="yes"

node_version=$( node --version 2> /dev/null )
rc=$?
if [ "$rc" != 0 ] || [ -z "$node_version" ] ; then
    echo "WARNING! Node.js was not found. Skipping node unit tests"  1>&2
    has_node="no"
fi

# We also need random_ut.csv file in vim unit tests
python test_rbql.py --create_random_csv_table random_ut.csv

if [ "$has_node" == "yes" ] ; then
    node ./unit_tests.js random_ut.csv
fi


# CLI tests:
md5sum_test=($( ./cli_rbql.py --query "select a1,a2,a7,b2,b3,b4 left join test_datasets/countries.tsv on a2 == b1 where 'Sci-Fi' in a7.split('|') and b2!='US' and int(a4) > 2010" < test_datasets/movies.tsv | md5sum))
md5sum_canonic=($( md5sum unit_tests/canonic_result_4.tsv ))
if [ "$md5sum_canonic" != "$md5sum_test" ] ; then
    echo "CLI test FAIL!"  1>&2
fi

if [ "$has_node" == "yes" ] ; then
    md5sum_test=($( ./cli_rbql.py --query "select a1,a2,a7,b2,b3,b4 left join test_datasets/countries.tsv on a2 == b1 where a7.split('|').includes('Sci-Fi') && b2!='US' && a4 > 2010" --host_language js < test_datasets/movies.tsv | md5sum))
    md5sum_canonic=($( md5sum unit_tests/canonic_result_4.tsv ))
    if [ "$md5sum_canonic" != "$md5sum_test" ] ; then
        echo "CLI test FAIL!"  1>&2
    fi
fi


# vim integration tests:

if [ "$has_node" == "yes" ] ; then
    $vim -s unit_tests.vim -V0vim_debug.log -u test_vimrc
else
    $vim -s unit_tests_py_only.vim -V0vim_debug.log -u test_vimrc
    cp movies.tsv.py.rs movies.tsv.js.rs 2> /dev/null
    cp movies.tsv.system_py.py.rs movies.tsv.system_py.js.rs 2> /dev/null
fi
errors=$( cat vim_debug.log | grep '^E[0-9][0-9]*' | wc -l )
total=$( cat vim_unit_tests.log | wc -l )
started=$( cat vim_unit_tests.log | grep 'Starting' | wc -l )
finished=$( cat vim_unit_tests.log | grep 'Finished' | wc -l )
fails=$( cat vim_unit_tests.log | grep 'FAIL' | wc -l )
if [ $total != 6 ] || [ $started != $finished ] || [ $fails != 0 ] ; then
    echo "FAIL! Integration tests failed: see vim_unit_test.log"  1>&2
    exit 1
fi

md5sum_movies_csv_canon="bb13547839020c33ba0da324fd0bb197"
md5sum_movies_tsv_canon="2a8016ac2cb05f52a1fd391a909112f5"

md5sum_test_1=($( md5sum movies.tsv.py.rs ))
md5sum_test_2=($( md5sum movies.tsv.js.rs ))
md5sum_test_3=($( md5sum movies.tsv.system_py.py.rs ))
md5sum_test_4=($( md5sum movies.tsv.system_py.js.rs ))
md5sum_update=($( md5sum university_ranking.rs.tsv ))
md5sum_movies_csv_test=($( md5sum movies_small.tsv.csv ))
md5sum_movies_tsv_test=($( md5sum movies_small.tsv.csv.tsv ))

md5sum_canonic=($( md5sum unit_tests/canonic_integration_1.tsv ))
sanity_len=$( printf "$md5sum_canonic" | wc -c )

if [ "$sanity_len" != 32 ] || [ "$md5sum_test_1" != $md5sum_canonic ] || [ "$md5sum_test_2" != $md5sum_canonic ] || [ "$md5sum_test_3" != $md5sum_canonic ] || [ "$md5sum_test_4" != $md5sum_canonic ] ; then
    echo "FAIL! Integration tests failed: md5sums"  1>&2
    exit 1
fi

if [ "$md5sum_movies_csv_canon" != "$md5sum_movies_csv_test" ] || [ "$md5sum_movies_tsv_canon" != "$md5sum_movies_tsv_test" ] ; then
    echo "FAIL! Integration tests failed: md5sums for movies_small"  1>&2
    exit 1
fi

if [ "$md5sum_update" != "fcc44cf2080ec88b56062472bbd89c3b" ] ; then
    echo "FAIL! Update integration tests failed: md5sums"  1>&2
    exit 1
fi

if [ $errors != 0 ] || [ ! -e vim_debug.log ] ; then
    echo "Warning: some errors were detected during vim integration testing, see vim_debug.log"  1>&2
    exit 1
fi

cleanup_tmp_files

echo "Finished vim integration tests"
