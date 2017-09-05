function split_escaped_csv_str(src) {
    if (src.indexOf('"') == -1)
        return src.split(',')
    var result = [];
    var cidx = 0
    if (src.charAt(0) === ',') {
        result.push('');
        cidx = 1;
    }
    while (cidx < src.length) {
        if (src.charAt(cidx) === '"') {
            var uidx = src.indexOf('",', cidx + 1);
            if (uidx != -1) {
                uidx += 1;
            } else if (uidx == -1 && src.charAt(src.length - 1) == '"') {
                uidx = src.length;
            }
            if (uidx != -1) {
                result.push(src.substring(cidx + 1, uidx - 1));
                cidx = uidx + 1;
                continue;
            }
        }
        var uidx = src.indexOf(',', cidx);
        if (uidx == -1)
            uidx = src.length;
        result.push(src.substring(cidx, uidx));
        cidx = uidx + 1;
    }
    if (src.charAt(src.length - 1) == ',')
        result.push('');
    return result;
}

module.exports.split_escaped_csv_str = split_escaped_csv_str;
