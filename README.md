## Overview
Rainbow CSV has 2 main features:
* Highlights csv columns in different rainbow colors. 
* Allows to run _SELECT_ and _UPDATE_ queries in RBQL: SQL-like transprogramming query language.

There are 2 ways to enable csv columns highlighting:
1. CSV autodetection based on file content. File extension doesn't have to be .csv or .tsv
2. Manual CSV delimiter selection with _:RainbowDelim_ command (So you can use it even for non-csv files, e.g. to highlight function arguments in different colors)

To run an RBQL query either press _F5_ or enter the query in vim command line e.g. _:Select a1, a2_

### Demonstration of rainbow_csv highlighting and RBQL queries 
1-st query with Python expressions and 2-nd query with JavaScript:


![demo_screencast](https://raw.githubusercontent.com/mechatroner/rainbow_csv/master/demo/rbql_demo_2.gif)


The demo table is _demo/movies.tsv_. There are also some other test datasets in _python/test\_datasets_.


# RBQL (RainBow Query Language) Description
RBQL is a technology which provides SQL-like language that supports _SELECT_ and _UPDATE_ queries with Python or JavaScript expressions.

### Main Features
* Use Python or Java Script expressions inside _SELECT_, _UPDATE_, _WHERE_ and _ORDER BY_ statements
* Output entries appear in the same order as in input unless _ORDER BY_ is provided.
* Input csv/tsv table may contain varying number of entries (but select query must be written in a way that prevents output of missing values)
* Unicode support

### Supported SQL Keywords (Keywords are case insensitive)

* SELECT \[ TOP _N_ \] \[ DISTINCT [ COUNT ] \]
* UPDATE \[ SET \]
* WHERE
* ORDER BY ... [ DESC | ASC ]
* [ [ STRICT ] LEFT | INNER ] JOIN

#### Keywords rules
All keywords have the same meaning as in SQL queries. You can check them online e.g. [here](https://www.w3schools.com/sql/default.asp)
But there are also two new keywords: _DISTINCT COUNT_ and _STRICT LEFT JOIN_:
* _DISTINCT COUNT_ is like _DISTINCT_, but adds a new column to the "distinct" result set: number of occurences of the entry, similar to _uniq -c_ unix command.
* _STRICT LEFT JOIN_ is like _LEFT JOIN_, but generates an error if any key in left table "A" doesn't have exactly one matching key in the right table "B".

Some other rules:
* _UPDATE SET_ is synonym to _UPDATE_, because in RBQL there is no need to specify the source table.
* _UPDATE_ has the same semantic as in SQL, but it is actually a special type of _SELECT_ query.
* _JOIN_ statements must have the following form: **<join\_keyword> /path/to/table.tsv on ai == bj**

### Special variables

| Variable Name          | Variable Type | Variable Description                 |
|------------------------|---------------|--------------------------------------|
| *                      |N/A            | Current record                       |
| a1, a2, ... , a**N**   |string         | Value of i-th column                 |
| b1, b2, ... , b**N**   |string         | Value of i-th column in join table B |
| NR                     |integer        | Line number (1-based)                |
| NF                     |integer        | Number of fields in line             |

### Examples of RBQL queries

#### With Python expressions

* `select top 100 a1, int(a2) * 10, len(a4) where a1 == "Buy" order by int(a2)`
* `select * order by random.random()` - random sort, this is an equivalent of bash command _sort -R_

#### With JavaScript expressions

* `select top 100 a1, a2 * 10, a4.length where a1 == "Buy" order by parseInt(a2)`
* `select * order by Math.random()` - random sort, this is an equivalent of bash command _sort -R_

# Plugin description

### Mappings

|Key                       | Action                                             |
|--------------------------|----------------------------------------------------|
|**\<Leader\>d**  (**\d**) | Print info about current column (under the cursor) |
|**F5**                    | Start query editing for the current csv file       |
|**F5**                    | Execute currently edited query                     |


### Commands

#### :Select ...

Allows to enter RBQL select query in vim command line.
The query must start with _:Select_ command e.g. _:Select a1, a2 order by a1_

#### :Update ...

Allows to enter RBQL update query in vim command line.
The query must start with _:Update_ command e.g. _:Update a1 = a1 + " " + a2_

#### :RainbowDelim

Mark current file as csv and highlight columns in rainbow colors. Character
under the cursor will be used as a delimiter. The delimiter will be saved in a
config file for future vim sessions.

You can also use this command for non-csv files, e.g. to highlight function arguments
in source code in different colors. To return back to original syntax highlighting run _:NoRainbowDelim_

#### :NoRainbowDelim

This command will disable rainbow columns highlighting for the current file.
Useful when autodection mechanism has failed and marked non-csv file as csv.

#### :RainbowName \<name\>

Assign any name to the table in the current buffer. You can use this name in join operation instead of the table path.
e.g. you can now use:
```JOIN customers ON a1 == b1``` 

intead of:
```JOIN /path/to/my/customers/table ON a1 == b1```

### Configuration

#### g:rbql_meta_language
Default: 'python'

Scripting language to use in RBQL expression. Either 'js' or 'python'
To use JavaScript add _let g:rbql_meta_language = 'js'_ to .vimrc

#### g:rcsv_delimiters
Default: [	,]

By default plugin checks only TAB and comma characters during autodetection stage.
You can override this variable to autodetect tables with other separators. e.g. _let g:rcsv\_delimiters = [	;:,]_

#### g:disable_rainbow_csv_autodetect
csv autodetection mechanism can be disabled by setting this variable value to 1.
Manual delimiter selection would still be possible.

#### g:rcsv_max_columns
Default: 30

Autodetection will fail if buffer has more than _g:rcsv\_max\_columns_ columns.
You can increase or decrease this limit.


### Optional "Header" file feature

Rainbow csv allows you to create a special "header" file for your table files. It should have the same name as the table file but with ".header" suffix (e.g. for "input.tsv" the header file is "input.tsv.header"). The only purpose of header file is to provide csv column names for **\d** key.

### Installation

Install with your favorite plugin manager.

If you want to use RBQL with JavaScript expressions, make sure you have Node.js installed


# Other

### How does it work?
Python module rbql.py parses RBQL query, creates a new python worker module, then imports and executes it.

### Some more examples of RBQL queries:

#### With Python expressions

* `select a1, a2 where a2 in ["car", "plane", "boat"]` - use Python's "in" to emulate SQL's "in"
* `update set a3 = 'United States' where a3.find('of America') != -1`
* `select * where NR <= 10` - this is an equivalent of bash command "head -n 10", NR is 1-based')
* `select a1, a4` - this is an equivalent of bash command "cut -f 1,4"
* `select * order by int(a2) desc` - this is an equivalent of bash command "sort -k2,2 -r -n"
* `select NR, *` - enumerate lines, NR is 1-based
* `select * where re.match(".*ab.*", a1) is not None` - select entries where first column has "ab" pattern
* `select a1, b1, b2 inner join ./countries.txt on a2 == b1 order by a1` - an example of join query

#### With JavaScript expressions

* `select a1, a2 where ["car", "plane", "boat"].indexOf(a2) > -1`
* `update set a3 = 'United States' where a3.indexOf('of America') != -1`
* `select * where NR <= 10` - this is an equivalent of bash command "head -n 10", NR is 1-based')
* `select a1, a4` - this is an equivalent of bash command "cut -f 1,4"
* `select * order by parseInt(a2) desc` - this is an equivalent of bash command "sort -k2,2 -r -n"
* `select * order by Math.random()` - random sort, this is an equivalent of bash command "sort -R"
* `select NR, *` - enumerate lines, NR is 1-based
* `select a1, b1, b2 inner join ./countries.txt on a2 == b1 order by a1` - an example of join query


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



