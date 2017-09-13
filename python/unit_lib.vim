let g:rbql_test_log_records = []


func! AssertEqual(lhs, rhs)
    if a:lhs != a:rhs
        let msg = 'FAIL. Equal assertion failed: "' . a:lhs . '" != "' . a:rhs '"'
        call add(g:rbql_test_log_records, msg)
    endif
endfunc


func! RunUnitTests()
    call add(g:rbql_test_log_records, 'Starting Test: Statusline')
    "10,a,b,20000,5
    "a1 a2 a3 a4  a5
    let test_stln = rainbow_csv#generate_tab_statusline(1, ['10', 'a', 'b', '20000', '5'])
    let test_stln_str = join(test_stln, '')
    let canonic_stln = 'a1 a2 a3 a4  a5'
    call AssertEqual(test_stln_str, canonic_stln)

    "10  a   b   20000   5
    "a1  a2  a3  a4      a5
    let test_stln = rainbow_csv#generate_tab_statusline(4, ['10', 'a', 'b', '20000', '5'])
    let test_stln_str = join(test_stln, '')
    let canonic_stln = 'a1  a2  a3  a4      a5'
    call AssertEqual(test_stln_str, canonic_stln)

    let test_cases = [
        \ ['abc',                                   'abc'],
        \ ['abc,',                                  'abc;'],
        \ [',abc',                                  ';abc'],
        \ ['abc,cdef',                              'abc;cdef'],
        \ ['"abc",cdef',                            '"abc";cdef'],
        \ ['abc,"cdef"',                            'abc;"cdef"'],
        \ ['"a,bc",cdef',                           '"a,bc";cdef'],
        \ ['abc,"c,def"',                           'abc;"c,def"'],
        \ ['abc,"cdef,"acdf,"asddf',                'abc;"cdef;"acdf;"asddf'],
        \ [',',                                     ';'],
        \ [', ',                                    '; '],
        \ ['"abc"',                                 '"abc"'],
        \ [',"haha,hoho",',                         ';"haha,hoho";'],
        \ [',"bbbb,"cccc,"',                        ';"bbbb,"cccc,"'],
        \ [',",","',                                ';",";"'],
        \ ['"a,bc","adf,asf","asdf,asdf,","as,df"', '"a,bc";"adf,asf";"asdf,asdf,";"as,df"'],
        \ ]

    for nt in range(len(test_cases))
        let test_str = join(rainbow_csv#split_escaped_csv_str(test_cases[nt][0]), ';')
        let canonic_str = test_cases[nt][1]
        call AssertEqual(test_str, canonic_str)
    endfor

    call add(g:rbql_test_log_records, 'Finished Test: Statusline')
endfunc
