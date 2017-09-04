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

column_var_regex = re.compile(r'^a([1-9][0-9]*)$')
bcolumn_var_regex = re.compile(r'^b([1-9][0-9]*)$')

rbql_script_dir = os.path.dirname(os.path.realpath(__file__))

js_script_body = codecs.open(os.path.join(rbql_script_dir, 'template.js.raw'), encoding='utf-8').read()
py_script_body = codecs.open(os.path.join(rbql_script_dir, 'template.py.raw'), encoding='utf-8').read()


def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)


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


def replace_rbql_var(text):
    mtobj = column_var_regex.match(text)
    if mtobj is not None:
        column_number = int(mtobj.group(1))
        return 'safe_get(fields, {})'.format(column_number - 1)
    mtobj = bcolumn_var_regex.match(text)
    if mtobj is not None:
        column_number = int(mtobj.group(1))
        return 'safe_get(bfields, {})'.format(column_number - 1)
    return None


class RBParsingError(Exception):
    pass


def xrange6(x):
    if PY3:
        return range(x)
    return xrange(x)


def is_digit(c):
    v = ord(c)
    return v >= ord('0') and v <= ord('9')


def is_boundary(c):
    if c == '_':
        return False
    v = ord(c)
    if v >= ord('a') and v <= ord('z'):
        return False
    if v >= ord('A') and v <= ord('Z'):
        return False
    if v >= ord('0') and v <= ord('9'):
        return False
    return True


def is_escaped_quote(cline, i):
    if i == 0:
        return False
    if i == 1 and cline[i - 1] == '\\':
        return True
    #Don't fix for raw string literals: double backslash before quote is not allowed there
    if cline[i - 1] == '\\' and cline[i - 2] != '\\':
        return True
    return False


def strip_py_comments(cline):
    #TODO simplify this, don't remove comments from lines, but skip lines completely if they contain comments
    cline = cline.strip()
    cline = cline.replace('\t', ' ')
    cur_quote_mark = None
    for i in xrange6(len(cline)):
        c = cline[i]
        if cur_quote_mark is None and c == '#':
            return cline[:i].rstrip()
        if cur_quote_mark is None and (c == "'" or c == '"'):
            cur_quote_mark = c
            continue
        if cur_quote_mark is not None and c == cur_quote_mark and not is_escaped_quote(cline, i):
            cur_quote_mark = None
    return cline


def strip_js_comments(cline):
    cline = cline.strip()
    cline = cline.replace('\t', ' ')
    if cline.startswith('//'):
        return ''
    return cline


class TokenType:
    RAW = 1
    STRING_LITERAL = 2
    WHITESPACE = 3
    ALPHANUM_RAW = 4
    SYMBOL_RAW = 5


class Token:
    def __init__(self, ttype, content):
        self.ttype = ttype
        self.content = content

    def __str__(self):
        return '{}\t{}'.format(self.ttype, self.content)


def tokenize_string_literals(lines):
    result = list()
    for cline in lines:
        cur_quote_mark = None
        k = 0
        i = 0
        while i < len(cline):
            c = cline[i]
            if cur_quote_mark is None and (c == "'" or c == '"'):
                cur_quote_mark = c
                result.append(Token(TokenType.RAW, cline[k:i]))
                k = i
            elif cur_quote_mark is not None and c == cur_quote_mark and not is_escaped_quote(cline, i):
                cur_quote_mark = None
                result.append(Token(TokenType.STRING_LITERAL, cline[k:i + 1]))
                k = i + 1
            i += 1
        if k < i:
            result.append(Token(TokenType.RAW, cline[k:i]))
        result.append(Token(TokenType.WHITESPACE, ' '))
    return result


def tokenize_terms(tokens):
    result = list()
    for token in tokens:
        if token.ttype != TokenType.RAW:
            result.append(token)
            continue
        content = token.content

        i = 0
        k = 0
        in_alphanumeric = False
        while i < len(content):
            c = content[i]
            if c == ' ' or is_boundary(c):
                if k < i:
                    assert in_alphanumeric
                    result.append(Token(TokenType.ALPHANUM_RAW, content[k:i]))
                k = i + 1
                in_alphanumeric = False
                if c == ' ':
                    result.append(Token(TokenType.WHITESPACE, ' '))
                else:
                    result.append(Token(TokenType.SYMBOL_RAW, c))
            elif not in_alphanumeric:
                in_alphanumeric = True
                k = i
            i += 1
        if k < i:
            assert in_alphanumeric
            result.append(Token(TokenType.ALPHANUM_RAW, content[k:i]))
    return result


def remove_consecutive_whitespaces(tokens):
    #TODO/FIXME don't do this. may break some expressions. leave it to the parser
    result = list()
    for i in xrange6(len(tokens)):
        if (tokens[i].ttype != TokenType.WHITESPACE) or (i == 0) or (tokens[i - 1].ttype != TokenType.WHITESPACE):
            result.append(tokens[i])
    if len(result) and result[0].ttype == TokenType.WHITESPACE:
        result = result[1:]
    if len(result) and result[-1].ttype == TokenType.WHITESPACE:
        result = result[:-1]
    return result


def replace_column_vars(tokens):
    for i in xrange6(len(tokens)):
        if tokens[i].ttype == TokenType.STRING_LITERAL:
            continue
        replaced_py_var = replace_rbql_var(tokens[i].content)
        if replaced_py_var is not None:
            tokens[i].content = replaced_py_var
    return tokens


def replace_star_vars(tokens):
    for i in xrange6(len(tokens)):
        if tokens[i].ttype == TokenType.STRING_LITERAL:
            continue
        if tokens[i].content != '*':
            continue
        j = i - 1
        if j >= 0 and tokens[j].content == ' ':
            j -= 1
        if j >= 0:
            assert tokens[j].content != ' '
            if not tokens[j].content.endswith(','):
                continue
        j = i + 1
        if j < len(tokens) and tokens[j].content == ' ':
            j += 1
        if j < len(tokens):
            assert tokens[j].content != ' '
            if not tokens[j].content.startswith(','):
                continue
        tokens[i].content = 'star_line'
    return tokens


def join_tokens(tokens):
    return ''.join([t.content for t in tokens]).strip()


class Pattern:
    def __init__(self, text):
        self.text = text
        self.tokens = list()
        fields = text.split(' ')
        for i in xrange6(len(fields)):
            self.tokens.append(Token(TokenType.ALPHANUM_RAW, fields[i]))
            if i + 1 < len(fields):
                self.tokens.append(Token(TokenType.WHITESPACE, ' '))
        self.size = len(self.tokens)


def consume_action(patterns, tokens, idx):
    if tokens[idx].ttype == TokenType.STRING_LITERAL:
        return (None, idx + 1)
    for pattern in patterns:
        if idx + pattern.size >= len(tokens):
            continue
        input_slice = tokens[idx:idx + pattern.size]
        if [t.content.upper() for t in input_slice] != [t.content for t in pattern.tokens]:
            continue
        if [t.ttype for t in input_slice] != [t.ttype for t in pattern.tokens]:
            continue
        return (pattern.text, idx + pattern.size)
    return (None, idx + 1)


def strip_tokens(tokens):
    while len(tokens) and tokens[0].content == ' ':
        tokens = tokens[1:]
    while len(tokens) and tokens[-1].content == ' ':
        tokens = tokens[:-1]
    return tokens


def separate_actions(tokens):
    result = dict()
    prev_action = None
    k = 0
    i = 0
    patterns = [STRICT_LEFT_JOIN, LEFT_JOIN, INNER_JOIN, JOIN, SELECT_DISTINCT, SELECT, SELECT_TOP, ORDER_BY, WHERE]
    patterns = sorted(patterns, key=len, reverse=True)
    patterns = [Pattern(p) for p in patterns]
    while i < len(tokens):
        action, i_next = consume_action(patterns, tokens, i)
        if action is None:
            i = i_next
            continue
        if prev_action is not None:
            result[prev_action] = strip_tokens(tokens[k:i])
        if action in result:
            raise RBParsingError('More than one "{}" statements found'.format(action))
        prev_action = action
        i = i_next
        k = i
    if prev_action is not None:
        result[prev_action] = strip_tokens(tokens[k:i])
    return result


def escape_delim(delim):
    if delim == '\t':
        return '\\t'
    return delim


def parse_join_expression(tokens):
    syntax_err_msg = 'Incorrect join syntax. Must be: "<JOIN> /path/to/B/table on a<i> == b<j>"'
    tokens = join_tokens(tokens).split(' ')
    if len(tokens) != 5 or tokens[1].upper() != 'ON' or tokens[3] != '==':
        raise RBParsingError(syntax_err_msg)
    if column_var_regex.match(tokens[4]) is not None:
        tokens[2], tokens[4] = tokens[4], tokens[2]
    if column_var_regex.match(tokens[2]) is None or bcolumn_var_regex.match(tokens[4]) is None:
        raise RBParsingError(syntax_err_msg)
    return (tokens[0], replace_rbql_var(tokens[2]), replace_rbql_var(tokens[4]))


def parse_to_py(rbql_lines, py_dst, delim, join_csv_encoding=default_csv_encoding, import_modules=None):
    if not py_dst.endswith('.py'):
        raise RBParsingError('python module file must have ".py" extension')

    for il in xrange6(len(rbql_lines)):
        cline = rbql_lines[il]
        if cline.find("'''") != -1 or cline.find('"""') != -1: #TODO remove this condition after improving column_vars replacement logic
            raise RBParsingError('In line {}. Multiline python comments and doc strings are not allowed in rbql'.format(il + 1))
        rbql_lines[il] = strip_py_comments(cline)

    rbql_lines = [l for l in rbql_lines if len(l)]

    tokens = tokenize_string_literals(rbql_lines)
    tokens = tokenize_terms(tokens)
    tokens = remove_consecutive_whitespaces(tokens)
    rb_actions = separate_actions(tokens)

    select_op = None
    writer_name = None
    select_ops = {SELECT: 'SimpleWriter', SELECT_TOP: 'SimpleWriter', SELECT_DISTINCT: 'UniqWriter'}
    for k, v in select_ops.items():
        if k in rb_actions:
            select_op = k
            writer_name = v

    if select_op is None:
        raise RBParsingError('"SELECT" statement not found')

    joiner_name = 'none_joiner'
    join_op = None
    rhs_table_path = None
    lhs_join_var = None
    rhs_join_var = None
    join_ops = {JOIN: 'InnerJoiner', INNER_JOIN: 'InnerJoiner', LEFT_JOIN: 'LeftJoiner', STRICT_LEFT_JOIN: 'StrictLeftJoiner'}
    for k, v in join_ops.items():
        if k in rb_actions:
            join_op = k
            joiner_name = v

    if join_op is not None:
        rhs_table_path, lhs_join_var, rhs_join_var = parse_join_expression(rb_actions[join_op])

    py_meta_params = dict()
    import_expression = ''
    if import_modules is not None:
        for mdl in import_modules:
            import_expression += 'import {}\n'.format(mdl)
    py_meta_params['import_expression'] = import_expression
    py_meta_params['dlm'] = escape_delim(delim)
    py_meta_params['join_encoding'] = join_csv_encoding
    py_meta_params['rhs_join_var'] = rhs_join_var
    py_meta_params['writer_type'] = writer_name
    py_meta_params['joiner_type'] = joiner_name
    py_meta_params['rhs_table_path'] = rhs_table_path
    py_meta_params['lhs_join_var'] = lhs_join_var
    py_meta_params['where_expression'] = 'True'
    if WHERE in rb_actions:
        py_meta_params['where_expression'] = join_tokens(replace_column_vars(rb_actions[WHERE]))
    py_meta_params['top_count'] = -1
    if select_op == SELECT_TOP:
        try:
            py_meta_params['top_count'] = int(rb_actions[select_op][0].content)
            assert rb_actions[select_op][1].content == ' '
            rb_actions[select_op] = rb_actions[select_op][2:]
        except Exception:
            raise RBParsingError('Unable to parse "TOP" expression')
    select_tokens = replace_column_vars(rb_actions[select_op])
    select_tokens = replace_star_vars(select_tokens)
    if not len(select_tokens):
        raise RBParsingError('"SELECT" expression is empty')
    select_expression = join_tokens(select_tokens)
    py_meta_params['select_expression'] = select_expression

    py_meta_params['sort_flag'] = 'False'
    py_meta_params['reverse_flag'] = 'False'
    py_meta_params['sort_key_expression'] = 'None'
    if ORDER_BY in rb_actions:
        py_meta_params['sort_flag'] = 'True'
        order_expression = join_tokens(replace_column_vars(rb_actions[ORDER_BY]))
        direction_marker = ' DESC'
        if order_expression.upper().endswith(direction_marker):
            order_expression = order_expression[:-len(direction_marker)].rstrip()
            py_meta_params['reverse_flag'] = 'True'
        direction_marker = ' ASC'
        if order_expression.upper().endswith(direction_marker):
            order_expression = order_expression[:-len(direction_marker)].rstrip()
        py_meta_params['sort_key_expression'] = order_expression

    with codecs.open(py_dst, 'w', encoding='utf-8') as dst:
        dst.write(py_script_body.format(**py_meta_params))


def parse_to_js(src_table_path, dst_table_path, rbql_lines, js_dst, delim, csv_encoding=default_csv_encoding, import_modules=None):
    for il in xrange6(len(rbql_lines)):
        cline = rbql_lines[il]
        rbql_lines[il] = strip_js_comments(cline)

    rbql_lines = [l for l in rbql_lines if len(l)]

    tokens = tokenize_string_literals(rbql_lines)
    tokens = tokenize_terms(tokens)
    tokens = remove_consecutive_whitespaces(tokens)
    rb_actions = separate_actions(tokens)

    select_op = None
    writer_name = None
    select_ops = {SELECT: 'SimpleWriter', SELECT_TOP: 'SimpleWriter', SELECT_DISTINCT: 'UniqWriter'}
    for k, v in select_ops.items():
        if k in rb_actions:
            select_op = k
            writer_name = v

    if select_op is None:
        raise RBParsingError('"SELECT" statement not found')

    join_function = 'null_join'
    join_op = None
    rhs_table_path = 'null'
    lhs_join_var = None
    rhs_join_var = None
    join_funcs = {JOIN: 'inner_join', INNER_JOIN: 'inner_join', LEFT_JOIN: 'left_join', STRICT_LEFT_JOIN: 'strict_left_join'}
    for k, v in join_funcs.items():
        if k in rb_actions:
            join_op = k
            join_function = v

    if join_op is not None:
        rhs_table_path, lhs_join_var, rhs_join_var = parse_join_expression(rb_actions[join_op])
        rhs_table_path = "'{}'".format(rhs_table_path)

    js_meta_params = dict()
    #TODO require modules feature
    js_meta_params['dlm'] = escape_delim(delim)
    js_meta_params['csv_encoding'] = 'binary' if csv_encoding == 'latin-1' else csv_encoding
    js_meta_params['rhs_join_var'] = rhs_join_var
    js_meta_params['writer_type'] = writer_name
    js_meta_params['join_function'] = join_function
    js_meta_params['src_table_path'] = "null" if src_table_path is None else "'{}'".format(src_table_path)
    js_meta_params['dst_table_path'] = "null" if dst_table_path is None else "'{}'".format(dst_table_path)
    js_meta_params['rhs_table_path'] = rhs_table_path
    js_meta_params['lhs_join_var'] = lhs_join_var
    js_meta_params['where_expression'] = 'true'
    if WHERE in rb_actions:
        js_meta_params['where_expression'] = join_tokens(replace_column_vars(rb_actions[WHERE]))
    js_meta_params['top_count'] = -1
    if select_op == SELECT_TOP:
        try:
            js_meta_params['top_count'] = int(rb_actions[select_op][0].content)
            assert rb_actions[select_op][1].content == ' '
            rb_actions[select_op] = rb_actions[select_op][2:]
        except Exception:
            raise RBParsingError('Unable to parse "TOP" expression')
    select_tokens = replace_column_vars(rb_actions[select_op])
    select_tokens = replace_star_vars(select_tokens)
    if not len(select_tokens):
        raise RBParsingError('"SELECT" expression is empty')
    select_expression = join_tokens(select_tokens)
    js_meta_params['select_expression'] = select_expression

    js_meta_params['sort_flag'] = 'false'
    js_meta_params['reverse_flag'] = 'false'
    js_meta_params['sort_key_expression'] = 'None'
    if ORDER_BY in rb_actions:
        js_meta_params['sort_flag'] = 'true'
        order_expression = join_tokens(replace_column_vars(rb_actions[ORDER_BY]))
        direction_marker = ' DESC'
        if order_expression.upper().endswith(direction_marker):
            order_expression = order_expression[:-len(direction_marker)].rstrip()
            js_meta_params['reverse_flag'] = 'true'
        direction_marker = ' ASC'
        if order_expression.upper().endswith(direction_marker):
            order_expression = order_expression[:-len(direction_marker)].rstrip()
        js_meta_params['sort_key_expression'] = order_expression

    with codecs.open(js_dst, 'w', encoding='utf-8') as dst:
        dst.write(js_script_body.format(**js_meta_params))


def system_has_node_js():
    import subprocess
    error_code = 0
    out_data = ''
    try:
        cmd = ['node', '--version']
        pobj = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        out_data, err_data = pobj.communicate()
        error_code = pobj.returncode
    except OSError as e:
        if e.errno == 2:
            return False
        raise
    return error_code == 0 and len(out_data) and len(err_data) == 0


def print_error_and_exit(error_msg):
    eprint(error_msg)
    sys.exit(1)


def run_with_python(args):
    import time
    import tempfile
    delim = args.delim
    query = args.query
    query_path = args.query_file
    #convert_only = args.convert_only
    input_path = args.input_table_path
    output_path = args.output_table_path
    import_modules = args.libs
    csv_encoding = args.csv_encoding

    rbql_lines = None
    if query is None and query_path is None:
        print_error_and_exit('Error: provide either "--query" or "--query_path" option')
    if query is not None and query_path is not None:
        print_error_and_exit('Error: unable to use both "--query" and "--query_path" options')
    if query_path is not None:
        assert query is None
        rbql_lines = codecs.open(query_path, encoding='utf-8').readlines()
    else:
        assert query_path is None
        rbql_lines = [query]

    tmp_dir = tempfile.gettempdir()

    module_name = 'rbconvert_{}'.format(time.time()).replace('.', '_')
    module_filename = '{}.py'.format(module_name)
    tmp_path = os.path.join(tmp_dir, module_filename)
    sys.path.insert(0, tmp_dir)

    try:
        parse_to_py(rbql_lines, tmp_path, delim, csv_encoding, import_modules)
    except RBParsingError as e:
        print_error_and_exit('RBQL Parsing Error: \t{}'.format(e))
    if not os.path.isfile(tmp_path) or not os.access(tmp_path, os.R_OK):
        print_error_and_exit('Error: Unable to find generated python module at {}.'.format(tmp_path))
    try:
        rbconvert = dynamic_import(module_name)
        src = None
        if input_path:
            src = codecs.open(input_path, encoding=csv_encoding)
        else:
            src = get_encoded_stdin(csv_encoding)
        if output_path:
            with codecs.open(output_path, 'w', encoding=csv_encoding) as dst:
                rbconvert.rb_transform(src, dst)
        else:
            dst = get_encoded_stdout(csv_encoding)
            rbconvert.rb_transform(src, dst)
    except Exception as e:
        error_msg = 'Error: Unable to use generated python module.\n'
        error_msg += 'Location of the generated module: {}\n\n'.format(tmp_path)
        error_msg += 'Original python exception:\n{}\n'.format(str(e))
        print_error_and_exit(error_msg)


def run_with_js(args):
    import time
    import tempfile
    import subprocess
    if not system_has_node_js():
        print_error_and_exit('Error: Node.js is not found, test command: "node --version"')
    delim = args.delim
    query = args.query
    query_path = args.query_file
    #convert_only = args.convert_only
    input_path = args.input_table_path
    output_path = args.output_table_path
    import_modules = args.libs
    csv_encoding = args.csv_encoding

    rbql_lines = None
    if query is None and query_path is None:
        print_error_and_exit('Error: provide either "--query" or "--query_path" option')
    if query is not None and query_path is not None:
        print_error_and_exit('Error: unable to use both "--query" and "--query_path" options')
    if query_path is not None:
        assert query is None
        rbql_lines = codecs.open(query_path, encoding='utf-8').readlines()
    else:
        assert query_path is None
        rbql_lines = [query]

    tmp_dir = tempfile.gettempdir()
    script_filename = 'rbconvert_{}'.format(time.time()).replace('.', '_') + '.js'
    tmp_path = os.path.join(tmp_dir, script_filename)
    parse_to_js(input_path, output_path, rbql_lines, tmp_path, delim, csv_encoding, import_modules)
    cmd = ['node', tmp_path]
    pobj = subprocess.Popen(cmd, stderr=subprocess.PIPE)
    err_data = pobj.communicate()[1]
    error_code = pobj.returncode
    if len(err_data) or error_code != 0:
        if not len(err_data):
            err_data = 'Unknown Error'
        else:
            err_data = err_data.decode('latin-1')
        print_error_and_exit('An error occured during js script execution:\n\n{}\n\n================================================\nGenerated script location: {}'.format(err_data, tmp_path))


def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--delim', help='Delimiter', default=r'\t')
    parser.add_argument('--query', help='Query string in rbql')
    parser.add_argument('--query_file', metavar='FILE', help='Read rbql query from FILE')
    parser.add_argument('--input_table_path', metavar='FILE', help='Read csv table from FILE instead of stdin')
    parser.add_argument('--output_table_path', metavar='FILE', help='Write output table to FILE instead of stdout')
    parser.add_argument('--meta_language', metavar='LANG', help='script language to use in query', default='python', choices=['python', 'js'])
    #parser.add_argument('--convert_only', action='store_true', help='Only generate script do not run query on csv table')
    parser.add_argument('--csv_encoding', help='Manually set csv table encoding', default=default_csv_encoding, choices=['latin-1', 'utf-8'])
    parser.add_argument('-I', dest='libs', action='append', help='Import module to use in the result conversion script')
    args = parser.parse_args()
    if args.meta_language == 'python':
        run_with_python(args)
    else:
        run_with_js(args)



if __name__ == '__main__':
    main()
