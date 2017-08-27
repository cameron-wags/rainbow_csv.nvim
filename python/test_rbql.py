#!/usr/bin/env python
# -*- coding: utf-8 -*-
from __future__ import unicode_literals
from __future__ import print_function

import sys
import os
import argparse
import random
import unittest
import re
import tempfile
import time
import importlib
import codecs
import io
import rbql
import subprocess

#This module must be both python2 and python3 compatible


default_csv_encoding = rbql.default_csv_encoding

def table_to_string(array2d, delim):
    result = '\n'.join([delim.join(ln) for ln in array2d])
    if len(array2d):
        result += '\n'
    return result


def table_to_file(array2d, dst_path, delim='\t'):
    with open(dst_path, 'w') as f:
        for row in array2d:
            f.write(delim.join(row))
            f.write('\n')


def table_to_stream(array2d, delim):
    return io.StringIO(table_to_string(array2d, delim))


def run_file_query_test_py(query, input_path, testname, import_modules=None, csv_encoding=default_csv_encoding, delim='\t'):
    tmp_dir = tempfile.gettempdir()
    if not len(sys.path) or sys.path[0] != tmp_dir:
        sys.path.insert(0, tmp_dir)
    module_name = '{}{}_{}_{}'.format(rainbow_ut_prefix, time.time(), testname, random.randint(1, 100000000)).replace('.', '_')
    module_filename = '{}.py'.format(module_name)
    tmp_path = os.path.join(tmp_dir, module_filename)
    dst_table_filename = '{}.tsv'.format(module_name)
    output_path = os.path.join(tmp_dir, dst_table_filename)
    rbql.parse_to_py([query], tmp_path, delim, csv_encoding, import_modules)
    rbconvert = rbql.dynamic_import(module_name)
    with codecs.open(input_path, encoding=csv_encoding) as src, codecs.open(output_path, 'w', encoding=csv_encoding) as dst:
        rbconvert.rb_transform(src, dst)
    return output_path


def run_file_query_test_js(query, input_path, testname, import_modules=None, csv_encoding=default_csv_encoding, delim='\t'):
    tmp_dir = tempfile.gettempdir()
    rnd_string = '{}{}_{}_{}'.format(rainbow_ut_prefix, time.time(), testname, random.randint(1, 100000000)).replace('.', '_')
    script_filename = '{}.js'.format(rnd_string)
    tmp_path = os.path.join(tmp_dir, script_filename)
    dst_table_filename = '{}.tsv'.format(rnd_string)
    output_path = os.path.join(tmp_dir, dst_table_filename)
    rbql.parse_to_js(input_path, output_path, [query], tmp_path, delim, csv_encoding, import_modules)
    cmd = ['node', tmp_path]
    pobj = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    out_data, err_data = pobj.communicate()
    error_code = pobj.returncode
    if len(err_data) or error_code != 0:
        raise RuntimeError("Error in file test: {}.\nScript location: {}".format(testname, tmp_path))
    return output_path


rainbow_ut_prefix = 'ut_rbconvert_'


def run_conversion_test_py(query, input_table, testname, import_modules=None, join_csv_encoding=default_csv_encoding, delim='\t'):
    tmp_dir = tempfile.gettempdir()
    if not len(sys.path) or sys.path[0] != tmp_dir:
        sys.path.insert(0, tmp_dir)
    module_name = '{}{}_{}_{}'.format(rainbow_ut_prefix, time.time(), testname, random.randint(1, 100000000)).replace('.', '_')
    module_filename = '{}.py'.format(module_name)
    tmp_path = os.path.join(tmp_dir, module_filename)
    src = table_to_stream(input_table, delim)
    dst = io.StringIO()
    rbql.parse_to_py([query], tmp_path, delim, join_csv_encoding, import_modules)
    assert os.path.isfile(tmp_path) and os.access(tmp_path, os.R_OK)
    rbconvert = rbql.dynamic_import(module_name)
    rbconvert.rb_transform(src, dst)
    out_data = dst.getvalue()
    if len(out_data):
        out_lines = out_data[:-1].split('\n')
        out_table = [ln.split(delim) for ln in out_lines]
    else:
        out_table = []
    return out_table


def run_conversion_test_js(query, input_table, testname, import_modules=None, csv_encoding=default_csv_encoding, delim='\t'):
    tmp_dir = tempfile.gettempdir()
    script_name = '{}{}_{}_{}.js'.format(rainbow_ut_prefix, time.time(), testname, random.randint(1, 100000000)).replace('.', '_')
    tmp_path = os.path.join(tmp_dir, script_name)
    rbql.parse_to_js(None, None, [query], tmp_path, delim, csv_encoding, None)
    src = table_to_string(input_table, delim)
    cmd = ['node', tmp_path]
    pobj = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, stdin=subprocess.PIPE)
    out_data, err_data = pobj.communicate(src.encode(csv_encoding))
    out_data = out_data.decode(csv_encoding)
    error_code = pobj.returncode
    assert len(err_data) == 0 and error_code == 0
    if len(out_data):
        out_lines = out_data[:-1].split('\n')
        out_table = [ln.split(delim) for ln in out_lines]
    else:
        out_table = []
    return out_table



def make_random_csv_entry(min_len, max_len, restricted_chars):
    strlen = random.randint(min_len, max_len)
    char_set = list(range(256))
    restricted_chars = [ord(c) for c in restricted_chars]
    char_set = [c for c in char_set if c not in restricted_chars]
    data = list()
    for i in rbql.xrange6(strlen):
        data.append(random.choice(char_set))
    pseudo_latin = bytes(bytearray(data)).decode('latin-1')
    return pseudo_latin


def generate_random_scenario(max_num_rows, max_num_cols, delims):
    num_rows = random.randint(1, max_num_rows)
    num_cols = random.randint(1, max_num_cols)
    delim = random.choice(delims)
    restricted_chars = ['\r', '\n'] + [delim]
    key_col = random.randint(0, num_cols - 1)
    good_keys = ['Hello', 'Avada Kedavra ', ' ??????', '128', '3q295 fa#(@*$*)', ' abcdefg ', 'NR', 'a1', 'a2']
    input_table = list()
    for r in rbql.xrange6(num_rows):
        input_table.append(list())
        for c in rbql.xrange6(num_cols):
            if c != key_col:
                input_table[-1].append(make_random_csv_entry(0, 20, restricted_chars))
            else:
                input_table[-1].append(random.choice(good_keys))

    output_table = list()
    target_key = random.choice(good_keys)
    if random.choice([True, False]):
        sql_op = '!='
        output_table = [row for row in input_table if row[key_col] != target_key]
    else:
        sql_op = '=='
        output_table = [row for row in input_table if row[key_col] == target_key]
    query = 'select * where a{} {} "{}"'.format(key_col + 1, sql_op, target_key)
    return (input_table, query, output_table, delim)


class TestEverything(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        tmp_dir = tempfile.gettempdir()
        old_unused = [f for f in os.listdir(tmp_dir) if f.startswith(rainbow_ut_prefix)]
        for name in old_unused:
            script_path = os.path.join(tmp_dir, name)
            os.remove(script_path)


    def compare_tables(self, canonic_table, test_table):
        self.assertEqual(len(canonic_table), len(test_table))
        for i in rbql.xrange6(len(canonic_table)):
            self.assertEqual(len(canonic_table[i]), len(test_table[i]))
            self.assertEqual(canonic_table[i], test_table[i])
        self.assertEqual(canonic_table, test_table)

    #TODO add degraded tests: empty table, one row table, empty result set etc

    def test_random_bin_tables(self):
        test_name = 'test_random_bin_tables'
        for subtest in rbql.xrange6(50):
            input_table, query, canonic_table, delim = generate_random_scenario(12, 12, ['\t', ',', ';'])
            test_table = run_conversion_test_py(query, input_table, test_name, delim=delim)
            self.compare_tables(canonic_table, test_table)


    def test_run1(self):
        test_name = 'test1'

        input_table = list()
        input_table.append(['5', 'haha', 'hoho'])
        input_table.append(['-20', 'haha', 'hioho'])
        input_table.append(['50', 'haha', 'dfdf'])
        input_table.append(['20', 'haha', ''])

        canonic_table = list()
        canonic_table.append(['3', '50', '4'])
        canonic_table.append(['4', '20', '0'])

        query = 'select NR, a1, len(a3) where int(a1) > 5'
        test_table = run_conversion_test_py(query, input_table, test_name)
        self.compare_tables(canonic_table, test_table)
        query = 'select NR, a1, a3.length where a1 > 5'
        test_table = run_conversion_test_js(query, input_table, test_name)
        self.compare_tables(canonic_table, test_table)


    def test_run2(self):
        test_name = 'test2'

        input_table = list()
        input_table.append(['5', 'haha', 'hoho'])
        input_table.append(['-20', 'haha', 'hioho'])
        input_table.append(['50', 'haha', 'dfdf'])
        input_table.append(['20', 'haha', ''])
        input_table.append(['8'])
        input_table.append(['3', '4', '1000', 'asdfasf', 'asdfsaf', 'asdfa'])
        input_table.append(['11', 'hoho', ''])
        input_table.append(['10', 'hihi', ''])
        input_table.append(['13', 'haha', ''])

        canonic_table = list()
        canonic_table.append(['haha'])
        canonic_table.append(['hoho'])

        query = '\tselect    distinct\ta2 where int(a1) > 10 #some#\t comments "with #text" "#"" '
        test_table = run_conversion_test_py(query, input_table, test_name)
        self.compare_tables(canonic_table, test_table)
        query = '\tselect    distinct\ta2 where a1 > 10 //some#\t comments "with //text" "#"" '
        test_table = run_conversion_test_js(query, input_table, test_name)
        self.compare_tables(canonic_table, test_table)


    def test_run3(self):
        test_name = 'test3'
        input_table = list()
        input_table.append(['5', 'haha', 'hoho'])
        input_table.append(['-20', 'haha', 'hioho'])
        input_table.append(['50', 'haha', 'dfdf'])
        input_table.append(['20', 'haha', ''])
        input_table.append(['11', 'hoho', ''])
        input_table.append(['10', 'hihi', ''])
        input_table.append(['13', 'haha', ''])

        canonic_table = list()
        canonic_table.append(['50', 'haha', 'dfdf'])
        canonic_table.append(['20', 'haha', ''])
        canonic_table.append(['13', 'haha', ''])
        canonic_table.append(['5', 'haha', 'hoho'])
        canonic_table.append(['-20', 'haha', 'hioho'])

        query = 'select \t  *  where flike(a2,\t"%a_a") order\tby int(a1)    desc   '
        test_table = run_conversion_test_py(query, input_table, test_name)
        self.compare_tables(canonic_table, test_table)
        #TODO implement flike() in js


    def test_run4(self):
        test_name = 'test4'
        input_table = list()
        input_table.append(['0', 'haha', 'hoho'])
        input_table.append(['9'])
        input_table.append(['81', 'haha', 'dfdf'])
        input_table.append(['4', 'haha', 'dfdf', 'asdfa', '111'])

        canonic_table = list()
        canonic_table.append(['0', r"\'\"a   bc"])
        canonic_table.append(['3', r"\'\"a   bc"])
        canonic_table.append(['9', r"\'\"a   bc"])
        canonic_table.append(['2', r"\'\"a   bc"])

        query = r'select int(math.sqrt(int(a1))), r"\'\"a   bc"'
        test_table = run_conversion_test_py(query, input_table, test_name, ['math', 'os'])
        self.compare_tables(canonic_table, test_table)

        #TODO do not strip consequent whitespaces durint rbql query parsing.
        #query = r'select Math.floor(Math.sqrt(a1)), String.raw`\'\"a   bc`'
        #test_table = run_conversion_test_js(query, input_table, test_name)
        #self.compare_tables(canonic_table, test_table)


    def test_run5(self):
        test_name = 'test5'
        query = 'select a2'
        input_table = list()
        input_table.append(['0', 'haha', 'hoho'])
        input_table.append(['9'])
        input_table.append(['81', 'haha', 'dfdf'])
        input_table.append(['4', 'haha', 'dfdf', 'asdfa', '111'])

        with self.assertRaises(Exception) as cm:
            run_conversion_test_py(query, input_table, test_name, ['math', 'os'])
        e = cm.exception
        self.assertTrue(str(e).find('No "a2" column at line: 2') != -1)


    def test_run6(self):
        test_name = 'test6'
        join_table_path = os.path.join(tempfile.gettempdir(), '{}_rhs_join_table.tsv'.format(test_name))

        join_table = list()
        join_table.append(['bicycle', 'legs'])
        join_table.append(['car', 'gas '])
        join_table.append(['plane', 'wings  \r'])
        join_table.append(['boat', 'wind\r'])
        join_table.append(['rocket', 'some stuff'])

        table_to_file(join_table, join_table_path)

        input_table = list()
        input_table.append(['5', 'car', 'lada'])
        input_table.append(['-20', 'car', 'Ferrari'])
        input_table.append(['50', 'plane', 'tu-134'])
        input_table.append(['20', 'boat', 'destroyer\r'])
        input_table.append(['10', 'boat', 'yacht '])
        input_table.append(['200', 'plane', 'boeing 737'])
        input_table.append(['80', 'train', 'Thomas'])

        canonic_table = list()
        canonic_table.append(['5', '10', 'boat', 'yacht ', 'boat', 'wind'])
        canonic_table.append(['4', '20', 'boat', 'destroyer', 'boat', 'wind'])
        canonic_table.append(['2', '-20', 'car', 'Ferrari', 'car', 'gas '])
        canonic_table.append(['1', '5', 'car', 'lada', 'car', 'gas '])
        canonic_table.append(['3', '50', 'plane', 'tu-134', 'plane', 'wings  '])
        canonic_table.append(['6', '200', 'plane', 'boeing 737', 'plane', 'wings  '])

        query = r'select NR, * inner join {} on a2 == b1 where b2 != "haha" and int(a1) > -100 and len(b2) > 1 order by a2, int(a1)'.format(join_table_path)
        test_table = run_conversion_test_py(query, input_table, test_name)
        self.compare_tables(canonic_table, test_table)
        query = r'select NR, * inner join {} on a2 == b1 where   b2 !=  "haha" &&  a1 > -100 &&  b2.length >  1 order by a2, parseInt(a1)'.format(join_table_path)
        test_table = run_conversion_test_js(query, input_table, test_name)
        self.compare_tables(canonic_table, test_table)


    def test_run7(self):
        test_name = 'test7'
        join_table_path = os.path.join(tempfile.gettempdir(), '{}_rhs_join_table.tsv'.format(test_name))

        join_table = list()
        join_table.append(['bicycle', 'legs'])
        join_table.append(['car', 'gas'])
        join_table.append(['plane', 'wings'])
        join_table.append(['rocket', 'some stuff'])

        table_to_file(join_table, join_table_path)

        query = r'select b1,b2,   a1 left join {} on a2 == b1 where b2 != "wings"'.format(join_table_path)

        input_table = list()
        input_table.append(['100', 'magic carpet', 'nimbus 3000'])
        input_table.append(['5', 'car', 'lada'])
        input_table.append(['-20', 'car', 'ferrari'])
        input_table.append(['50', 'plane', 'tu-134'])
        input_table.append(['20', 'boat', 'destroyer'])
        input_table.append(['10', 'boat', 'yacht'])
        input_table.append(['200', 'plane', 'boeing 737'])

        canonic_table = list()
        canonic_table.append(['None', 'None', '100'])
        canonic_table.append(['car', 'gas', '5'])
        canonic_table.append(['car', 'gas', '-20'])
        canonic_table.append(['None', 'None', '20'])
        canonic_table.append(['None', 'None', '10'])

        test_table = run_conversion_test_py(query, input_table, test_name)
        self.compare_tables(canonic_table, test_table)


    def test_run8(self):
        test_name = 'test8'
        join_table_path = os.path.join(tempfile.gettempdir(), '{}_rhs_join_table.tsv'.format(test_name))

        join_table = list()
        join_table.append(['bicycle', 'legs'])
        join_table.append(['car', 'gas'])
        join_table.append(['plane', 'wings'])
        join_table.append(['rocket', 'some stuff'])

        table_to_file(join_table, join_table_path)

        query = r'select b1,b2,   a1 strict left join {} on a2 == b1 where b2 != "wings"'.format(join_table_path)

        input_table = list()
        input_table.append(['5', 'car', 'lada'])
        input_table.append(['-20', 'car', 'ferrari'])
        input_table.append(['50', 'plane', 'tu-134'])
        input_table.append(['20', 'boat', 'destroyer'])
        input_table.append(['10', 'boat', 'yacht'])
        input_table.append(['200', 'plane', 'boeing 737'])
        input_table.append(['100', 'magic carpet', 'nimbus 3000'])

        with self.assertRaises(Exception) as cm:
            test_table = run_conversion_test_py(query, input_table, test_name)
        e = cm.exception
        self.assertTrue(str(e).find('all A table keys must be present in table B') != -1)


    def test_run9(self):
        test_name = 'test9'
        join_table_path = os.path.join(tempfile.gettempdir(), '{}_rhs_join_table.tsv'.format(test_name))

        join_table = list()
        join_table.append(['bicycle', 'legs'])
        join_table.append(['car', 'gas'])
        join_table.append(['plane', 'wings'])
        join_table.append(['plane', 'air'])
        join_table.append(['rocket', 'some stuff'])

        table_to_file(join_table, join_table_path)

        query = r'select b1,b2,a1 inner join {} on a2 == b1 where b1 != "car"'.format(join_table_path)

        input_table = list()
        input_table.append(['5', 'car', 'lada'])
        input_table.append(['-20', 'car', 'ferrari'])
        input_table.append(['50', 'plane', 'tu-134'])
        input_table.append(['200', 'plane', 'boeing 737'])

        with self.assertRaises(Exception) as cm:
            test_table = run_conversion_test_py(query, input_table, test_name)
        e = cm.exception
        self.assertTrue(str(e).find('Join column must be unique in right-hand-side "B" table') != -1)


    def test_run10(self):
        test_name = 'test10'
        query = 'select * where a3 =="hoho" or int(a1)==50 or a1 == "aaaa" or a2== "bbbbb" '

        input_table = list()
        input_table.append(['5', 'haha', 'hoho'])
        input_table.append(['-20', 'haha', 'hioho'])
        input_table.append(['50', 'haha', 'dfdf'])
        input_table.append(['20', 'haha', ''])

        canonic_table = list()
        canonic_table.append(['5', 'haha', 'hoho'])
        canonic_table.append(['50', 'haha', 'dfdf'])

        test_table = run_conversion_test_py(query, input_table, test_name)
        self.compare_tables(canonic_table, test_table)


    def test_run11(self):
        test_name = 'test11'

        input_table = list()
        input_table.append(['5', 'Петр Первый', 'hoho'])
        input_table.append(['-20', 'Екатерина Великая', 'hioho\r'])
        input_table.append(['50', 'Наполеон', 'dfdf\r'])
        input_table.append(['20', 'Наполеон', '\r'])

        canonic_table = list()
        canonic_table.append(['50', 'Наполеон', 'dfdf'])
        canonic_table.append(['20', 'Наполеон', ''])

        query = 'select * where a2== "Наполеон" '
        test_table = run_conversion_test_py(query, input_table, test_name, join_csv_encoding='utf-8')
        self.compare_tables(canonic_table, test_table)
        query = 'select * where a2== "Наполеон" '
        test_table = run_conversion_test_js(query, input_table, test_name, csv_encoding='utf-8')
        self.compare_tables(canonic_table, test_table)


    def test_run12(self):
        test_name = 'test12'
        join_table_path = os.path.join(tempfile.gettempdir(), '{}_rhs_join_table.tsv'.format(test_name))

        join_table = list()
        join_table.append(['bicycle', 'legs'])
        join_table.append(['car', 'gas'])
        join_table.append(['plane', 'wings'])
        join_table.append(['boat', 'wind'])
        join_table.append(['rocket', 'some stuff'])

        table_to_file(join_table, join_table_path)

        query = r'select NR, * JOIN {} on a2 == b1 where b2 != "haha" and int(a1) > -100 and len(b2) > 1 order by a2, int(a1)'.format(join_table_path)

        input_table = list()
        input_table.append(['5', 'car', 'lada'])
        input_table.append(['-20', 'car', 'Ferrari'])
        input_table.append(['50', 'plane', 'tu-134'])
        input_table.append(['20', 'boat', 'destroyer'])
        input_table.append(['10', 'boat', 'yacht'])
        input_table.append(['200', 'plane', 'boeing 737'])
        input_table.append(['80', 'train', 'Thomas'])

        canonic_table = list()
        canonic_table.append(['5', '10', 'boat', 'yacht', 'boat', 'wind'])
        canonic_table.append(['4', '20', 'boat', 'destroyer', 'boat', 'wind'])
        canonic_table.append(['2', '-20', 'car', 'Ferrari', 'car', 'gas'])
        canonic_table.append(['1', '5', 'car', 'lada', 'car', 'gas'])
        canonic_table.append(['3', '50', 'plane', 'tu-134', 'plane', 'wings'])
        canonic_table.append(['6', '200', 'plane', 'boeing 737', 'plane', 'wings'])

        test_table = run_conversion_test_py(query, input_table, test_name)
        self.compare_tables(canonic_table, test_table)



def calc_file_md5(fname):
    import hashlib
    hash_md5 = hashlib.md5()
    with open(fname, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            hash_md5.update(chunk)
    return hash_md5.hexdigest()


class TestFiles(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.old_dir = os.getcwd()
        script_dir = os.path.dirname(os.path.realpath(__file__))
        ut_dir = os.path.join(script_dir, 'unit_tests')
        os.chdir(ut_dir)

    @classmethod
    def tearDownClass(cls):
        os.chdir(cls.old_dir)

    def test_all(self):
        import json
        ut_config_path = 'unit_tests.cfg'
        has_node = rbql.system_has_node_js()
        if not has_node:
            rbql.eprint('unable to run js tests: node js is not found')
        with codecs.open(ut_config_path, encoding='utf-8') as src:
            for test_no, line in enumerate(src, 1):
                config = json.loads(line)
                src_path = config['src_table']
                canonic_table = config['canonic_table']
                query = config['query']
                encoding = config.get('encoding', default_csv_encoding)
                delim = config.get('delim', 'TAB')
                if delim == 'TAB':
                    delim = '\t'
                meta_language = config.get('meta_language', 'python')
                canonic_path = os.path.abspath(canonic_table)
                canonic_md5 = calc_file_md5(canonic_table)

                if meta_language == 'python':
                    result_table = run_file_query_test_py(query, src_path, str(test_no), csv_encoding=encoding, delim=delim)
                    test_path = os.path.abspath(result_table) 
                    test_md5 = calc_file_md5(result_table)
                    self.assertEqual(test_md5, canonic_md5, msg='Tables missmatch. Canonic: {}; Actual: {}'.format(canonic_path, test_path))
                
                else:
                    assert meta_language == 'js'
                    if not has_node:
                        continue
                    result_table = run_file_query_test_js(query, src_path, str(test_no), csv_encoding=encoding, delim=delim)
                    test_path = os.path.abspath(result_table) 
                    test_md5 = calc_file_md5(result_table)
                    self.assertEqual(test_md5, canonic_md5, msg='Tables missmatch. Canonic: {}; Actual: {}'.format(canonic_path, test_path))



class TestStringMethods(unittest.TestCase):

    def test_strip(self):
        a = 'v = "hello" #world  '
        a_strp = rbql.strip_py_comments(a)
        self.assertEqual(a_strp, 'v = "hello"')
        a = 'v = "hello" //world  '
        a_strp = rbql.strip_js_comments(a)
        self.assertEqual(a_strp, 'v = "hello"')

    def test_strip2(self):
        a = r'''v = "hel\"lo" #w'or"ld  '''
        a_strp = rbql.strip_py_comments(a)
        self.assertEqual(a_strp, r'''v = "hel\"lo"''')
        a = r'''v = "hel\"lo" //w'or"ld  '''
        a_strp = rbql.strip_js_comments(a)
        self.assertEqual(a_strp, r'''v = "hel\"lo"''')

    def test_strip3(self):
        a = r'''v = "hello\\" #w'or"ld  '''
        a_strp = rbql.strip_py_comments(a)
        self.assertEqual(a_strp, r'''v = "hello\\"''')
        a = r'''v = "hello\\" //w'or"ld  '''
        a_strp = rbql.strip_js_comments(a)
        self.assertEqual(a_strp, r'''v = "hello\\"''')

    def test_strip4(self):
        a = ''' # a comment'''
        a_strp = rbql.strip_py_comments(a)
        self.assertEqual(a_strp, '')
        a = ''' // a comment'''
        a_strp = rbql.strip_js_comments(a)
        self.assertEqual(a_strp, '')


