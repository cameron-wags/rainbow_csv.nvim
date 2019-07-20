#!/usr/bin/env node
const path = require('path');
const fs = require('fs');

const rbql_home_dir = __dirname;


function replace_all(src, search, replacement) {
    return src.split(search).join(replacement);
}


function escape_string_literal_backtick(src) {
    src = replace_all(src, '\\', '\\\\');
    src = replace_all(src, "`", "\\`");
    src = replace_all(src, "${", "\\${");
    src = "`" + src + "`";
    return src;
}


function read_engine_text() {
    try {
        return fs.readFileSync(path.join(rbql_home_dir, 'rbql.js'), 'utf-8');
    } catch (e) {
        return '';
    }
}


function build_engine_text(for_web) {
    let proto_engine_dir = path.join(rbql_home_dir, 'proto_engine');
    let builder_text = fs.readFileSync(path.join(proto_engine_dir, 'builder.js'), 'utf-8');
    let template_text = fs.readFileSync(path.join(proto_engine_dir, 'template.js'), 'utf-8');
    let marker = 'codegeneration_pseudo_function_include_combine("template.js")';
    let do_not_edit_warning = '// DO NOT EDIT!\n// This file was autogenerated from builder.js and template.js using build_engine.js script\n\n';
    let engine_body = builder_text.replace(marker, escape_string_literal_backtick(template_text)); 
    if (for_web) {
        engine_body = "let module = {'exports': {}};\n" + 'rbql = module.exports;\n' + engine_body;
        engine_body = '( function() {\n' + engine_body + '})()';
        engine_body = 'let rbql = null;\n' + engine_body;
    }
    let engine_text = do_not_edit_warning + engine_body + '\n\n' + do_not_edit_warning;
    return engine_text;
}


function build_engine() {
    let engine_text = build_engine_text(false);
    fs.writeFileSync(path.join(rbql_home_dir, 'rbql.js'), engine_text, 'utf-8');
    let web_engine_text = build_engine_text(true);
    fs.writeFileSync(path.join(rbql_home_dir, 'web_rbql.js'), web_engine_text, 'utf-8');
}


module.exports.build_engine = build_engine;
module.exports.read_engine_text = read_engine_text;
module.exports.build_engine_text = build_engine_text;

if (require.main === module) {
    build_engine();
}

