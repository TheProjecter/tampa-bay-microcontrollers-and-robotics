#!/usr/bin/python

# terminal.py

r'''Intelligent terminal for Arduino.

This runs on your PC as a toolset for your Arduino to interact with you.

print <rest>
input <prompt>
load $var1 [$var2...]                      # followed by space separated values,
                                           # terminated by blank line
plot {$var|value}... [format_string] [kwarg=value]...
show
'''

from __future__ import print_function

import sys
from matplotlib.pyplot import plot, show

import comm

Vars = {}

Debug = 0

def run(devnum=0, baud=comm.B57600, **kwargs):
    with comm.osclosing(comm.open(devnum, baud=baud, **kwargs)) as arduino:
        while True:
            line = comm.readline(arduino, strip_nulls=True)
            #print("got:", repr(line))
            command = line.split(' ', 1)
            if command:
                if Debug > 1: print("got:", repr(line))
                if command[0] == 'print':
                    if len(command) > 1:
                        print(command[1])
                    else:
                        print()
                elif command[0] == 'input':
                    if len(command) > 1:
                        ans = raw_input(command[1] + ' ')
                    else:
                        ans = raw_input('? ')
                    comm.write(arduino, ans)
                elif command[0] == 'load':
                    if len(command) != 2:
                        print("expected at least 1 argument to load, got {0}"
                               .format(len(command) - 1), file=sys.stderr)
                    else:
                        vars = command[1].split()
                        errors = 0
                        for var in vars:
                            if var[0] != '$':
                                print("load variable names must start with '$',"
                                      " got {0!r}".format(var), file=sys.stderr)
                                errors += 1
                        if errors == 0:
                            data = [[] for _ in vars]
                            line = comm.readline(arduino)
                            while line:
                                numbers = line.split()
                                if len(numbers) != len(vars):
                                    print("incorrect number of values, "
                                          "got {0}, expected {1}"
                                            .format(len(numbers), len(vars)))
                                    errors += 1
                                    break
                                else:
                                    for i, x in enumerate(line.split(' ')):
                                        data[i].append(to_number(x))
                                line = comm.readline(arduino)
                            for var, values in zip(vars, data):
                                Vars[var] = values
                            print("loaded", len(data[0]), "rows")
                elif command[0] == 'plot':
                    if len(command) < 2:
                        print("plot: must have at least one argument",
                              file=sys.stderr)
                    else:
                        args = []
                        kwargs = {}
                        for arg in command[1].split():
                            if arg[0] == '$':
                                args.append(Vars[arg])
                            elif '=' in arg:
                                kw_name, value = arg.split('=')
                                kwargs[kw_name] = value
                            else:
                                args.append(arg)
                        if Debug: print("plotting", args, kwargs)
                        plot(*args, **kwargs)
                elif command[0] == 'show':
                    print("this blocks until you close the plot window")
                    show()
                    #show(block=False)
                else:
                    print("illegal command from arduino:", repr(line),
                          file=sys.stderr)


def to_number(s):
    if '.' in s or 'e' in s or 'E' in s:
        return float(s)
    return int(s)


if __name__ == "__main__":
    try:
        run()
    except Exception as e:
        print("caught exception", e)
        raise
