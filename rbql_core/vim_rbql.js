const os = require('os');
const path = require('path');
const fs = require('fs');

const rbql = require('./rbql.js');

var tmp_worker_module_path = null;


function get_error_message(error) {
    if (error && error.message)
        return error.message;
    return String(error);
}


function cleanup_tmp() {
    if (fs.existsSync(tmp_worker_module_path)) {
        fs.unlinkSync(tmp_worker_module_path);
    }
}


function finish_query_with_error(error_type, error_msg) {
    console.log(error_type);
    console.log(error_msg);
    process.exit(0);
}


function handle_worker_success(warnings, output_path) {
    cleanup_tmp();
    console.log('OK');
    console.log(output_path);
    if (warnings !== null) {
        let hr_warnings = rbql.make_warnings_human_readable(warnings);
        for (let i = 0; i < hr_warnings.length; i++) {
            console.log(hr_warnings[i]);
        }
    }
}


function main() {
    let cmd_args = process.argv;
    cmd_args = cmd_args.slice(2);
    let [input_path, query_file, delim, policy, output_delim, output_policy]  = cmd_args;
    let csv_encoding = rbql.default_csv_encoding;
    let init_source_file = null;
    let rbql_lines = fs.readFileSync(query_file, 'utf-8').split('\n');
    var tmp_dir = os.tmpdir();
    let output_path = path.join(tmp_dir, path.basename(input_path) + '.txt');
    var script_filename = 'rbconvert_' + String(Math.random()).replace('.', '_') + '.js';
    tmp_worker_module_path = path.join(tmp_dir, script_filename);
    try {
        rbql.parse_to_js(input_path, output_path, rbql_lines, tmp_worker_module_path, delim, policy, output_delim, output_policy, csv_encoding, init_source_file);
    } catch (e) {
        finish_query_with_error('Parsing Error', get_error_message(e));
        return;
    }
    var worker_module = require(tmp_worker_module_path);
    worker_module.run_on_node((warnings) => { handle_worker_success(warnings, output_path); }, error_msg => { finish_query_with_error('Execution Error', error_msg); });
}


main();
