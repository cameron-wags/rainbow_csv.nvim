# Survey of some public csv datasets

## Game of Thrones Battles
Available on kaggle: https://www.kaggle.com/mylesoneill/game-of-thrones 

### Problems
#### Has '\r' line separators
vim incorrectly interprets the file as a single but very long line

#### both consequtive double quotes and comma inside one of the quoted fields
looks like this:
  `...,"It isn't mentioned how many Stark men are left in Winterfell, other than ""very few""."`

#### Has header


## Game of Thrones characters deaths
Available on kaggle: https://www.kaggle.com/mylesoneill/game-of-thrones 

### Problems
#### Has '\r' line separators
vim incorrectly interprets the file as a single but very long line

#### Has header


## UCI:adult
Available at UCI repository: http://archive.ics.uci.edu/ml/machine-learning-databases/adult/

### Problems
#### last line is empty

#### whitespaces after commas:
`22, Private, 201490, HS-grad, 9, Never-married, Adm-clerical, Own-child, White, Male, 0, 0, 20, United-States, <=50K`

## UCI:iris
Available at UCI repository

### Problems
#### last line is empty

## UCI:wine
Available at UCI repository

### Problems
No problems

## UCI:car evaluation
Available at UCI repository

### Problems
No problems

## UCI:forest fires
Available at UCI repository

### Problems
#### Has header

## UCI:breast cancer wisconsin
Available at UCI repository

### Problems
#### Many fields
32 fields


## UCI:Human Activity Recognition Using Smartphones
Available at UCI repository

### Problems
X_test.txt file only was checked
#### whitespace delimiters with inconsistent width 
sometimes 1, sometimes 2 whitespaces, e.g.
`  aaaa bbb  cccc aa  mmm`
#### whitespace at the beginning of every line
e.g.:
`  aaaa bbb  cccc aa  mmm`


## UCI:Wine quality

### Problems

#### uses semicolon ";" as delimiter
default autodetection doesn't work

## UCI:Abalone

### Problems
No problems

## UCI:Bank marketing

### Problems

#### uses semicolon ";" as delimiter
default autodetection doesn't work

#### all strings are enclosed in double quotes, e.g.:
`30;"unemployed";"married";"primary";"no";1787;"no";"no";"cellular";19;"oct";79;1;-1;0;"unknown";"no"`

## Kaggle:IMDB 5000
### Problems
No problems

## Kaggle:Soccer
### Problems
#### binary format
The dataset is in sqlite format

## Kaggle:credit cards fraud
### Problems
#### huge file (144 MB)
takes 30 second to perform this js query:
`Select * order by a2 * 1.0 desc where NR != 1`
python equivalent takes ~ the same time

## Kaggle:human_resources_analytics
### Problems
No problems

# Common problems
* empty last line. i.e. two '\n\n' at the end of file
* whitespaces after comma
* header line

