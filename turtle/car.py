# car.py

from __future__ import division

import turtle
import math

Car_body = ((-5,-10),(-5,10),(5,10),(5,-10))

Car_components = (
    (Car_body, "black"),                            # main body
    (((-8,6),(-8,12),(-5,12),(-5,6)), "black"),     # lf wheel
    (((8,6),(8,12),(5,12),(5,6)), "black"),         # rf wheel
    (((-8,-6),(-8,-12),(-5,-12),(-5,-6)), "black"), # lr wheel
    (((8,-6),(8,-12),(5,-12),(5,-6)), "black"),     # rr wheel
)

def make_car_shape(angle=None):
    beacon_len = 60
    beacon_width = 40  # degrees
    car = turtle.Shape('compound')
    for args in Car_components: car.addcomponent(*args)
    if angle is None: return car
    la = math.radians(angle - beacon_width/2)
    ra = math.radians(angle + beacon_width/2)
    lx, ly = beacon_len*math.sin(la), beacon_len*math.cos(la)
    rx, ry = beacon_len*math.sin(ra), beacon_len*math.cos(ra)
    car.addcomponent(((0,10),(lx,ly),(rx,ry)), "", "blue")
    return car

class screen(object):
    def __init__(self):
        global Screen
        self.screen = turtle.Screen()
        self.screen.setup(width=0.70, height=0.90)
        self.screen.title("Intelligent Robot Car")
        self.screen.mode('logo')
        self.screen.register_shape('box', ((0,0),(0,10),(10,10),(10,0)))
        self.screen.register_shape('car', make_car_shape())
        self.screen.register_shape('car_looking_forward', make_car_shape(0))
        self.screen.register_shape('car_looking_left', make_car_shape(-30))
        self.screen.register_shape('car_looking_right', make_car_shape(30))
        self.screen.delay(10) # mSec
        Screen = self

    def __enter__(self):
        return self

    def __exit__(self, type, value, tb):
        self.close()

    def close(self):
        self.screen.bye()

class car(turtle.RawTurtle):
    def __init__(self):
        super(car, self).__init__(Screen.screen)
        self.penup()
        self.set_steering_angle(0)
        self.range_finder_off()

    def set_steering_angle(self, angle):
        self.steering_angle = angle

    def range_finder_on(self, direction):
        if direction not in ('left', 'straight', 'right'):
            raise ValueError("illegal direction: %r" % direction)
        self.range_finder_direction = direction
        if direction == 'left':
            self.shape('car_looking_left')
        elif direction == 'right':
            self.shape('car_looking_right')
        else:
            self.shape('car_looking_forward')

    def range_finder_off(self):
        self.shape('car')
        self.range_finder_direction = 'off'

    def go_forward(self, distance):
        self.forward(distance)

    def go_backward(self, distance):
        self.backward(distance)

    def hit(self, obstacle):
        heading = math.radians(self.heading)
        sin, cos = math.sin(heading), math.cos(heading)
        corners = [translate(x, y, sin, cos) for x, y in Car_body]
        if any(corner in obstacle for corner in corners):
            raise ValueError()

Car_body
    (((-5,-10),(-5,10),(5,10),(5,-10))

def translate(x, y, sin, cos):
    return x * cos + y * sin, y * cos - x * sin

class obstacle(turtle.RawTurtle):
    def __init__(self, llx, lly, width, height, angle = 0):
        super(obstacle, self).__init__(Screen.screen)
        self.penup()
        self.speed(0)
        self.shape('box')
        self.shapesize(width/10, height/10)
        self.setheading(angle)
        self.setpos(llx, lly)
        ar = math.radians(angle)
        sin, cos = math.sin(ar), math.cos(ar)
        self.ll = llx, lly
        self.ul = llx + height * sin, lly + height * cos
        self.ur = self.ul[0] + width * cos, self.ul[1] - width * sin
        self.lr = llx + width * cos, lly - width * sin

    def test(self):
        obstacle(self.ll[0] - 10, self.ll[1] - 10, 10, 10)
        obstacle(self.ul[0] - 10, self.ul[1], 10, 10)
        obstacle(self.ur[0], self.ur[1], 10, 10)
        obstacle(self.lr[0], self.lr[1] - 10, 10, 10)

    def distance(self, x, y):
        return min(self.ll, self.ul) <= x <= max(self.lr, self.ur) and \
               min(self.ll, self.lr) <= y <= max(self.ul, self.ur)

