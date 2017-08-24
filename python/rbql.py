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


column_var_regex = re.compile(r'^a([1-9][0-9]*)$')
bcolumn_var_regex = re.compile(r'^b([1-9][0-9]*)$')


def replace_rbql_var(text):
    mtobj = column_var_regex.match(text)
    if mtobj is not None:
        column_number = int(mtobj.group(1))
        return 'fields[{}]'.format(column_number - 1)
    mtobj = bcolumn_var_regex.match(text)
    if mtobj is not None:
        column_number = int(mtobj.group(1))
        return 'bfields[{}]'.format(column_number - 1)
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


def strip_comments(cline):
    cline = cline.rstrip()
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
        return '{}\t{}'.join(self.ttype, self.content)


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




py_script_body = r'''#!/usr/bin/env python
# -*- coding: utf-8 -*-
from __future__ import unicode_literals
import sys
import os
import random #for random sort
import datetime #for date manipulations
import re #for regexes
import codecs

{import_expression}


PY3 = sys.version_info[0] == 3

def str6(obj):
    if PY3 and isinstance(obj, str):
        return obj
    if not PY3 and isinstance(obj, basestring):
        return obj
    return str(obj)

DLM = '{dlm}'

def rows(f, chunksize=1024, sep='\n'):
    incomplete_row = None
    while True:
        chunk = f.read(chunksize)
        if not chunk:
            if incomplete_row is not None and len(incomplete_row):
                yield incomplete_row
            return
        while True:
            i = chunk.find(sep)
            if i == -1:
                break
            if incomplete_row is not None:
                yield incomplete_row + chunk[:i]
                incomplete_row = None
            else:
                yield chunk[:i]
            chunk = chunk[i+1:]
        if incomplete_row is not None:
            incomplete_row += chunk
        else:
            incomplete_row = chunk


class BadFieldError(Exception):
    def __init__(self, bad_idx):
        self.bad_idx = bad_idx

class RbqlRuntimeError(Exception):
    pass


class rbql_list(list):
    def __getitem__(self, idx):
        try:
            v = super(rbql_list, self).__getitem__(idx)
        except IndexError as e:
            raise BadFieldError(idx)
        return v


class Flike:
    def __init__(self):
        self._cache = dict()

    def _like_to_regex(self, pattern):
        p = 0
        i = 0
        converted = ''
        while i < len(pattern):
            if pattern[i] in ['_', '%']:
                converted += re.escape(pattern[p:i])
                p = i + 1
                if pattern[i] == '_':
                    converted += '.'
                else:
                    converted += '.*'
            i += 1
        converted += re.escape(pattern[p:i])
        return '^' + converted + '$'

    def __call__(self, text, pattern):
        if pattern not in self._cache:
            rgx = self._like_to_regex(pattern)
            self._cache[pattern] = re.compile(rgx)
        return self._cache[pattern].match(text) is not None

flike = Flike()


class SimpleWriter:
    def __init__(self, dst):
        self.dst = dst
        self.NW = 0

    def write(self, record):
        self.dst.write(record)
        self.dst.write('\n')
        self.NW += 1


class UniqWriter:
    def __init__(self, dst):
        self.dst = dst
        self.seen = set()

    def write(self, record):
        if record in self.seen:
            return
        self.seen.add(record)
        self.dst.write(record)
        self.dst.write('\n')


def read_join_table(join_table_path):
    fields_max_len = 0
    if not os.path.isfile(join_table_path):
        raise RbqlRuntimeError('Table B: ' + join_table_path + ' is not accessible')
    result = dict()
    with codecs.open(join_table_path, encoding='{join_encoding}') as src_text:
        for il, line in enumerate(rows(src_text), 1):
            line = line.rstrip('\r\n')
            bfields = rbql_list(line.split(DLM))
            fields_max_len = max(fields_max_len, len(bfields))
            try:
                key = {rhs_join_var}
            except BadFieldError as e:
                bad_idx = e.bad_idx
                raise RbqlRuntimeError('No "b' + str(bad_idx + 1) + '" column at line: ' + str(il) + ' in "B" table')
            if key in result:
                raise RbqlRuntimeError('Join column must be unique in right-hand-side "B" table')
            result[key] = bfields
    return (result, fields_max_len)


def none_joiner(path):
    return None


class InnerJoiner:
    def __init__(self, join_table_path):
        self.join_data, self.fields_max_len = read_join_table(join_table_path)
    def get(self, lhs_key):
        return self.join_data.get(lhs_key, None)


class LeftJoiner:
    def __init__(self, join_table_path):
        self.join_data, self.fields_max_len = read_join_table(join_table_path)
    def get(self, lhs_key):
        return self.join_data.get(lhs_key, [None] * self.fields_max_len)


class StrictLeftJoiner:
    def __init__(self, join_table_path):
        self.join_data, self.fields_max_len = read_join_table(join_table_path)
    def get(self, lhs_key):
        result = self.join_data.get(lhs_key, None)
        if result is None:
            raise RbqlRuntimeError('In "strict left join" mode all A table keys must be present in table B. Key "' + lhs_key + '" was not found')
        return result


def main():
    rb_transform(sys.stdin, sys.stdout)


def rb_transform(source, destination):
    unsorted_entries = list()
    writer = {writer_type}(destination)
    joiner = {joiner_type}('{rhs_table_path}')
    for NR, line in enumerate(rows(source), 1):
        lnum = NR #TODO remove, backcompatibility
        line = line.rstrip('\r\n')
        star_line = line
        fields = rbql_list(line.split(DLM))
        NF = len(fields)
        flen = NF #TODO remove, backcompatibility
        bfields = None
        try:
            if joiner is not None:
                bfields = joiner.get({lhs_join_var})
                if bfields is None:
                    continue
                star_line = DLM.join([line] + [str6(f) for f in bfields])
            if not ({where_expression}):
                continue
            out_fields = [{select_expression}]
            if {sort_flag}:
                sort_key_value = ({sort_key_expression})
                unsorted_entries.append((sort_key_value, DLM.join([str6(f) for f in out_fields])))
            else:
                if {top_count} != -1 and writer.NW >= {top_count}:
                    break
                writer.write(DLM.join([str6(f) for f in out_fields]))
        except BadFieldError as e:
            bad_idx = e.bad_idx
            raise RbqlRuntimeError('No "a' + str(bad_idx + 1) + '" column at line: ' + str(NR))
        except Exception as e:
            raise RbqlRuntimeError('Error at line: ' + str(NR) + ', Details: ' + str(e))
    if len(unsorted_entries):
        unsorted_entries = sorted(unsorted_entries, reverse = {reverse_flag})
        for e in unsorted_entries:
            if {top_count} != -1 and writer.NW >= {top_count}:
                break
            writer.write(e[1])


if __name__ == '__main__':
    main()

'''





def vim_sanitize(obj):
    return str(obj).replace("'", '"')

def set_vim_variable(vim, var_name, value):
    str_value = str(value).replace("'", '"')
    vim.command("let {} = '{}'".format(var_name, str_value))

def normalize_delim(delim):
    if delim == '\t':
        return r'\t'
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
        if cline.find("'''") != -1 or cline.find('"""') != -1: #TODO improve parsing to allow multiline strings/comments
            raise RBParsingError('In line {}. Multiline python comments and doc strings are not allowed in rbql'.format(il + 1))
        rbql_lines[il] = strip_comments(cline)

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
    py_meta_params['dlm'] = normalize_delim(delim)
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
    select_expression= join_tokens(select_tokens)
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


js_script_body = r'''
fs = require('fs')
readline = require('readline');

var csv_encoding = '{csv_encoding}';
var DLM = '{dlm}';
var src_table_path = '{src_table_path}';
var dst_table_path = '{dst_table_path}';
var join_table_path = {rhs_table_path};
var top_count = {top_count};

var lineReader = readline.createInterface({{ input: fs.createReadStream(src_table_path, {{encoding: csv_encoding}}) }});
dst_stream = fs.createWriteStream(dst_table_path, {{defaultEncoding: csv_encoding}});

var NR = 0;

function exit_with_error_msg(error_msg) {{
    error_msg = error_msg.replace(/\n/g, '\t');
    console.log('error\t' + error_msg);
    process.exit(1);
}}

function SimpleWriter(dst) {{
    this.dst = dst;
    this.NW = 0;
    this.write = function(record) {{
        this.dst.write(record);
        this.dst.write('\n');
        this.NW += 1;
    }}
}}

function UniqWriter(dst) {{
    this.dst = dst;
    this.seen = new Set();
    this.write = function(record) {{
        if (!this.seen.has(record)) {{
            this.seen.add(record);
            this.dst.write(record);
            this.dst.write('\n');
        }}
    }}
}}


function read_join_table(table_path) {{
    var fields_max_len = 0;
    //FIXME handle path not exists, maybe with try/except
    content = fs.readFileSync(table_path, {{encoding: csv_encoding}});
    lines = content.split('\n');
    result = new Map();
    for (var i = 0; i < content.length; i++) {{
        line = lines[i];
        //FIXME strip last '\r'
        fields = line.split(DLM);
        fields_max_len = Math.max(fields_max_len, fields.length);
        key = fields[{rhs_join_var}];
        if (result.has(key)) {{
            exit_with_error_msg('Join column must be unique in right-hand-side "B" table');
        }}
        result.set(key, fields);
    }}
    return [result, fields_max_len];
}}

function null_join(join_map, max_join_fields, lhs_key) {{
    return null;
}}

function inner_join(join_map, max_join_fields, lhs_key) {{
    return join_map.get(lhs_key);
}}


function left_join(join_map, max_join_fields, lhs_key) {{
    var result = join_map.get(lhs_key);
    if (result == null) {{
        result = Array(max_join_fields).fill(null);
    }}
    return result;
}}


function strict_left_join(join_map, max_join_fields, lhs_key) {{
    var result = join_map.get(lhs_key);
    if (result == null) {{
        exit_with_error_msg('In "strict left join" mode all A table keys must be present in table B. Key "' + lhs_key + '" was not found');
    }}
    return result;
}}


function stable_compare(a, b) {{
    for (var i = 0; i < a.length; i++) {{
        if (a[i] !== b[i])
            return a[i] < b[i] ? -1 : 1;
    }}
}}


var join_map = null;
var max_join_fields = null;
if (join_table_path !== null) {{
    join_params = read_join_table(join_table_path);
    join_map = join_params[0];
    max_join_fields = join_params[1];
}}


var writer = new {writer_type}(dst_stream);
var unsorted_entries = [];

lineReader.on('line', function (line) {{
    NR += 1;
    //FIXME strip last '\r'
    var fields = line.split(DLM);
    var NF = fields.length;
    bfields = null;
    star_line = line;
    if (join_map != null) {{
        bfields = {join_function}(join_map, max_join_fields, {lhs_join_var});
        if (bfields == null)
            return;
        star_line = line + DLM + bfields.join(DLM);
    }}
    if (!({where_expression}))
        return;
    out_fields = [{select_expression}]
    if ({sort_flag}) {{
        sort_entry = [{sort_key_expression}, NR, out_fields.join(DLM)];
        unsorted_entries.push(sort_entry);
    }} else {{
        if (top_count != -1 && writer.NW >= top_count)
            lineReader.close();
        writer.write(out_fields.join(DLM));
    }}

}});


lineReader.on('close', function () {{
    if (unsorted_entries.length) {{
        unsorted_entries.sort(stable_compare);
        if ({reverse_flag})
            unsorted_entries.reverse();
        for (var i = 0; i < unsorted_entries.length; i++) {{
            if (top_count != -1 && writer.NW >= top_count)
                break;
            writer.write(unsorted_entries[i][unsorted_entries[i].length - 1]);
        }}
    }}
    console.log('ok\tok');
}});

'''


def strip_js_comments(cline):
    cline = cline.rstrip()
    cline = cline.replace('\t', ' ')
    #FIXME strip comments!
    return cline


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
    #FIXME require modules feature
    js_meta_params['dlm'] = normalize_delim(delim)
    js_meta_params['csv_encoding'] = 'binary' if csv_encoding == 'latin-1' else csv_encoding
    js_meta_params['rhs_join_var'] = rhs_join_var
    js_meta_params['writer_type'] = writer_name
    js_meta_params['join_function'] = join_function
    js_meta_params['src_table_path'] = src_table_path
    js_meta_params['dst_table_path'] = dst_table_path
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
    select_expression= join_tokens(select_tokens)
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


def vim_execute(src_table_path, rb_script_path, py_script_path, dst_table_path, delim, csv_encoding=default_csv_encoding):
    if os.path.exists(py_script_path):
        os.remove(py_script_path)
    import vim
    try:
        src_lines = codecs.open(rb_script_path, encoding='utf-8').readlines()
        parse_to_py(src_lines, py_script_path, delim, csv_encoding)
    except RBParsingError as e:
        set_vim_variable(vim, 'query_status', 'Parsing Error')
        set_vim_variable(vim, 'report', e)
        return

    module_name = os.path.basename(py_script_path)
    assert module_name.endswith('.py')
    module_name = module_name[:-3]
    module_dir = os.path.dirname(py_script_path)
    sys.path.insert(0, module_dir)
    try:
        rbconvert = dynamic_import(module_name)

        src = codecs.open(src_table_path, encoding=csv_encoding)
        with codecs.open(dst_table_path, 'w', encoding=csv_encoding) as dst:
            rbconvert.rb_transform(src, dst)
        src.close()
    except Exception as e:
        error_msg = 'Error: Unable to use generated python module.\n'
        error_msg += 'Original python exception:\n{}\n'.format(str(e))
        set_vim_variable(vim, 'query_status', 'Execution Error')
        set_vim_variable(vim, 'report', error_msg)
        tmp_dir = tempfile.gettempdir()
        import traceback
        with open(os.path.join(tmp_dir, 'last_exception'), 'w') as exc_dst:
            traceback.print_exc(file=exc_dst)
        return
    set_vim_variable(vim, 'query_status', 'OK')


def print_error_and_exit(error_msg):
    eprint(error_msg)
    sys.exit(1)

def run_with_python(args):
    delim = args.delim
    query = args.query
    query_path = args.query_file
    convert_only = args.convert_only
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

    try:
        parse_to_py(rbql_lines, tmp_path, delim, csv_encoding, import_modules)
    except RBParsingError as e:
        print_error_and_exit('RBQL Parsing Error: \t{}'.format(e))
    if not os.path.isfile(tmp_path) or not os.access(tmp_path, os.R_OK):
        print_error_and_exit('Error: Unable to find generated python module at {}.'.format(tmp_path))
    sys.path.insert(0, tmp_dir)
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


def system_has_node_js():
    import subprocess
    error_code = 0
    out_data = ''
    try:
        cmd = ['node', '--version']
        pobj = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        pobj.wait()
        error_code = pobj.returncode
        out_data = pobj.stdout.read()
    except OSError as e:
        if e.errno == 2:
            return False
        raise
    return error_code == 0 and len(out_data)


def run_with_js(args):
    import subprocess
    if not system_has_node_js():
        print_error_and_exit('Error: node is not found, test command: "node --version"')
    delim = args.delim
    query = args.query
    query_path = args.query_file
    convert_only = args.convert_only
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
    pobj = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    pobj.wait()
    out_data = pobj.stdout.read().decode('ascii')
    fields = out_data.split('\t', 1)
    if len(fields) < 2:
        print_error_and_exit('Unknown Error\nGenerated script location: {}'.format(tmp_path))
    if fields[0] != 'ok':
        print_error_and_exit('Error: {}\nGenerated script location: {}'.format(fields[1], tmp_path))
    #print(tmp_path) #FOR_DEBUG


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--delim', help='Delimiter', default=r'\t')
    parser.add_argument('--query', help='Query string in rbql')
    parser.add_argument('--query_file', metavar='FILE', help='Read rbql query from FILE')
    parser.add_argument('--input_table_path', metavar='FILE', help='Read csv table from FILE instead of stdin')
    parser.add_argument('--output_table_path', metavar='FILE', help='Write output table to FILE instead of stdout')
    parser.add_argument('--meta_language', metavar='LANG', help='script language to use in query', default='python', choices=['python', 'js'])
    parser.add_argument('--convert_only', action='store_true', help='Only generate script do not run query on csv table')
    parser.add_argument('--csv_encoding', help='Manually set csv table encoding', default=default_csv_encoding, choices=['latin-1', 'utf-8'])
    parser.add_argument('-I', dest='libs', action='append', help='Import module to use in the result conversion script')
    args = parser.parse_args()
    if args.meta_language == 'python':
        run_with_python(args)
    else:
        run_with_js(args)



if __name__ == '__main__':
    main()
