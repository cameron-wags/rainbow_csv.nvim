function split_quoted_str(src, dlm) {
    if (src.indexOf('"') == -1)
        return [src.split(dlm), false];
    var result = [];
    var warning = false;
    var cidx = 0;
    while (cidx < src.length) {
        if (src.charAt(cidx) === '"') {
            var uidx = cidx + 1;
            while (true) {
                uidx = src.indexOf('"', uidx);
                if (uidx == -1) {
                    result.push(src.substring(cidx + 1).replace(/""/g, '"'));
                    return [result, true];
                } else if (uidx + 1 >= src.length || src.charAt(uidx + 1) == dlm) {
                    result.push(src.substring(cidx + 1, uidx).replace(/""/g, '"'));
                    cidx = uidx + 2;
                    break;
                } else if (src.charAt(uidx + 1) == '"') {
                    uidx += 2; 
                    continue;
                } else {
                    warning = true;
                    uidx += 1;
                    continue;
                }
            }
        } else {
            var uidx = src.indexOf(dlm, cidx);
            if (uidx == -1)
                uidx = src.length;
            var field = src.substring(cidx, uidx);
            if (field.indexOf('"') != -1)
                warning = true;
            result.push(field);
            cidx = uidx + 1;
        }
    }
    if (src.charAt(src.length - 1) == dlm)
        result.push('');
    return [result, warning];
}


function MinAggregator() {
    this.stats = new Map();

    this.increment = function(key, val) {
        var cur_aggr = this.stats.get(key);
        if (cur_aggr === undefined) {
            this.stats.set(key, val);
        } else {
            this.stats.set(key, Math.min(cur_aggr, val));
        }
    }

    this.get_final = function(key) {
        return this.stats.get(key);
    }
}


function MaxAggregator() {
    this.stats = new Map();

    this.increment = function(key, val) {
        var cur_aggr = this.stats.get(key);
        if (cur_aggr === undefined) {
            this.stats.set(key, val);
        } else {
            this.stats.set(key, Math.max(cur_aggr, val));
        }
    }

    this.get_final = function(key) {
        return this.stats.get(key);
    }
}


function SubkeyChecker() {
    this.subkeys = new Map();

    this.increment = function(key, subkey) {
        var old_subkey = this.subkeys.get(key);
        if (old_subkey === undefined) {
            this.subkeys.set(key, subkey);
        } else if (old_subkey != subkey) {
            throw 'Unable to group by "' + key + '", different values in output: "' + old_subkey + '" and "' + subkey + '"';
        }
    }

    this.get_final = function(key) {
        return this.subkeys.get(key);
    }
}


module.exports.split_quoted_str = split_quoted_str;
module.exports.MinAggregator = MinAggregator;
module.exports.MaxAggregator = MaxAggregator;
module.exports.SubkeyChecker = SubkeyChecker;
