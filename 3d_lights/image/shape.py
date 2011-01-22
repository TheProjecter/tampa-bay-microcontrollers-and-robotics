# shape.py

from __future__ import division

import math

class point(object):
    def __init__(self, x, y, z):
        self.x = x
        self.y = y
        self.z = z

    @classmethod
    def semi_polar(cls, ro, theta, z):
        r'''Polar rather than x, y, but z still cartesian.

        ro in degrees.

            >>> point.semi_polar(0,1,2)
            (1.0, 0.0, 2.0)
            >>> point.semi_polar(90,1,2)
            (0.0, 1.0, 2.0)
            >>> point.semi_polar(180,1,2)
            (-1.0, 0.0, 2.0)
            >>> point.semi_polar(270,1,2)
            (0.0, -1.0, 2.0)
        '''
        radians = math.radians(ro)
        return cls(theta * math.cos(radians), theta * math.sin(radians), z)

    def __repr__(self):
        def fix(n): return n if abs(n) > 0.04 else 0.0
        return "(%.1f, %.1f, %.1f)" % (fix(self.x), fix(self.y), fix(self.z))

    def __add__(self, b):
        r'''The + operator on points.

            >>> point(1,2,3) + point(4,5,6)
            (5.0, 7.0, 9.0)
            >>> a = point(1,2,3)
            >>> a += point(4,5,6)
            >>> a
            (5.0, 7.0, 9.0)
        '''
        return point(self.x + b.x, self.y + b.y, self.z + b.z)

    def __sub__(self, b):
        r'''The - operator on points.

            >>> point(5,7,9) - point(1,2,3)
            (4.0, 5.0, 6.0)
        '''
        return point(self.x - b.x, self.y - b.y, self.z - b.z)

    def distance_to(self, b):
        r'''The distance from self to b.

            >>> point(10,20,30).distance_to(point(19,8,50))
            25.0
        '''
        return math.hypot(math.hypot(self.x - b.x, self.y - b.y), self.z - b.z)
    
    def scale(self, n):
        return point(self.x * n, self.y * n, self.z * n)

class shape(object):
    r'''Might add coordinate transformation logic here later...
    '''
    def __init__(self): pass

    def __contains__(self, point):
        if point is None: return False
        return self.contains(point)

class sphere(shape):
    r'''A simple sphere.
    
    Don't have to worry about coordinate transformations here!

        >>> point(1,0,0) in sphere(point(0,0,0), 1)
        True
        >>> point(1,0.1,0) in sphere(point(0,0,0), 1)
        False
        >>> point(0.57735,0.57735,0.57735) in sphere(point(0,0,0), 1)
        True
        >>> point(0.57736,0.57736,0.57736) in sphere(point(0,0,0), 1)
        False
    '''
    def __init__(self, center, radius):
        self.center = center
        self.radius = radius

    def __repr__(self):
        return "<sphere at %s, radius %g>" % (self.center, self.radius)

    def contains(self, point):
        return self.center.distance_to(point) <= self.radius + 1e-4
