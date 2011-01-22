#!/usr/bin/python

# bouncing_ball.py

from __future__ import division

import math
import itertools

import shape
import render

class ball(shape.sphere):
    def __init__(self, radius):
        super(ball, self).__init__(shape.point(-2, 3, 8), radius)
        self.v = shape.point(0.3, 0.4, math.sqrt(1.0 - 0.3*0.3 - 0.4*0.4)) \
                      .scale(1.5)

    def move(self):
        self.center += self.v
        if self.center.z - self.radius < 0:
            self.center.z += -2*(self.center.z - self.radius)
            self.v.z = -self.v.z
        elif self.center.z + self.radius > 15:
            self.center.z -= 2*(self.center.z + self.radius - 15)
            self.v.z = -self.v.z
        d = math.hypot(self.center.x, self.center.y)
        if d + self.radius > 7.5:
            scale = (d - 2*(d + self.radius - 7.5)) / d
            self.center.x *= scale
            self.center.y *= scale
            pa = math.atan2(self.center.y, self.center.x)
            va = math.atan2(self.v.y, self.v.x)
            vh = math.hypot(self.v.x, self.v.y)
            va += math.pi - 2*(va - pa)
            self.v.x = vh * math.cos(va)
            self.v.y = vh * math.sin(va)

    def gen_frame(self):
        self.move()
        return render.frame(self)

def gen(filename = 'bounce.bin', secs = 8, diameter = 4):
    b = ball(diameter // 2)
    with open(filename, 'wb') as f:
        render.to_file(f,
          itertools.chain.from_iterable(b.gen_frame()
                                        for _ in xrange(secs * 10)))

if __name__ == "__main__":
    gen()
