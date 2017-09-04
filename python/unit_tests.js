rbql_utils = require('./rbql_utils.js')

function arrays_are_equal(a, b) {
    if (a.length != b.length)
        return false;
    for (var i = 0; i < a.length; i++) {
        if (a[i] !== b[i])
            return false;
    }
    return true;
}


function test_split() {
    var test_cases = []
    test_cases.push(['hello,world', ['hello','world']])
    test_cases.push(['hello,"world"', ['hello','world']])
    test_cases.push(['"abc"', ['abc']])
    test_cases.push(['abc', ['abc']])
    test_cases.push(['', ['']])
    test_cases.push([',', ['','']])
    test_cases.push([',,,', ['','','','']])
    test_cases.push([',"",,,', ['','','','','']])
    test_cases.push(['"","",,,""', ['','','','','']])
    test_cases.push(['"aaa,bbb",', ['aaa,bbb','']])
    test_cases.push(['"aaa,bbb",ccc', ['aaa,bbb','ccc']])
    test_cases.push(['"aaa,bbb","ccc"', ['aaa,bbb','ccc']])
    test_cases.push(['"aaa,bbb","ccc,ddd"', ['aaa,bbb','ccc,ddd']])
    test_cases.push(['"aaa,bbb",ccc,ddd', ['aaa,bbb','ccc', 'ddd']])
    test_cases.push(['"a"aa" a,bbb",ccc,ddd', ['a"aa" a,bbb','ccc', 'ddd']])
    test_cases.push(['"aa, bb, cc",ccc",ddd', ['aa, bb, cc','ccc"', 'ddd']])
    for (var i = 0; i < test_cases.length; i++) {
        var src = test_cases[i][0];
        var canonic_dst = test_cases[i][1];
        var test_dst = rbql_utils.split_escaped_csv_str(src);
        if (!arrays_are_equal(test_dst, canonic_dst)) {
            console.error('Error while running csv split unit test ' + i + ':');
            console.error('Source: ' + src);
            console.error('Test result: ' + test_dst);
            console.error('Canonic result: ' + canonic_dst);
        }
    }
    console.log('Finished split unit test');
}

test_split();
