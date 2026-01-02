from cython.view cimport array as cvarray
from libc.stdlib cimport malloc, free
from cpython.unicode cimport PyUnicode_FromKindAndData, PyUnicode_4BYTE_KIND
import numpy as np
cimport numpy as cnp

def extract_tags(unicode s):
    cdef:
        int length = len(s)
        int i = 0
        int j = 0
        int x = 0
        int ntag = 0
        int maxtag = int(length / 3)
        unicode new
        Py_UCS4 *text = <Py_UCS4 *>malloc(length * sizeof(Py_UCS4))
        Py_UCS4 c
        cnp.ndarray arr
        cnp.ndarray row
        list tags

    arr = np.ndarray(shape=(maxtag, 4), dtype=np.int32)

    while i < length:
        c = s[i]

        if c == u'<':
            j = i
            while (j < length):
                if s[j] == u'>':
                    arr[ntag] = (x, i, j+1-i, j+1)
                    i = j
                    break
                j += 1
            ntag += 1

        else:
            text[x] = c
            x += 1

        i += 1

    text[x] = 0
    new = PyUnicode_FromKindAndData(PyUnicode_4BYTE_KIND, text, x)
    free(text)

    tags = [s[row[1]:row[3]] for row in arr[:ntag,:]]

    return arr[:ntag,:3], tags, new
