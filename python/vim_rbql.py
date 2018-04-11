import os
import sys
import codecs
import traceback
import subprocess
import tempfile
import time

import rbql

vim_interface = None


class VimInterface:
    def __init__(self):
        import vim
        self.vim = vim

    def set_vim_variable(self, var_name, value):
        escaped_value = value.replace("'", "''")
        self.vim.command("let {} = '{}'".format(var_name, escaped_value))

    def report_error_to_vim(self, query_status, details):
        self.set_vim_variable('psv_query_status', query_status)
        self.set_vim_variable('psv_error_report', details)


class CLIVimMediator:
    def __init__(self):
        self.psv_variables = dict()

    def set_vim_variable(self, var_name, value):
        self.psv_variables[var_name] = value

    def report_error_to_vim(self, query_status, details):
        self.set_vim_variable('psv_query_status', query_status)
        self.set_vim_variable('psv_error_report', details)

    def save_report(self, dst):
        query_status = self.psv_variables.get('psv_query_status', 'Unknown Error')
        dst_table_path = self.psv_variables.get('psv_dst_table_path', '')
        report = self.psv_variables.get('psv_error_report', '')
        if not len(report):
            report = self.psv_variables.get('psv_warning_report', '')
        dst.write(query_status + '\n')
        dst.write(dst_table_path + '\n')
        if len(report):
            dst.write(report + '\n')


def get_random_suffix():
    return str(time.time()).split('.')[0]


def execute_python(src_table_path, rb_script_path, input_delim, input_policy, out_delim, out_policy, dst_table_path):
    csv_encoding = rbql.default_csv_encoding

    with rbql.RbqlPyEnv() as worker_env:
        try:
            tmp_path = worker_env.module_path
            rbql_lines = codecs.open(rb_script_path, encoding='utf-8').readlines()
            rbql.parse_to_py(rbql_lines, tmp_path, input_delim, input_policy, out_delim, out_policy, csv_encoding, None)
        except rbql.RBParsingError as e:
            vim_interface.report_error_to_vim('Parsing Error', str(e))
            return

        try:
            rbconvert = worker_env.import_worker()
            warnings = None
            with codecs.open(src_table_path, encoding=csv_encoding) as src, codecs.open(dst_table_path, 'w', encoding=csv_encoding) as dst:
                warnings = rbconvert.rb_transform(src, dst)
            if warnings is not None:
                hr_warnings = rbql.make_warnings_human_readable(warnings)
                warning_report = '\n'.join(hr_warnings)
                vim_interface.set_vim_variable('psv_warning_report', warning_report)
            worker_env.remove_env_dir()
            vim_interface.set_vim_variable('psv_query_status', 'OK')
        except Exception as e:
            error_msg = 'Error: Unable to use generated python module.\n'
            error_msg += 'Original python exception:\n{}\n'.format(str(e))
            vim_interface.report_error_to_vim('Execution Error', error_msg)


def execute_js(src_table_path, rb_script_path, input_delim, input_policy, out_delim, out_policy, dst_table_path):
    csv_encoding = rbql.default_csv_encoding
    tmp_dir = tempfile.gettempdir()
    meta_script_name = 'vim_rb_convert_{}.js'.format(get_random_suffix())
    meta_script_path = os.path.join(tmp_dir, meta_script_name)
    if not rbql.system_has_node_js():
        vim_interface.report_error_to_vim('Execution Error', 'Node.js is not found, test command: "node --version"')
        return
    try:
        rbql_lines = codecs.open(rb_script_path, encoding='utf-8').readlines()
        rbql.parse_to_js(src_table_path, dst_table_path, rbql_lines, meta_script_path, input_delim, input_policy, out_delim, out_policy, csv_encoding, None)
    except rbql.RBParsingError as e:
        vim_interface.report_error_to_vim('Parsing Error', str(e))
        return
    cmd = ['node', meta_script_path]
    pobj = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    out_data, err_data = pobj.communicate()
    error_code = pobj.returncode

    operation_report = rbql.parse_json_report(error_code, err_data)
    operation_error = operation_report.get('error')
    if operation_error is not None:
        vim_interface.report_error_to_vim('Execution Error', operation_error)
        return
    warnings = operation_report.get('warnings')
    if warnings is not None:
        hr_warnings = rbql.make_warnings_human_readable(warnings)
        warning_report = '\n'.join(hr_warnings)
        vim_interface.set_vim_variable('psv_warning_report', warning_report)
    rbql.remove_if_possible(meta_script_path)
    vim_interface.set_vim_variable('psv_query_status', 'OK')


def converged_execute(meta_language, src_table_path, rb_script_path, input_delim, input_policy, out_delim, out_policy):
    try:
        input_delim = rbql.normalize_delim(input_delim)
        out_delim = rbql.normalize_delim(out_delim)
        tmp_dir = tempfile.gettempdir()
        table_name = os.path.basename(src_table_path)
        dst_table_name = '{}.txt'.format(table_name)
        dst_table_path = os.path.join(tmp_dir, dst_table_name)
        vim_interface.set_vim_variable('psv_dst_table_path', dst_table_path)
        assert meta_language in ['python', 'js']
        if meta_language == 'python':
            execute_python(src_table_path, rb_script_path, input_delim, input_policy, out_delim, out_policy, dst_table_path)
        else:
            execute_js(src_table_path, rb_script_path, input_delim, input_policy, out_delim, out_policy, dst_table_path)
    except Exception as e:
        vim_interface.report_error_to_vim('Execution Error', str(e))


def run_execute(meta_language, src_table_path, rb_script_path, input_delim, input_policy, out_delim, out_policy):
    global vim_interface
    vim_interface = VimInterface()
    converged_execute(meta_language, src_table_path, rb_script_path, input_delim, input_policy, out_delim, out_policy)


def run_execute_cli(meta_language, src_table_path, rb_script_path, input_delim, input_policy, out_delim, out_policy):
    global vim_interface
    vim_interface = CLIVimMediator()
    converged_execute(meta_language, src_table_path, rb_script_path, input_delim, input_policy, out_delim, out_policy)
    vim_interface.save_report(sys.stdout)


def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('meta_language', metavar='LANG', help='script language to use in query', choices=['python', 'js'])
    parser.add_argument('input_table_path', metavar='FILE', help='Read csv table from FILE')
    parser.add_argument('query_file', metavar='FILE', help='Read rbql query from FILE')
    parser.add_argument('input_delim', metavar='DELIM', help='Input delimiter')
    parser.add_argument('input_policy', metavar='POLICY', help='Input policy', choices=['simple', 'quoted', 'monocolumn'])
    parser.add_argument('out_delim', metavar='DELIM', help='Output delimiter')
    parser.add_argument('out_policy', metavar='POLICY', help='Output policy', choices=['simple', 'quoted', 'monocolumn'])
    args = parser.parse_args()
    run_execute_cli(args.meta_language, args.input_table_path, args.query_file, args.input_delim, args.input_policy, args.out_delim, args.out_policy)


if __name__ == '__main__':
    main()
