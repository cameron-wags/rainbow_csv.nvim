let g:rbql_test_log_records = []


func! AssertEqual(lhs, rhs)
    if a:lhs != a:rhs
        let msg = 'FAIL. Equal assertion failed: "' . string(a:lhs) . '" != "' . string(a:rhs) . '"'
        throw msg
    endif
endfunc


func! AssertTrue(expr, error_msg)
    if !a:expr
        let msg = 'FAIL. True assertion failed: ' . a:error_msg
        throw msg
    endif
endfunc


func! TestAlignStats()
    let field = 'foobar'
    let is_first_line = 0
    let field_components = [0, 0, 0]
    call rainbow_csv#update_subcomponent_stats(field, is_first_line, field_components)
    call AssertEqual(field_components, [6, -1, -1])

    let field = 'foobar'
    let is_first_line = 1
    let field_components = [0, 0, 0]
    call rainbow_csv#update_subcomponent_stats(field, is_first_line, field_components)
    call AssertEqual(field_components, [6, 0, 0])
endfunc


func! TestWhitespaceSplit()
    call AssertEqual(rainbow_csv#whitespace_split('  hello   world ', 0), ['hello', 'world'])
    call AssertEqual(rainbow_csv#whitespace_split('   ', 0), [''])
    call AssertEqual(rainbow_csv#whitespace_split('   ', 1), ['   '])
    call AssertEqual(rainbow_csv#whitespace_split('  hello   world ', 0), ['hello', 'world'])
    call AssertEqual(rainbow_csv#whitespace_split('hello   world ', 0), ['hello', 'world'])
    call AssertEqual(rainbow_csv#whitespace_split('   hello   world', 0), ['hello', 'world'])
    call AssertEqual(rainbow_csv#whitespace_split(' hello  world ', 1), [' hello', ' world '])
    call AssertEqual(rainbow_csv#whitespace_split(' hello  world', 1), [' hello', ' world'])
    call AssertEqual(rainbow_csv#whitespace_split('hello  world ', 1), ['hello', ' world '])
    call AssertEqual(rainbow_csv#whitespace_split(' a ', 1), [' a '])
    call AssertEqual(rainbow_csv#whitespace_split('a ', 1), ['a '])
    call AssertEqual(rainbow_csv#whitespace_split(' a', 1), [' a'])
    call AssertEqual(rainbow_csv#whitespace_split(' a ', 0), ['a'])
    call AssertEqual(rainbow_csv#whitespace_split('a ', 0), ['a'])
    call AssertEqual(rainbow_csv#whitespace_split(' a', 0), ['a'])
    call AssertEqual(rainbow_csv#whitespace_split(' aa hello  world   bb ', 1), [' aa', 'hello', ' world', '  bb '])
    call AssertEqual(rainbow_csv#whitespace_split(' aa hello  world   bb ', 0), ['aa', 'hello', 'world', 'bb'])
endfunc


func! RunUnitTests()
    call add(g:rbql_test_log_records, 'Starting Test: Statusline')

    "10,a,b,20000,5
    "a1 a2 a3 a4  a5
    let test_stln = rainbow_csv#generate_tab_statusline(1, 1, ['10', 'a', 'b', '20000', '5'])
    let test_stln_str = join(test_stln, '')
    let canonic_stln = 'a1 a2 a3 a4  a5'
    call AssertEqual(test_stln_str, canonic_stln)

    "10  a   b   20000   5
    "a1  a2  a3  a4      a5
    let test_stln = rainbow_csv#generate_tab_statusline(4, 1, ['10', 'a', 'b', '20000', '5'])
    let test_stln_str = join(test_stln, '')
    let canonic_stln = 'a1  a2  a3  a4      a5'
    call AssertEqual(test_stln_str, canonic_stln)

    call AssertEqual(rainbow_csv#preserving_quoted_split('   ', ',')[0], ['   '])
    call AssertEqual(rainbow_csv#quoted_split('   ', ','), [''])
    call AssertEqual(rainbow_csv#quoted_split(' "  abc  " , abc , bbb ', ','), ['  abc  ', 'abc', 'bbb'])

    let test_cases = []
    call add(test_cases, ['abc', 'abc'])
    call add(test_cases, ['abc,', 'abc;'])
    call add(test_cases, [',abc', ';abc'])
    call add(test_cases, ['abc,cdef', 'abc;cdef'])
    call add(test_cases, ['"abc",cdef', '"abc";cdef'])
    call add(test_cases, ['abc,"cdef"', 'abc;"cdef"'])
    call add(test_cases, ['"a,bc",cdef', '"a,bc";cdef'])
    call add(test_cases, ['abc,"c,def"', 'abc;"c,def"'])
    call add(test_cases, [',', ';'])
    call add(test_cases, [', ', '; '])
    call add(test_cases, ['"abc"', '"abc"'])
    call add(test_cases, [',"haha,hoho",', ';"haha,hoho";'])
    call add(test_cases, ['"a,bc","adf,asf","asdf,asdf,","as,df"', '"a,bc";"adf,asf";"asdf,asdf,";"as,df"'])

    call add(test_cases, [' "  abc  " , abc , bbb ', ' "  abc  " ; abc ; bbb '])

    for nt in range(len(test_cases))
        let test_str = join(rainbow_csv#preserving_quoted_split(test_cases[nt][0], ',')[0], ';')
        let canonic_str = test_cases[nt][1]
        call AssertEqual(test_str, canonic_str)
    endfor

    call TestWhitespaceSplit()

    call TestAlignStats()
    
    call add(g:rbql_test_log_records, 'Finished Test: Statusline')
endfunc


func! TestSplitRandomCsv()
    "FIXME compare warnings equality too since vim function can now return them
    let lines = readfile('./random_ut.csv')
    for line in lines
        let records = split(line, "\t", 1)
        call AssertEqual(len(records), 3)
        let escaped_entry = records[0]
        let canonic_warning = str2nr(records[1])
        call AssertTrue(canonic_warning == 0 || canonic_warning == 1, 'warning must be either 0 or 1')
        let canonic_dst = split(records[2], ';', 1)
        let test_dst = rainbow_csv#preserving_quoted_split(escaped_entry, ',')[0]
        if !canonic_warning
            call AssertEqual(len(canonic_dst), len(test_dst))
            call AssertEqual(join(test_dst, ','), escaped_entry)
            let unescaped_dst = rainbow_csv#unescape_quoted_fields(test_dst)
            call AssertEqual(join(unescaped_dst, ';'), records[2])
        endif
    endfor
endfunc
