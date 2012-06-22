# testplot.py

r'''Test the matplotlib.pyplot plot function.
'''

from __future__ import print_function

import sys
from matplotlib.pyplot import plot, show

xy = [(1,10), (2,20), (3,40)]
x = [1.1, 2, 4.9]
y = [10, 20.0, 39]

#plot(xy, 'r-')
#show()

plot(x, y, 'r+')
show()
