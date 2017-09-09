# Survey of public csv datasets

## Game of Thrones Battles
Available on kaggle: https://www.kaggle.com/mylesoneill/game-of-thrones 

### Problems
#### Has '\r' line separators
vim incorrectly interprets the file as a single but very long line

#### both consequtive double quotes and comma inside one of the quoted fields
looks like this:
  `...,"It isn't mentioned how many Stark men are left in Winterfell, other than ""very few""."`


## Game of Thrones characters deaths
Available on kaggle: https://www.kaggle.com/mylesoneill/game-of-thrones 

### Problems
#### Has '\r' line separators
vim incorrectly interprets the file as a single but very long line


## UCI:adult
Available at UCI repository: http://archive.ics.uci.edu/ml/machine-learning-databases/adult/
### Problems
#### last line is empty

#### whitespaces after commas:
`22, Private, 201490, HS-grad, 9, Never-married, Adm-clerical, Own-child, White, Male, 0, 0, 20, United-States, <=50K`
