#!/usr/bin/env python
from __future__ import unicode_literals
from __future__ import print_function
import re
import unittest


def replace_string_literals(rbql_expression):
    # regex is improved expression from here: https://stackoverflow.com/a/14366904/2898283
    #FIXME what if string has "r" prefix ???
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
    return (format_expression, string_literals)


class TestParsing(unittest.TestCase):

    def test_literals_replacement(self):
        #TODO generate some random examples: Generate some strings randomly and then parse them
        test_cases = list()
        test_cases.append((r'Select 100 order by a1', []))
        test_cases.append((r'Select "hello" order by a1', ['"hello"']))
        test_cases.append((r"Select 'hello', 100 order by a1 desc", ["'hello'"]))
        test_cases.append((r'Select "hello", *, "world" 100 order by a1 desc', ['"hello"', '"world"']))
        test_cases.append((r'Select "hello", "world", "hello \" world", "hello \\\" world", "hello \\\\\\\" world" order by "world"', ['"hello"', '"world"', r'"hello \" world"', r'"hello \\\" world"', r'"hello \\\\\\\" world"', '"world"']))
        #test_cases.append((r"""Select 'hello', 'world', 'hello\' world', 'hello \\\' world', 'hello \\\\\\\' world' order by 'world'""",[]))
        #test_cases.append((r'''Select "  hello 'world'  ", '  hello "world"  ' order by a1''',[]))
        #test_cases.append((r'Select r"hello", r"world", "hello\" world", "hello \\\" world", "hello \\\\\\\" world \\\\\\\" world" order by "world"',[]))
        #test_cases.append((r'Select "hello", "world", "hello\" world", "hello world\\\\\\", "hello world\\" order by "world"',[]))
        #test_cases.append((r'Select "hello", "world", "hello\" world", "hello world\\\\\\", "hello world\\" order by "world"',[]))

        for tc in test_cases:
            format_expression, string_literals = replace_string_literals(tc[0])
            canonic_literals = tc[1]
            self.assertEqual(canonic_literals, string_literals)


