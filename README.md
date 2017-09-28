## Overview
Rainbow CSV has two main features:
* Highlights csv columns in different rainbow colors. 
* Allows to run "select" queries in RBQL: SQL-like transprogramming language.

To enter a "select" query either press 'F5' or enter the query in vim command line e.g. `:Select a1, a2`

There are 2 ways to enable csv columns highlighting:
1. CSV autodetection based on file content. File extension doesn't have to be .csv or .tsv
2. Manual CSV delimiter selection with `:RainbowDelim` command (So you can use it even for non-csv files, e.g. to highlight function arguments in different colors)

### Demonstration of rainbow_csv highlighting and RBQL queries 
1-st query with Python expressions and 2-nd query with JavaScript:


![demo_screencast](https://raw.githubusercontent.com/mechatroner/rainbow_csv/master/demo/rbql_demo_2.gif)


The demo table is demo/movies.tsv. There are also some other test datasets in python/test_datasets.


## RBQL (RainBow Query Language) Description
RBQL is a technology which provides SQL-like language that supports "select" queries with Python or JavaScript expressions.

### Main Features
* Use Python or JavaScript expressions inside "select", "where" and "order by" statements
* Use "a1", "a2", ... , "aN" as column names to write select queries
* Output entries appear in the same order as in input unless "ORDER BY" is provided.
* "NR" variable holds current record's line number and "NF" holds number of fields in the record (awk has the same variables)
* Use double equality "==" instead of single "=" to check for equality
* Use one of the "join" keywords to run join query
* Input csv/tsv table may contain varying number of entries (but select query must be written in a way that prevents output of missing values)
* Unicode support

### Supported SQL Keywords (Keywords are case insensitive)

* SELECT 
* WHERE 
* ORDER BY ... [DESC|ASC]
* DISTINCT
* TOP
* [INNER] JOIN
* LEFT JOIN
* STRICT LEFT JOIN

### Special variables
* `a1`, `a2`, ... , `aN` - Column names
* `*` - Current record
* `NR` - Number of Records being processed (or line number). NR is 1-based
* `NF` - Number of Fields in the current line/record
* `b1`, `b2`, ... , `bN` - Column names in right table B in JOIN operations

### Join query rules
* Keywords `join` (`inner join`) and `left join` work exactly like their SQL equivalents with only difference that join key in right table "B" must be unique.  
* Keyword `strict left join` is like `left join`, but generates error if some keys in left table "A" don't have matching key in right table "B".
* Join statement must have the following form: `<join_keyword> /path/to/table.tsv on ai == bj`

### RBQL Query examples with Python expressions

* `select * where a1 == "Buy"` - use double equality "==" instead of single equality "="
* `select a1, a2 where a2 in ["car", "plane", "boat"]` - use Python's "in" to emulate SQL's "in"
* `select * where NR <= 10` - this is an equivalent of bash command "head -n 10", NR is 1-based')
* `select a1, a4` - this is an equivalent of bash command "cut -f 1,4"
* `select * order by int(a2) desc` - this is an equivalent of bash command "sort -k2,2 -r -n"
* `select * order by random.random()` - random sort, this is an equivalent of bash command "sort -R"
* `select NR, *` - enumerate lines, NR is 1-based
* `select * where re.match(".*ab.*", a1) is not None` - select entries where first column has "ab" pattern
* `select a1, b1, b2 inner join ./countries.txt on a2 == b1 order by a1` - an example of join query

### RBQL Query examples with JavaScript expressions

* `select * where a1 == "Buy"` - use double equality "==" instead of single equality "="
* `select a1, a2 where ["car", "plane", "boat"].indexOf(a2) > -1`
* `select * where NR <= 10` - this is an equivalent of bash command "head -n 10", NR is 1-based')
* `select a1, a4` - this is an equivalent of bash command "cut -f 1,4"
* `select * order by parseInt(a2) desc` - this is an equivalent of bash command "sort -k2,2 -r -n"
* `select * order by Math.random()` - random sort, this is an equivalent of bash command "sort -R"
* `select NR, *` - enumerate lines, NR is 1-based
* `select a1, b1, b2 inner join ./countries.txt on a2 == b1 order by a1` - an example of join query

### How does it work?
Python script rbql.py parses RBQL query, creates a new .py module, then imports and executes it.


## Mappings

|Key           | Action                                                      |
|--------------|-------------------------------------------------------------|
|`<leader>d`   | Print info about current column (under the cursor)          |
|`F5`          | Start "select" query editing for the current csv file       |
|`F5`          | Execute currently edited "select" query                     |


## Commands

#### :Select ...

Most useful command: allows to enter RBQL query in vim command line.
The query must start with `:Select` command e.g. `:Select a1, a2 order by a1`

#### :RainbowDelim

Mark current file as csv and highlight columns in rainbow colors, character
under the cursor will be used as delimiter. Selection will be recorded in the
config file for future vim sessions.

#### :NoRainbowDelim

This command will disable rainbow columns highlighting for the current file.
Usefull when autodection mechanism has failed and marked non csv file as csv
this command also has an alias `:NoRainbowDelim`


## Configuration

#### g:rbql_meta_language
*Default: 'python'*
Scripting language to use in RBQL expression. Either 'js' or 'python'
To use JavaScript add `let g:rbql_meta_language = 'js'` to .vimrc

#### g:rcsv_delimiters
*Default: [	,]*
By default plugin checks only TAB and comma characters during autodetection stage.
You can override this variable to autodetect tables with other separators. e.g. `let g:rcsv_delimiters = [	;:,]`

#### g:disable_rainbow_csv_autodetect
You can disable csv files autodetection mechanism by setting this variable value to 1.
You will still be able to use manual csv delimiter selection.

#### g:rcsv_max_columns
*Default: 30*
Autodetection will fail if buffer has more than `g:rcsv_max_columns` columns.
You can rise or lower this limit.

## Other

### cli_rbql.py script

rainbow_csv comes with cli_rbql.py script which is located in ~/.vim extension folder.  
You can use it in standalone mode to execute RBQL queries from command line. Example:
```
./cli_rbql.py --query "select a1, a2 order by a1" < input.tsv
```
To find out more about cli_rbql.py and available options, execute:
```
./cli_rbql.py -h
```


### Optional "Header" file feature

Rainbow csv allows you to create a special "header" file for your table files. It should have the same name as the table file but with ".header" suffix (e.g. for "input.tsv" the header file is "input.tsv.header"). The only purpose of header file is to provide csv column names for `:RbGetColumn` command.


### Installation

Install with your favorite plugin manager.

If you want to use RBQL with JavaScript expressions, make sure you have Node.js installed

