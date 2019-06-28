syntax match column0 /,[^,]*$/
syntax match column0 /,[^,]*,/me=e-1 nextgroup=escaped_column1,column1
syntax match escaped_column0 /, *"\([^"]*""\)*[^"]*" *$/
syntax match escaped_column0 /, *"\([^"]*""\)*[^"]*" *,/me=e-1 nextgroup=escaped_column1,column1
syntax match column1 /,[^,]*$/
syntax match column1 /,[^,]*,/me=e-1 nextgroup=escaped_column2,column2
syntax match escaped_column1 /, *"\([^"]*""\)*[^"]*" *$/
syntax match escaped_column1 /, *"\([^"]*""\)*[^"]*" *,/me=e-1 nextgroup=escaped_column2,column2
syntax match column2 /,[^,]*$/
syntax match column2 /,[^,]*,/me=e-1 nextgroup=escaped_column3,column3
syntax match escaped_column2 /, *"\([^"]*""\)*[^"]*" *$/
syntax match escaped_column2 /, *"\([^"]*""\)*[^"]*" *,/me=e-1 nextgroup=escaped_column3,column3
syntax match column3 /,[^,]*$/
syntax match column3 /,[^,]*,/me=e-1 nextgroup=escaped_column4,column4
syntax match escaped_column3 /, *"\([^"]*""\)*[^"]*" *$/
syntax match escaped_column3 /, *"\([^"]*""\)*[^"]*" *,/me=e-1 nextgroup=escaped_column4,column4
syntax match column4 /,[^,]*$/
syntax match column4 /,[^,]*,/me=e-1 nextgroup=escaped_column5,column5
syntax match escaped_column4 /, *"\([^"]*""\)*[^"]*" *$/
syntax match escaped_column4 /, *"\([^"]*""\)*[^"]*" *,/me=e-1 nextgroup=escaped_column5,column5
syntax match column5 /,[^,]*$/
syntax match column5 /,[^,]*,/me=e-1 nextgroup=escaped_column6,column6
syntax match escaped_column5 /, *"\([^"]*""\)*[^"]*" *$/
syntax match escaped_column5 /, *"\([^"]*""\)*[^"]*" *,/me=e-1 nextgroup=escaped_column6,column6
syntax match column6 /,[^,]*$/
syntax match column6 /,[^,]*,/me=e-1 nextgroup=escaped_column7,column7
syntax match escaped_column6 /, *"\([^"]*""\)*[^"]*" *$/
syntax match escaped_column6 /, *"\([^"]*""\)*[^"]*" *,/me=e-1 nextgroup=escaped_column7,column7
syntax match column7 /,[^,]*$/
syntax match column7 /,[^,]*,/me=e-1 nextgroup=escaped_column8,column8
syntax match escaped_column7 /, *"\([^"]*""\)*[^"]*" *$/
syntax match escaped_column7 /, *"\([^"]*""\)*[^"]*" *,/me=e-1 nextgroup=escaped_column8,column8
syntax match column8 /,[^,]*$/
syntax match column8 /,[^,]*,/me=e-1 nextgroup=escaped_column9,column9
syntax match escaped_column8 /, *"\([^"]*""\)*[^"]*" *$/
syntax match escaped_column8 /, *"\([^"]*""\)*[^"]*" *,/me=e-1 nextgroup=escaped_column9,column9
syntax match column9 /,[^,]*$/
syntax match column9 /,[^,]*,/me=e-1 nextgroup=escaped_column0,column0
syntax match escaped_column9 /, *"\([^"]*""\)*[^"]*" *$/
syntax match escaped_column9 /, *"\([^"]*""\)*[^"]*" *,/me=e-1 nextgroup=escaped_column0,column0
syntax match startcolumn /^[^,]*/ nextgroup=escaped_column1,column1
syntax match escaped_startcolumn /^ *"\([^"]*""\)*[^"]*" *$/
syntax match escaped_startcolumn /^ *"\([^"]*""\)*[^"]*" *,/me=e-1 nextgroup=escaped_column1,column1
