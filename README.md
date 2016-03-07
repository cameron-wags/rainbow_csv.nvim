**rainbow_csv**: highlight columns in csv/tsv/*sv files in different colors

##Overview

Rainbow CSV provides a way to highlight logical columns in different rainbow
colors. This helps to understand data patterns in csv, tsv, etc files more
quickly. Every 10-th column has a default font color.

There are 2 ways to enable csv columns highlighting:
    1. CSV autodetection based on buffer content
    2. Manual CSV delimiter selection

When a new buffer is opened, Rainbow CSV analyzes it's content and tries to
autodect whether it is a csv file or not; and if it is, what character this
csv is delimited by. Autodetection is triggered only if no other syntax rules
have been set for the buffer. Buffer's file extension is irrelevant for
autodetection, autodetection should work even if buffer content was loaded by
vim from stdin.

If autodetection mechanism was disabled or failed for some reason, you can
specify csv delimiter manualy: execute command `:RainbowDelim` and character
under the cursor will be used as csv delimiter for columns highlighting.

Another feature of Rainbow CSV is to provide information about current csv
column. Column numbers are available for every csv data file. If csv data file
columns have associated names, user can put them in a special *Header* file.
To get info about a column, press `<leader>d` combination.

###Header concept

Header file is a single-line csv file with the same number of fields as the data
file, which are separated by the same delimiter. Values in header fields are
names of data file columns.
If the number of fields in data and header files mismatch, a warning will be printed
when user requests column information.

The only function of header file is to provide info about csv data files
column names. If you don't need this feature, rainbow_csv plugin works perfectly
without it.

####Example of tsv data file and header file pair
csv data file content:

```
Jack,20  
Maria,18 
John,40  
Dmitry,27
Maria,30 
John,17  
```

csv header file content:
```
Name,Age
```

##Mappings

|Key           |  mode  |   Action                                             |
|--------------|--------|------------------------------------------------------|
|`<leader>d`   |    n   |   Print info about current column (under the cursor) |

To disable all mappings set global variable `g:rcsv_map_keys` to 0

##Commands

####:RainbowDelim

Mark current file as csv and highlight columns in rainbow colors, character
under the cursor will be used as delimiter. Selection will be recorded in the
config file for future vim sessions.

####:NoRainbowDelim

This command will disable rainbow columns highlighting for the current file.
Usefull when autodection mechanism has failed and marked non csv file as csv

####:RainbowNoDelim

alias for `:NoRainbowDelim`

####:RainbowGetColumn

Will print info about current csv column (column under the cursor).
Printed info contains:
1. column number, 1 - based
2. column name, only available if a header file is set

By default this command is mapped to `<leader>d` combination

####:RainbowSetHeader

Requires an argument - path to the header file.
Sets header file for the current tsv data file. It will be recorded in config
file for future vim sessions.

*Usage:*
```
:RainbowSetHeader path/to/header
```

##Configuration

####g:rcsv_map_keys
*Default: 1*

Set to 0 if you want to diable plugin key mappings

####g:rcsv_delimiters
*Default: [	,]*

By default plugin checks only TAB and comma characters for csv autodetection.
You can specify your own set of autodetectable delimiters by defining a custom
`g:rcsv_delimiters` list in your .vimrc

*Example:*
(plugin will check TAB, semicolon, colon and whitespace on autodetect)
```
let g:rcsv_delimiters = [	;: ]
```

####g:disable_rainbow_csv_autodetect
*Default: 0*

If plugin csv autodetection feature produces to much false positives, you can
disable this mechanism by defining `g:disable_rainbow_csv_autodetect`
option in your .vimrc

*Example:*
```
let g:disable_rainbow_csv_autodetect = 1
```
You will still be able to use manual csv delimiter selection.

####g:rcsv_max_columns
*Default: 30*

Autodetection will fail if buffer has more than `g:rcsv_max_columns` columns.
You can rise or lower this limit.

*Example:*
```
let g:rcsv_max_columns = 40
```

NOTE: setting rcsv_max_columns to a big value may slow down csv files display

####g:rcsv_colorpairs
*Default: see autoload/rainbow_csv.vim code*

If you don't like the default column colors, you can specify your own.
*Example:*
(1,6,11... columns are darkred, and every 5-th column have default font color)

```
let g:rcsv_colorpairs = [
    \ ['darkred',     'darkred'],
    \ ['darkblue',    'darkblue'],
    \ ['darkgreen',   'darkgreen'],
    \ ['darkmagenta', 'darkmagenta'],
    \ ['NONE',        'NONE'],
    \ ]
```
