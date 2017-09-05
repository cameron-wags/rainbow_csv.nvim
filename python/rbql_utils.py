def split_escaped_csv_str(src):
    if src.find('"') == -1: #optimization for majority of lines
        return src.split(',')
    result = list()
    cidx = 0
    if src[0] == ',':
        result.append('')
        cidx = 1
    while cidx < len(src):
        if src[cidx] == '"':
            uidx = src.find('",', cidx + 1)
            if uidx != -1:
                uidx += 1
            elif uidx == -1 and src[-1] == '"':
                uidx = len(src)
            if uidx != -1:
                result.append(src[cidx+1:uidx-1])
                cidx = uidx + 1
                continue
        uidx = src.find(',', cidx)
        if uidx == -1:
            uidx = len(src)
        result.append(src[cidx:uidx])
        cidx = uidx + 1
    if src[-1] == ',':
        result.append('')
    return result
            

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


