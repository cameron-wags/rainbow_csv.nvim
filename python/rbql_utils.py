def split_quoted_str(src, dlm):
    assert dlm != '"'
    if src.find('"') == -1: #optimization for majority of lines
        return (src.split(dlm), False)
    result = list()
    warning = False
    cidx = 0
    while cidx < len(src):
        if src[cidx] == '"':
            uidx = cidx + 1
            while True:
                uidx = src.find('"', uidx)
                if uidx == -1:
                    result.append(src[cidx+1:].replace('""', '"'))
                    return (result, True)
                elif uidx + 1 >= len(src) or src[uidx + 1] == dlm:
                    result.append(src[cidx+1:uidx].replace('""', '"'))
                    cidx = uidx + 2
                    break
                elif src[uidx + 1] == '"':
                    uidx += 2
                    continue
                else:
                    warning = True
                    uidx += 1
                    continue
        else:
            uidx = src.find(dlm, cidx)
            if uidx == -1:
                uidx = len(src)
            field = src[cidx:uidx]
            if field.find('"') != -1:
                warning = True
            result.append(field)
            cidx = uidx + 1
    if src[-1] == dlm:
        result.append('')
    return (result, warning)
            

def rows(f, chunksize=1024, sep='\n'):
    incomplete_row = None
    while True:
        chunk = f.read(chunksize)
        if not chunk:
            if incomplete_row is not None and len(incomplete_row):
                yield incomplete_row
            return
        while True:
            i = chunk.find(sep)
            if i == -1:
                break
            if incomplete_row is not None:
                yield incomplete_row + chunk[:i]
                incomplete_row = None
            else:
                yield chunk[:i]
            chunk = chunk[i+1:]
        if incomplete_row is not None:
            incomplete_row += chunk
        else:
            incomplete_row = chunk


