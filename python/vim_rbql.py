import os
import sys
import codecs
import traceback
import subprocess
import tempfile
import time

import vim

import rbql


def set_vim_variable(var_name, value):
    escaped_value = value.replace("'", "''")
    vim.command("let {} = '{}'".format(var_name, escaped_value))


def report_error_to_vim(query_status, details):
    set_vim_variable('psv_query_status', query_status)
    set_vim_variable('psv_error_report', details)


def get_random_suffix():
    return str(time.time()).split('.')[0]


def execute_python(src_table_path, rb_script_path, delim, csv_encoding, dst_table_path):
    tmp_dir = tempfile.gettempdir()
    module_name = 'vim_rb_convert_{}'.format(get_random_suffix())
    meta_script_name = '{}.py'.format(module_name)
    meta_script_path = os.path.join(tmp_dir, meta_script_name)
    try:
        rbql_lines = codecs.open(rb_script_path, encoding='utf-8').readlines()
        rbql.parse_to_py(rbql_lines, meta_script_path, delim, csv_encoding)
    except rbql.RBParsingError as e:
        rbql.remove_if_possible(meta_script_path)
        report_error_to_vim('Parsing Error', str(e))
        return

    sys.path.insert(0, tmp_dir)
    try:
        rbconvert = rbql.dynamic_import(module_name)
        warnings = None
        with codecs.open(src_table_path, encoding=csv_encoding) as src, codecs.open(dst_table_path, 'w', encoding=csv_encoding) as dst:
            warnings = rbconvert.rb_transform(src, dst)
        if warnings is not None:
            hr_warnings = rbql.make_warnings_human_readable(warnings)
            warning_report = '\n'.join(hr_warnings)
            set_vim_variable('psv_warning_report', warning_report)
        rbql.remove_if_possible(meta_script_path)
        set_vim_variable('psv_query_status', 'OK')
    except Exception as e:
        error_msg = 'Error: Unable to use generated python module.\n'
        error_msg += 'Original python exception:\n{}\n'.format(str(e))
        report_error_to_vim('Execution Error', error_msg)
        with open(os.path.join(tmp_dir, 'last_rbql_exception'), 'w') as exc_dst:
            traceback.print_exc(file=exc_dst)


def execute_js(src_table_path, rb_script_path, delim, csv_encoding, dst_table_path):
    tmp_dir = tempfile.gettempdir()
    meta_script_name = 'vim_rb_convert_{}.js'.format(get_random_suffix())
    meta_script_path = os.path.join(tmp_dir, meta_script_name)
    if not rbql.system_has_node_js():
        report_error_to_vim('Execution Error', 'Node.js is not found, test command: "node --version"')
        return
    try:
        rbql_lines = codecs.open(rb_script_path, encoding='utf-8').readlines()
        rbql.parse_to_js(src_table_path, dst_table_path, rbql_lines, meta_script_path, delim, csv_encoding)
    except rbql.RBParsingError as e:
        report_error_to_vim('Parsing Error', str(e))
        return
    cmd = ['node', meta_script_path]
    pobj = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    out_data, err_data = pobj.communicate()
    error_code = pobj.returncode

    operation_report = rbql.parse_json_report(error_code, err_data)
    operation_error = operation_report.get('error')
    if operation_error is not None:
        report_error_to_vim('Execution Error', operation_error)
        return
    warnings = operation_report.get('warnings')
    if warnings is not None:
        hr_warnings = rbql.make_warnings_human_readable(warnings)
        warning_report = '\n'.join(hr_warnings)
        set_vim_variable('psv_warning_report', warning_report)
    rbql.remove_if_possible(meta_script_path)
    set_vim_variable('psv_query_status', 'OK')


def run_execute(meta_language, src_table_path, rb_script_path, delim, csv_encoding=rbql.default_csv_encoding):
    try:
        tmp_dir = tempfile.gettempdir()
        table_name = os.path.basename(src_table_path)
        dst_table_name = '{}.rs'.format(table_name)
        dst_table_path = os.path.join(tmp_dir, dst_table_name)
        set_vim_variable('psv_dst_table_path', dst_table_path)
        assert meta_language in ['python', 'js']
        if meta_language == 'python':
            execute_python(src_table_path, rb_script_path, delim, csv_encoding, dst_table_path)
        else:
            execute_js(src_table_path, rb_script_path, delim, csv_encoding, dst_table_path)
    except Exception as e:
        report_error_to_vim('Execution Error', str(e))

