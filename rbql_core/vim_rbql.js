const os = require('os');
const path = require('path');
const fs = require('fs');

const rbql_csv = require('./rbql-js/rbql_csv.js');


function handle_worker_error(error_type, error_msg) {
    console.log(error_type);
    let result_file_path = '';
    console.log(result_file_path); 
    console.log(error_msg);
    process.exit(0);
}


function handle_worker_success(warnings, output_path) {
    console.log('OK');
    console.log(output_path);
    if (warnings !== null) {
        for (let i = 0; i < warnings.length; i++) {
            console.log(warnings[i]);
        }
    }
}


function main() {
    let cmd_args = process.argv;
    cmd_args = cmd_args.slice(2);
    let [input_path, query_file, delim, policy, output_delim, output_policy]  = cmd_args;
    let csv_encoding = 'latin-1';
    let init_source_file = null;
    let query = fs.readFileSync(query_file, 'utf-8');
    var tmp_dir = os.tmpdir();
    let output_path = path.join(tmp_dir, path.basename(input_path) + '.txt');

    let handle_success = function(warnings) {
        handle_worker_success(warnings, output_path);
    }
    rbql_csv.csv_run(query, input_path, delim, policy, output_path, output_delim, output_policy, csv_encoding, handle_success, handle_worker_error);
}


main();
