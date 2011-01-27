#!/usr/bin/python

# invert.py

def run(filein, fileout):
    with open(filein, 'rb') as f_in:
        with open(fileout, 'wb') as f_out:
            while True:
                b = f_in.read(1)
                if len(b) == 0: break
                v = ord(b)
                f_out.write(chr(v ^ 0xff))

if __name__ == "__main__":
    import sys
    assert len(sys.argv) == 3
    print sys.argv[1], sys.argv[2]
    run(sys.argv[1], sys.argv[2])
