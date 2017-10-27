## Overview
Rainbow CSV has 2 main features:
* Highlights csv columns in different rainbow colors. 
* Provides _SELECT_ and _UPDATE_ queries in RBQL: SQL-like transprogramming query language.

There are 2 ways to enable csv columns highlighting:
1. CSV autodetection based on file content. File extension doesn't have to be .csv or .tsv
2. Manual CSV delimiter selection with _:RainbowDelim_ command (So you can use rainbow_csv for non-table files, e.g. to highlight function arguments in different colors)

To run an RBQL query either press _F5_ or enter the query in vim command line e.g. _:Select a1, a2_

### Demonstration of rainbow_csv highlighting and RBQL queries 


![demo_screencast](https://i.imgur.com/Tnk9KZv.gif)


The demo table is _demo/movies.tsv_. There are also some other test datasets in _python/test\_datasets_.
In this demo python expressions were used, but JavaScript is also available.


# RBQL (RainBow Query Language) Description
RBQL is a technology which provides SQL-like language that supports _SELECT_ and _UPDATE_ queries with Python or JavaScript expressions.

### Main Features
* Use Python or Java Script expressions inside _SELECT_, _UPDATE_, _WHERE_ and _ORDER BY_ statements
* Output entries appear in the same order as in input unless _ORDER BY_ is provided.
* Input csv/tsv table may contain varying number of entries (but select query must be written in a way that prevents output of missing values)
* Result set of any query immediately becomes a first-class table on it's own.

### Supported SQL Keywords (Keywords are case insensitive)

* SELECT \[ TOP _N_ \] \[ DISTINCT [ COUNT ] \]
* UPDATE \[ SET \]
* WHERE
* ORDER BY ... [ DESC | ASC ]
* [ [ STRICT ] LEFT | INNER ] JOIN

#### Keywords rules
All keywords have the same meaning as in SQL queries. You can check them [online](https://www.w3schools.com/sql/default.asp)
But there are also two new keywords: _DISTINCT COUNT_ and _STRICT LEFT JOIN_:
* _DISTINCT COUNT_ is like _DISTINCT_, but adds a new column to the "distinct" result set: number of occurences of the entry, similar to _uniq -c_ unix command.
* _STRICT LEFT JOIN_ is like _LEFT JOIN_, but generates an error if any key in left table "A" doesn't have exactly one matching key in the right table "B".

Some other rules:
* _UPDATE SET_ is synonym to _UPDATE_, because in RBQL there is no need to specify the source table.
* _UPDATE_ has the same semantic as in SQL, but it is actually a special type of _SELECT_ query.
* _JOIN_ statements must have the following form: _<JOIN\_KEYWORD> (/path/to/table.tsv | table_name ) ON ai == bj_

### Special variables

| Variable Name          | Variable Type | Variable Description                 |
|------------------------|---------------|--------------------------------------|
| _a1_, _a2_,..., _a{N}_   |string         | Value of i-th column                 |
| _b1_, _b2_,..., _b{N}_   |string         | Value of i-th column in join table B |
| _NR_                     |integer        | Line number (1-based)                |
| _NF_                     |integer        | Number of fields in line             |

### Examples of RBQL queries

#### With Python expressions

* `select top 100 a1, int(a2) * 10, len(a4) where a1 == "Buy" order by int(a2)`
* `select * order by random.random()` - random sort, this is an equivalent of bash command _sort -R_

#### With JavaScript expressions

* `select top 100 a1, a2 * 10, a4.length where a1 == "Buy" order by parseInt(a2)`
* `select * order by Math.random()` - random sort, this is an equivalent of bash command _sort -R_

# Plugin description

### Rainbow highlighting for non-table files
You can use rainbow highlighting and RBQL even for non-csv/tsv files.
E.g. you can highlight records in log files, one-line xmls and other delimited records.
You can even highlight function arguments in your programming language using comma as a delimiter for _:RainbowDelim_ command.
And you can always turn off the rainbow highlighting using _:NoRainbowDelim_ command.

Here is an example of how to extract some fields from a bunch of uniform single-line xmls:

![demo_xml_screencast](https://i.imgur.com/HlzBWOV.gif)


### Mappings

|Key                       | Action                                             |
|--------------------------|----------------------------------------------------|
|**\<Leader\>d**  (**\d**) | Print info about current column (under the cursor) |
|**F5**                    | Start query editing for the current csv file       |
|**F5**                    | Execute currently edited query                     |


### Commands

#### :Select ...

Allows to enter RBQL select query as vim command.
e.g. _:Select a1, a2 order by a1_

#### :Update ...

Allows to enter RBQL update query as vim command.
e.g. _:Update a1 = a1 + " " + a2_

#### :RainbowDelim

Mark current file as a table and highlight it's columns in rainbow colors. Character
under the cursor will be used as a delimiter. The delimiter will be saved in a
config file for future vim sessions.

You can also use this command for non-csv files, e.g. to highlight function arguments
in source code in different colors. To return back to original syntax highlighting run _:NoRainbowDelim_

#### :RainbowDelimQuoted

Same as _:RainbowDelim_ but allows delimiters inside fields if the field is double quoted by rules of Excel / [RFC 4180](https://tools.ietf.org/html/rfc4180)

#### :RainbowMonoColumn

Mark the current file as rainbow table with a single column without delimiters. 
You will be able to run RBQL queries on it using _a1_ column variable.

#### :NoRainbowDelim

This command will disable rainbow columns highlighting for the current file.
Use it to cancel _:RainbowDelim_, _:RainbowDelimQuoted_ and _:RainbowMonoColumn_ effects or when autodection mechanism has failed and marked non-table file as a table

#### :RainbowName \<name\>

Assign any name to the current table. You can use this name in join operation instead of the table path. E.g.
```
JOIN customers ON a1 == b1
``` 
intead of:
```
JOIN /path/to/my/customers/table ON a1 == b1
```

### Configuration

#### g:rbql_output_format
Default: _tsv_
Allowed values: _tsv_, _csv_

Format of RBQL result set tables.

* tsv format doesn't allow quoted tabs inside fields. 
* csv is Excel-compatible and allows quoted commas.

Essentially format here is a pair: delimiter + quoting policy.
This setting for example can be used to convert files between tsv and csv format:
* To convert _csv_ to _tsv_: **1.** open csv file. **2.** `:let g:rbql_output_format='tsv'` **3.** `:Select *`
* To convert _tsv_ to _csv_: **1.** open tsv file. **2.** `:let g:rbql_output_format='csv'` **3.** `:Select *`


#### g:rbql_meta_language
Default: _python_

Scripting language to use in RBQL expression. Either 'js' or 'python'
To use JavaScript add _let g:rbql_meta_language = 'js'_ to .vimrc

#### g:rcsv_delimiters
Default: _["\t", ","]_

By default plugin checks only TAB and comma characters during autodetection stage.
You can override this variable to autodetect tables with other separators. e.g. _let g:rcsv\_delimiters = ["\t", ",", ";"]_

#### g:disable_rainbow_csv_autodetect
csv autodetection mechanism can be disabled by setting this variable value to 1.
Manual delimiter selection would still be possible.

#### g:rcsv_max_columns
Default: _30_

Autodetection will fail if buffer has more than _g:rcsv\_max\_columns_ columns.
You can increase or decrease this limit.


### Optional "Header" file feature

Rainbow csv allows you to create a special "header" file for any of your table files. It must have the same name as the table file but with ".header" suffix (e.g. for "table.tsv" table the header file is "table.tsv.header"). The only purpose of header file is to provide csv column names for **\d** key.
It is also possible to use `:RainbowSetHeader <file_name>` command to set a differently named file as a header for the current table.

### Installation

Install with your favorite plugin manager.

If you want to use RBQL with JavaScript expressions, make sure you have Node.js installed


# Other

### How does it work?
Python module rbql.py parses RBQL query, creates a new python worker module, then imports and executes it.

### Some more examples of RBQL queries:

#### With Python expressions

* `select top 20 len(a1) / 10, a2 where a2 in ["car", "plane", "boat"]` - use Python's "in" to emulate SQL's "in"
* `update set a3 = 'US' where a3.find('of America') != -1`
* `select * where NR <= 10` - this is an equivalent of bash command "head -n 10", NR is 1-based')
* `select a1, a4` - this is an equivalent of bash command "cut -f 1,4"
* `select * order by int(a2) desc` - this is an equivalent of bash command "sort -k2,2 -r -n"
* `select NR, *` - enumerate lines, NR is 1-based
* `select * where re.match(".*ab.*", a1) is not None` - select entries where first column has "ab" pattern
* `select a1, b1, b2 inner join ./countries.txt on a2 == b1 order by a1, a3` - an example of join query
* `select distinct count len(a1) where a2 != 'US'`

#### With JavaScript expressions

* `select top 20 a1.length / 10, a2 where ["car", "plane", "boat"].indexOf(a2) > -1`
* `update set a3 = 'US' where a3.indexOf('of America') != -1`
* `select * where NR <= 10` - this is an equivalent of bash command "head -n 10", NR is 1-based')
* `select a1, a4` - this is an equivalent of bash command "cut -f 1,4"
* `select * order by parseInt(a2) desc` - this is an equivalent of bash command "sort -k2,2 -r -n"
* `select * order by Math.random()` - random sort, this is an equivalent of bash command "sort -R"
* `select NR, *` - enumerate lines, NR is 1-based
* `select a1, b1, b2 inner join ./countries.txt on a2 == b1 order by a1, a3` - an example of join query
* `select distinct count a1.length where a2 != 'US'`


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



