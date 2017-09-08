import os
import sys
import codecs
import traceback
import subprocess
import tempfile

import vim

import rbql


def vim_sanitize(obj):
    return str(obj).replace("'", '"')


def set_vim_variable(var_name, value):
    #FIXME don't use replace quotes hack, escape the quotes
    str_value = value.replace("'", '"')
    vim.command("let {} = '{}'".format(var_name, str_value))


def report_to_vim(query_status, details):
    set_vim_variable('query_status', query_status)
    set_vim_variable('report', details)


def execute_python(src_table_path, rb_script_path, meta_script_path, dst_table_path, delim, csv_encoding):
    try:
        rbql_lines = codecs.open(rb_script_path, encoding='utf-8').readlines()
        rbql.parse_to_py(rbql_lines, meta_script_path, delim, csv_encoding)
    except rbql.RBParsingError as e:
        report_to_vim('Parsing Error', str(e))
        return

    module_name = os.path.basename(meta_script_path)
    assert module_name.endswith('.py')
    module_name = module_name[:-3]
    module_dir = os.path.dirname(meta_script_path)
    sys.path.insert(0, module_dir)
    try:
        rbconvert = rbql.dynamic_import(module_name)
        warnings = None
        with codecs.open(src_table_path, encoding=csv_encoding) as src, codecs.open(dst_table_path, 'w', encoding=csv_encoding) as dst:
            warnings = rbconvert.rb_transform(src, dst)
        warning_report = ''
        if warnings is not None:
            hr_warnings = rbql.make_warnings_human_readable(warnings)
            warning_report = '\n'.join(hr_warnings)
        report_to_vim('OK', warning_report)
    except Exception as e:
        error_msg = 'Error: Unable to use generated python module.\n'
        error_msg += 'Original python exception:\n{}\n'.format(str(e))
        report_to_vim('Execution Error', error_msg)
        tmp_dir = tempfile.gettempdir()
        with open(os.path.join(tmp_dir, 'last_rbql_exception'), 'w') as exc_dst:
            traceback.print_exc(file=exc_dst)


def execute_js(src_table_path, rb_script_path, meta_script_path, dst_table_path, delim, csv_encoding):
    if not rbql.system_has_node_js():
        report_to_vim('Execution Error', 'Node.js is not found, test command: "node --version"')
        return
    try:
        rbql_lines = codecs.open(rb_script_path, encoding='utf-8').readlines()
        rbql.parse_to_js(src_table_path, dst_table_path, rbql_lines, meta_script_path, delim, csv_encoding)
    except rbql.RBParsingError as e:
        report_to_vim('Parsing Error', str(e))
        return
    cmd = ['node', meta_script_path]
    pobj = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    out_data, err_data = pobj.communicate()
    error_code = pobj.returncode

    operation_report = rbql.parse_json_report(error_code, err_data)
    operation_error = operation_report.get('error')
    if operation_error is not None:
        report_to_vim('Execution Error', operation_error)
        return
    warnings = operation_report.get('warnings')
    warning_report = ''
    if warnings is not None:
        hr_warnings = rbql.make_warnings_human_readable(warnings)
        warning_report = '\n'.join(hr_warnings)
    report_to_vim('OK', warning_report)


def execute(meta_language, src_table_path, rb_script_path, meta_script_path, dst_table_path, delim, csv_encoding=rbql.default_csv_encoding):
    try:
        if os.path.exists(meta_script_path):
            os.remove(meta_script_path)
        assert meta_language in ['python', 'js']
        if meta_language == 'python':
            execute_python(src_table_path, rb_script_path, meta_script_path, dst_table_path, delim, csv_encoding)
        else:
            execute_js(src_table_path, rb_script_path, meta_script_path, dst_table_path, delim, csv_encoding)
    except Exception as e:
        report_to_vim('Execution Error', str(e))


