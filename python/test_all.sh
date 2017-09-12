#!/usr/bin/env bash

python -m unittest test_rbql
python3 -m unittest test_rbql
node ./unit_tests.js


#Some CLI tests:
md5sum_test=($( ./rbql.py --query "select a1,a2,a7,b2,b3,b4 left join test_datasets/countries.tsv on a2 == b1 where 'Sci-Fi' in a7.split('|') and b2!='US' and int(a4) > 2010" < test_datasets/movies.tsv | md5sum))
md5sum_canonic=($( md5sum unit_tests/canonic_result_4.tsv ))
if [ "$md5sum_canonic" != "$md5sum_test" ] ; then
    echo "CLI test FAIL!"  1>&2
fi

md5sum_test=($( ./rbql.py --query "select a1,a2,a7,b2,b3,b4 left join test_datasets/countries.tsv on a2 == b1 where a7.split('|').includes('Sci-Fi') && b2!='US' && a4 > 2010" --meta_language js < test_datasets/movies.tsv | md5sum))
md5sum_canonic=($( md5sum unit_tests/canonic_result_4.tsv ))
if [ "$md5sum_canonic" != "$md5sum_test" ] ; then
    echo "CLI test FAIL!"  1>&2
fi

#vim integration tests:
rm vim_unit_tests.log 2> /dev/null
rm movies.tsv.py.rs 2> /dev/null
rm movies.tsv.js.rs 2> /dev/null
rm movies.tsv.system_py.py.rs 2> /dev/null
rm movies.tsv.system_py.js.rs 2> /dev/null

vim -s unit_tests.vim
total=$( cat vim_unit_tests.log | wc -l )
started=$( cat vim_unit_tests.log | grep 'Starting' | wc -l )
finished=$( cat vim_unit_tests.log | grep 'Finished' | wc -l )
fails=$( cat vim_unit_tests.log | grep 'FAIL' | wc -l )
if [ $total != 5 ] || [ $started != $finished ] || [ $fails != 0 ] ; then
    echo "FAIL! Integration tests failed"  1>&2
fi

md5sum_test_1=($( md5sum movies.tsv.py.rs ))
md5sum_test_2=($( md5sum movies.tsv.js.rs ))
md5sum_test_3=($( md5sum movies.tsv.system_py.py.rs ))
md5sum_test_4=($( md5sum movies.tsv.system_py.js.rs ))
md5sum_canonic=($( md5sum unit_tests/canonic_integration_1.tsv ))
sanity_len=$( printf "$md5sum_canonic" | wc -c )

if [ "$sanity_len" != 32 ] || [ "$md5sum_test_1" != $md5sum_canonic ] || [ "$md5sum_test_2" != $md5sum_canonic ] || [ "$md5sum_test_3" != $md5sum_canonic ] || [ "$md5sum_test_4" != $md5sum_canonic ] ; then
    echo "FAIL! Integration tests failed"  1>&2
fi

rm vim_unit_tests.log 2> /dev/null
rm movies.tsv.py.rs 2> /dev/null
rm movies.tsv.js.rs 2> /dev/null
rm movies.tsv.system_py.py.rs 2> /dev/null
rm movies.tsv.system_py.js.rs 2> /dev/null

echo "Finished vim integration tests"
