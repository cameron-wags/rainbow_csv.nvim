#!/usr/bin/env python
# -*- coding: utf-8 -*-
from __future__ import unicode_literals
from __future__ import print_function

import sys
import os
import re
import importlib
import codecs
import io


#This module must be both python2 and python3 compatible


UPDATE = 'UPDATE'
SELECT = 'SELECT'
SELECT_TOP = 'SELECT TOP'
SELECT_DISTINCT = 'SELECT DISTINCT'
JOIN = 'JOIN'
INNER_JOIN = 'INNER JOIN'
LEFT_JOIN = 'LEFT JOIN'
STRICT_LEFT_JOIN = 'STRICT LEFT JOIN'
ORDER_BY = 'ORDER BY'
WHERE = 'WHERE'


default_csv_encoding = 'latin-1'

PY3 = sys.version_info[0] == 3

rbql_home_dir = os.path.dirname(os.path.realpath(__file__))

js_script_body = codecs.open(os.path.join(rbql_home_dir, 'template.js.raw'), encoding='utf-8').read()
py_script_body = codecs.open(os.path.join(rbql_home_dir, 'template.py.raw'), encoding='utf-8').read()


def normalize_delim(delim):
    if delim == r'\t':
        return '\t'
    return delim


def dynamic_import(module_name):
    try:
        importlib.invalidate_caches()
    except AttributeError:
        pass
    return importlib.import_module(module_name)


def get_encoded_stdin(encoding_name):
    if PY3:
        return io.TextIOWrapper(sys.stdin.buffer, encoding=encoding_name)
    else:
        return codecs.getreader(encoding_name)(sys.stdin)


def get_encoded_stdout(encoding_name):
    if PY3:
        return io.TextIOWrapper(sys.stdout.buffer, encoding=encoding_name)
    else:
        return codecs.getwriter(encoding_name)(sys.stdout)


def xrange6(x):
    if PY3:
        return range(x)
    return xrange(x)


def rbql_meta_format(template_src, meta_params):
    for k, v in meta_params.items():
        template_marker = '__RBQLMP__{}'.format(k)
        #TODO make special replace for multiple statements, like in update, it should be indent-aware
        template_src = template_src.replace(template_marker, v)
    return template_src


def remove_if_possible(file_path):
    try:
        os.remove(file_path)
    except Exception:
        pass


class RBParsingError(Exception):
    pass


def strip_py_comments(cline):
    cline = cline.strip()
    if cline.startswith('#'):
        return ''
    return cline


def strip_js_comments(cline):
    cline = cline.strip()
    if cline.startswith('//'):
        return ''
    return cline


def py_source_escape(src):
    result = src.replace('\\', '\\\\')
    result = result.replace('\t', '\\t')
    return result


def parse_join_expression(src):
    match = re.match(r'(?i)^ *([^ ]+) +on +([ab][0-9]+) *== *([ab][0-9]+) *$', src)
    if match is None:
        raise RBParsingError('Incorrect join syntax. Must be: "<JOIN> /path/to/B/table on a<i> == b<j>"')
    table_path = match.group(1)
    avar = match.group(2)
    bvar = match.group(3)
    if avar[0] == 'b':
        avar, bvar = bvar, avar
    if avar[0] != 'a' or bvar[0] != 'b':
        raise RBParsingError('Incorrect join syntax. Must be: "<JOIN> /path/to/B/table on a<i> == b<j>"')
    lhs_join_var = 'safe_get(afields, {})'.format(int(avar[1:]))
    rhs_join_var = 'safe_get(bfields, {})'.format(int(bvar[1:]))
    return (table_path, lhs_join_var, rhs_join_var)


def replace_column_vars(rbql_expression):
    translated = re.sub('(?:^|(?<=[^_a-zA-Z0-9]))([ab])([1-9][0-9]*)(?:$|(?=[^_a-zA-Z0-9]))', r'safe_get(\1fields, \2)', rbql_expression)
    return translated


def replace_star_vars_py(rbql_expression):
    rbql_expression = re.sub(r'(?:^|,) *\* *(?=, *\* *($|,))', '] + star_fields + [', rbql_expression)
    rbql_expression = re.sub(r'(?:^|,) *\* *(?:$|,)', '] + star_fields + [', rbql_expression)
    return rbql_expression


def replace_star_vars_js(rbql_expression):
    rbql_expression = re.sub(r'(?:^|,) *\* *(?=, *\* *($|,))', ']).concat(star_fields).concat([', rbql_expression)
    rbql_expression = re.sub(r'(?:^|,) *\* *(?:$|,)', ']).concat(star_fields).concat([', rbql_expression)
    return rbql_expression


def translate_update_expression(update_expression, indent):
    translated = re.sub('(?:^|,) *a([1-9][0-9]*) *=(?=[^=])', '\nsafe_set(afields, \\1,', update_expression)
    update_statements = translated.split('\n')
    update_statements = [s.strip() for s in update_statements]
    if len(update_statements) < 2 or len(update_statements[0]) > 0:
        raise RBParsingError('Unable to parse "UPDATE" expression')
    update_statements = update_statements[1:]
    update_statements = ['{})'.format(s) for s in update_statements]
    for i in range(1, len(update_statements)):
        update_statements[i] = indent + update_statements[i]
    translated = '\n'.join(update_statements)
    translated = replace_column_vars(translated)
    return translated


def translate_select_expression_py(select_expression):
    translated = replace_column_vars(select_expression)
    translated = replace_star_vars_py(translated)
    translated = translated.strip()
    if not len(translated):
        raise RBParsingError('"SELECT" expression is empty')
    return '[{}]'.format(translated)


def translate_select_expression_js(select_expression):
    translated = replace_column_vars(select_expression)
    translated = replace_star_vars_js(translated)
    translated = translated.strip()
    if not len(translated):
        raise RBParsingError('"SELECT" expression is empty')
    return '[].concat([{}])'.format(translated)


def separate_string_literals_py(rbql_expression):
    string_literals_regex = r'''(\"\"\"|\'\'\'|\"|\')((?<!\\)(\\\\)*\\\1|.)*?\1'''
    return do_separate_string_literals(rbql_expression, string_literals_regex)


def separate_string_literals_js(rbql_expression):
    string_literals_regex = r'''(`|\"|\')((?<!\\)(\\\\)*\\\1|.)*?\1'''
    return do_separate_string_literals(rbql_expression, string_literals_regex)


def do_separate_string_literals(rbql_expression, string_literals_regex):
    # regex is improved expression from here: https://stackoverflow.com/a/14366904/2898283
    matches = list(re.finditer(string_literals_regex, rbql_expression))
    string_literals = list()
    format_parts = list()
    idx_before = 0
    for m in matches:
        literal_id = len(string_literals)
        string_literals.append(m.group(0))
        format_parts.append(rbql_expression[idx_before:m.start()])
        format_parts.append('###RBQL_STRING_LITERAL###{}'.format(literal_id))
        idx_before = m.end()
    format_parts.append(rbql_expression[idx_before:])
    format_expression = ''.join(format_parts)
    format_expression = format_expression.replace('\t', ' ')
    return (format_expression, string_literals)


def combine_string_literals(host_expression, string_literals):
    for i in range(len(string_literals)):
        host_expression = host_expression.replace('###RBQL_STRING_LITERAL###{}'.format(i), string_literals[i])
    return host_expression


def locate_statements(rbql_expression):
    statement_groups = list()
    statement_groups.append([STRICT_LEFT_JOIN, LEFT_JOIN, INNER_JOIN, JOIN])
    statement_groups.append([SELECT])
    statement_groups.append([ORDER_BY])
    statement_groups.append([WHERE])
    statement_groups.append([UPDATE])

    result = list()
    for st_group in statement_groups:
        for statement in st_group:
            rgxp = None
            rgxp = r'(?i)(?:^| ){} '.format(statement.replace(' ', ' *'))
            matches = list(re.finditer(rgxp, rbql_expression))
            if not len(matches):
                continue
            if len(matches) > 1:
                raise RBParsingError('More than one "{}" statements found'.format(statement))
            assert len(matches) == 1
            match = matches[0]
            result.append((match.start(), match.end(), statement))
            break #there must be only one statement maximum in each group
    return sorted(result)


def separate_actions(rbql_expression):
    #TODO add more checks: 
    #make sure all rbql_expression was separated and SELECT or UPDATE is at the beginning
    ordered_statements = locate_statements(rbql_expression)
    result = dict()
    for i in range(len(ordered_statements)):
        statement_start = ordered_statements[i][0]
        span_start = ordered_statements[i][1]
        statement = ordered_statements[i][2]
        result[statement] = dict()
        span_end = ordered_statements[i + 1][0] if i + 1 < len(ordered_statements) else len(rbql_expression)
        assert statement_start < span_start
        assert span_start <= span_end
        span = rbql_expression[span_start:span_end]

        if statement == UPDATE:
            if len(result) > 1:
                raise RBParsingError('UPDATE must be the first statement in query')
            span = re.sub('(?i)^ *SET ', '', span)

        if statement == ORDER_BY:
            span = re.sub('(?i) ASC *$', '', span)
            new_span = re.sub('(?i) DESC *$', '', span)
            if new_span != span:
                span = new_span
                result[statement]['reverse'] = True
            else:
                result[statement]['reverse'] = False

        if statement == SELECT:
            if len(result) > 1:
                raise RBParsingError('SELECT must be the first statement in query')
            match = re.match('(?i)^ *TOP *([0-9]+) ', span)
            if match is not None:
                result[statement]['top'] = int(match.group(1))
                span = span[match.end():]
            match = re.match('(?i)^ *DISTINCT *(COUNT)? ', span)
            if match is not None:
                result[statement]['distinct'] = True
                if match.group(1) is not None:
                    result[statement]['distinct_count'] = True
                span = span[match.end():]

        result[statement]['text'] = span.strip()
    if SELECT not in result and UPDATE not in result:
        raise RBParsingError('Query must contain either SELECT or UPDATE statement')
    assert (SELECT in result) != (UPDATE in result)
    return result


def parse_to_py(rbql_lines, py_dst, delim, join_csv_encoding=default_csv_encoding, import_modules=None):
    if not py_dst.endswith('.py'):
        raise RBParsingError('python module file must have ".py" extension')

    rbql_lines = [strip_py_comments(l) for l in rbql_lines]
    rbql_lines = [l for l in rbql_lines if len(l)]
    full_rbql_expression = ' '.join(rbql_lines)
    format_expression, string_literals = separate_string_literals_py(full_rbql_expression)
    rb_actions = separate_actions(format_expression)

    #TODO refactor: try to convert all join ops into one with params
    joiner_name = 'none_joiner'
    join_op = None
    rhs_table_path = 'None'
    lhs_join_var = 'None'
    rhs_join_var = 'None'
    join_ops = {JOIN: 'InnerJoiner', INNER_JOIN: 'InnerJoiner', LEFT_JOIN: 'LeftJoiner', STRICT_LEFT_JOIN: 'StrictLeftJoiner'}
    for k, v in join_ops.items():
        if k in rb_actions:
            join_op = k
            joiner_name = v

    if join_op is not None:
        rhs_table_path, lhs_join_var, rhs_join_var = parse_join_expression(rb_actions[join_op]['text'])

    import_expression = ''
    if import_modules is not None:
        for mdl in import_modules:
            import_expression += 'import {}\n'.format(mdl)

    py_meta_params = dict()
    py_meta_params['rbql_home_dir'] = py_source_escape(rbql_home_dir)
    py_meta_params['import_expression'] = import_expression
    py_meta_params['dlm'] = py_source_escape(delim)
    py_meta_params['join_encoding'] = join_csv_encoding
    py_meta_params['rhs_join_var'] = rhs_join_var
    py_meta_params['joiner_type'] = joiner_name
    py_meta_params['rhs_table_path'] = py_source_escape(rhs_table_path)
    py_meta_params['lhs_join_var'] = lhs_join_var

    if WHERE in rb_actions:
        where_expression = replace_column_vars(rb_actions[WHERE]['text'])
        py_meta_params['where_expression'] = combine_string_literals(where_expression, string_literals)
    else:
        py_meta_params['where_expression'] = 'True'

    if UPDATE in rb_actions:
        update_expression = translate_update_expression(rb_actions[UPDATE]['text'], ' ' * 20)
        py_meta_params['writer_type'] = 'SimpleWriter'
        py_meta_params['select_expression'] = 'None'
        py_meta_params['update_statements'] = combine_string_literals(update_expression, string_literals)
        py_meta_params['is_select_query'] = 'False'
        py_meta_params['top_count'] = 'None'

    if SELECT in rb_actions:
        top_count = rb_actions[SELECT].get('top', None)
        py_meta_params['top_count'] = str(top_count) if top_count is not None else 'None'
        if 'distinct_count' in rb_actions[SELECT]:
            py_meta_params['writer_type'] = 'UniqCountWriter'
        elif 'distinct' in rb_actions[SELECT]:
            py_meta_params['writer_type'] = 'UniqWriter'
        else:
            py_meta_params['writer_type'] = 'SimpleWriter'
        select_expression = translate_select_expression_py(rb_actions[SELECT]['text'])
        py_meta_params['select_expression'] = combine_string_literals(select_expression, string_literals)
        py_meta_params['update_statements'] = 'pass'
        py_meta_params['is_select_query'] = 'True'

    if ORDER_BY in rb_actions:
        order_expression = replace_column_vars(rb_actions[ORDER_BY]['text'])
        py_meta_params['sort_key_expression'] = combine_string_literals(order_expression, string_literals)
        py_meta_params['reverse_flag'] = 'True' if rb_actions[ORDER_BY]['reverse'] else 'False'
        py_meta_params['sort_flag'] = 'True'
    else:
        py_meta_params['sort_key_expression'] = 'None'
        py_meta_params['reverse_flag'] = 'False'
        py_meta_params['sort_flag'] = 'False'

    with codecs.open(py_dst, 'w', encoding='utf-8') as dst:
        dst.write(rbql_meta_format(py_script_body, py_meta_params))


def parse_to_js(src_table_path, dst_table_path, rbql_lines, js_dst, delim, csv_encoding=default_csv_encoding, import_modules=None):
    rbql_lines = [strip_js_comments(l) for l in rbql_lines]
    rbql_lines = [l for l in rbql_lines if len(l)]
    full_rbql_expression = ' '.join(rbql_lines)
    format_expression, string_literals = separate_string_literals_js(full_rbql_expression)
    rb_actions = separate_actions(format_expression)

    join_function = 'null_join'
    join_op = None
    rhs_table_path = 'null'
    lhs_join_var = 'null'
    rhs_join_var = 'null'
    join_funcs = {JOIN: 'inner_join', INNER_JOIN: 'inner_join', LEFT_JOIN: 'left_join', STRICT_LEFT_JOIN: 'strict_left_join'}
    for k, v in join_funcs.items():
        if k in rb_actions:
            join_op = k
            join_function = v
    if join_op is not None:
        rhs_table_path, lhs_join_var, rhs_join_var = parse_join_expression(rb_actions[join_op]['text'])
        rhs_table_path = "'{}'".format(rhs_table_path)

    js_meta_params = dict()
    #TODO require modules feature
    js_meta_params['rbql_home_dir'] = py_source_escape(rbql_home_dir)
    js_meta_params['dlm'] = py_source_escape(delim)
    js_meta_params['csv_encoding'] = 'binary' if csv_encoding == 'latin-1' else csv_encoding
    js_meta_params['rhs_join_var'] = rhs_join_var
    js_meta_params['join_function'] = join_function
    js_meta_params['src_table_path'] = "null" if src_table_path is None else "'{}'".format(py_source_escape(src_table_path))
    js_meta_params['dst_table_path'] = "null" if dst_table_path is None else "'{}'".format(py_source_escape(dst_table_path))
    js_meta_params['rhs_table_path'] = py_source_escape(rhs_table_path)
    js_meta_params['lhs_join_var'] = lhs_join_var

    if WHERE in rb_actions:
        where_expression = replace_column_vars(rb_actions[WHERE]['text'])
        js_meta_params['where_expression'] = combine_string_literals(where_expression, string_literals)
    else:
        js_meta_params['where_expression'] = 'true'

    if UPDATE in rb_actions:
        update_expression = translate_update_expression(rb_actions[UPDATE]['text'], ' ' * 16)
        js_meta_params['writer_type'] = 'SimpleWriter'
        js_meta_params['select_expression'] = 'null'
        js_meta_params['update_statements'] = combine_string_literals(update_expression, string_literals)
        js_meta_params['is_select_query'] = 'false'
        js_meta_params['top_count'] = 'null'

    if SELECT in rb_actions:
        top_count = rb_actions[SELECT].get('top', None)
        js_meta_params['top_count'] = str(top_count) if top_count is not None else 'null'
        if 'distinct_count' in rb_actions[SELECT]:
            js_meta_params['writer_type'] = 'UniqCountWriter'
        elif 'distinct' in rb_actions[SELECT]:
            js_meta_params['writer_type'] = 'UniqWriter'
        else:
            js_meta_params['writer_type'] = 'SimpleWriter'
        select_expression = translate_select_expression_js(rb_actions[SELECT]['text'])
        js_meta_params['select_expression'] = combine_string_literals(select_expression, string_literals)
        js_meta_params['update_statements'] = ''
        js_meta_params['is_select_query'] = 'true'

    if ORDER_BY in rb_actions:
        order_expression = replace_column_vars(rb_actions[ORDER_BY]['text'])
        js_meta_params['sort_key_expression'] = combine_string_literals(order_expression, string_literals)
        js_meta_params['reverse_flag'] = 'true' if rb_actions[ORDER_BY]['reverse'] else 'false'
        js_meta_params['sort_flag'] = 'true'
    else:
        js_meta_params['sort_key_expression'] = 'null'
        js_meta_params['reverse_flag'] = 'false'
        js_meta_params['sort_flag'] = 'false'

    with codecs.open(js_dst, 'w', encoding='utf-8') as dst:
        dst.write(rbql_meta_format(js_script_body, js_meta_params))


def system_has_node_js():
    import subprocess
    exit_code = 0
    out_data = ''
    try:
        cmd = ['node', '--version']
        pobj = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        out_data, err_data = pobj.communicate()
        exit_code = pobj.returncode
    except OSError as e:
        if e.errno == 2:
            return False
        raise
    return exit_code == 0 and len(out_data) and len(err_data) == 0


def parse_json_report(exit_code, err_data):
    err_data = err_data.decode('latin-1')
    if not len(err_data) and exit_code == 0:
        return dict()
    try:
        import json
        report = json.loads(err_data)
        if exit_code != 0 and 'error' not in report:
            report['error'] = 'Unknown error'
        return report
    except Exception:
        err_msg = err_data if len(err_data) else 'Unknown error'
        report = {'error': err_msg}
        return report


def make_inconsistent_num_fields_hr_warning(table_name, inconsistent_lines_info):
    assert len(inconsistent_lines_info) > 1
    inconsistent_lines_info = inconsistent_lines_info.items()
    inconsistent_lines_info = sorted(inconsistent_lines_info, key=lambda v: v[1])
    num_fields_1, lnum_1 = inconsistent_lines_info[0]
    num_fields_2, lnum_2 = inconsistent_lines_info[1]
    warn_msg = 'Number of fields in {} table is not consistent. '.format(table_name)
    warn_msg += 'E.g. there are {} fields at line {}, and {} fields at line {}.'.format(num_fields_1, lnum_1, num_fields_2, lnum_2)
    return warn_msg


def make_warnings_human_readable(warnings):
    result = list()
    for warning_type, warning_value in warnings.items():
        if warning_type == 'null_value_in_output':
            result.append('None/null values in output were replaced by empty strings.')
        elif warning_type == 'defective_csv_line_in_input':
            result.append('Defective double quote escaping in input table. E.g. at line {}.'.format(warning_value))
        elif warning_type == 'defective_csv_line_in_join':
            result.append('Defective double quote escaping in join table. E.g. at line {}.'.format(warning_value))
        elif warning_type == 'output_fields_info':
            result.append(make_inconsistent_num_fields_hr_warning('output', warning_value))
        elif warning_type == 'input_fields_info':
            result.append(make_inconsistent_num_fields_hr_warning('input', warning_value))
        elif warning_type == 'join_fields_info':
            result.append(make_inconsistent_num_fields_hr_warning('join', warning_value))
        else:
            raise RuntimeError('Error: unknown warning type: {}'.format(warning_type))
    for w in result:
        assert w.find('\n') == -1
    return result


