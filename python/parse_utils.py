#!/usr/bin/env python
from __future__ import unicode_literals
from __future__ import print_function
import re
import unittest


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


class RBParsingError(Exception):
    pass


def separate_string_literals(rbql_expression):
    # regex is improved expression from here: https://stackoverflow.com/a/14366904/2898283
    matches = list(re.finditer(r'''(\"\"\"|\'\'\'|\"|\')((?<!\\)(\\\\)*\\\1|.)*?\1''', rbql_expression))
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


def separate_actions(rbql_expression):
    #TODO implement SELECT_TOP_DISTINCT
    statement_groups = list()
    statement_groups.append([STRICT_LEFT_JOIN, LEFT_JOIN, INNER_JOIN, JOIN])
    statement_groups.append([SELECT_DISTINCT, SELECT_TOP, SELECT])
    statement_groups.append([ORDER_BY])
    statement_groups.append([WHERE])
    statement_groups.append([UPDATE])

    result = dict()

    ordered_statements = list()

    for st_group in statement_groups:
        for statement in st_group:
            rgxp = None
            if statement == SELECT_TOP:
                rgxp = r'(?i)(?:^|[ ])SELECT *TOP *([0-9][0-9]*)(?:$|[ ])'
            else:
                rgxp = r'(?i)(?:^|[ ]){}(?:$|[ ])'.format(statement.replace(' ', ' *'))
            matches = list(re.finditer(rgxp, rbql_expression))
            if not len(matches):
                continue
            if len(matches) > 1:
                raise RBParsingError('More than one "{}" statements found'.format(statement))
            assert len(matches) == 1
            match = matches[0]
            result[statement] = dict()
            if statement == SELECT_TOP:
                result[statement]['top'] = int(match.group(1))
            ordered_statements.append((match.start(), match.end(), statement))
            break #there must be only one statement maximum in each group

    ordered_statements = sorted(ordered_statements)
    for i in range(len(ordered_statements)):
        statement_start = ordered_statements[i][0]
        span_start = ordered_statements[i][1]
        statement = ordered_statements[i][2]
        span_end = ordered_statements[i + 1][0] if i + 1 < len(ordered_statements) else len(rbql_expression)
        assert statement_start < span_start
        assert span_start <= span_end
        span = rbql_expression[span_start:span_end]
        if statement == ORDER_BY:
            span = re.sub('(?i)[ ]ASC[ ]*$', '', span)
            new_span = re.sub('(?i)[ ]DESC[ ]*$', '', span)
            if new_span != span:
                span = new_span
                result[statement]['reverse'] = True
            else:
                result[statement]['reverse'] = False
        result[statement]['text'] = span.strip()
    return result



class TestParsing(unittest.TestCase):

    def test_literals_replacement(self):
        #TODO generate some random examples: Generate some strings randomly and then parse them
        test_cases = list()
        test_cases.append((r'Select 100 order by a1', []))
        test_cases.append((r'Select "hello" order by a1', ['"hello"']))
        test_cases.append((r"Select 'hello', 100 order by a1 desc", ["'hello'"]))
        test_cases.append((r'Select "hello", *, "world" 100 order by a1 desc', ['"hello"', '"world"']))
        test_cases.append((r'Select "hello", "world", "hello \" world", "hello \\\" world", "hello \\\\\\\" world" order by "world"', ['"hello"', '"world"', r'"hello \" world"', r'"hello \\\" world"', r'"hello \\\\\\\" world"', '"world"']))

        for tc in test_cases:
            format_expression, string_literals = separate_string_literals(tc[0])
            canonic_literals = tc[1]
            self.assertEqual(canonic_literals, string_literals)

    def test_separate_actions(self):
        query = 'select top   100 *, a2, a3 inner  join /path/to/the/file.tsv on a1 == b3 where a4 == "hello" and int(b3) == 100 order by int(a7) desc '
        canonic_res = {'INNER JOIN': {'text': '/path/to/the/file.tsv on a1 == b3'}, 'SELECT TOP': {'text': '*, a2, a3', 'top': 100}, 'WHERE': {'text': 'a4 == "hello" and int(b3) == 100'}, 'ORDER BY': {'text': 'int(a7)', 'reverse': True}}
        test_res = separate_actions(query)
        assert test_res == canonic_res
