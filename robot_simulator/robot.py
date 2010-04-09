# robot.py

from __future__ import division

import sys
import time
import math
import pygame

import robot_simulator
from robot_simulator import background

Range_width, Range_distance = 20, 30

Car_body = (3, 2, 10, 20)

Car_components = (
    (robot_simulator.Green, Car_body),        # main body
    (robot_simulator.Black, (6, 4, 4, 4)),    # front mark
    (robot_simulator.Black, (0, 0, 3, 6)),    # lf wheel
    (robot_simulator.Black, (13, 0, 3, 6)),   # rf wheel
    (robot_simulator.Black, (0, 18, 3, 6)),   # lr wheel
    (robot_simulator.Black, (13, 18, 3, 6)),  # rr wheel
)

class car_image(pygame.Surface):
    def __init__(self):
        super(car_image, self).__init__((16, 24))
        self.set_colorkey(robot_simulator.White, pygame.RLEACCEL)
        self.fill(robot_simulator.White)
        for color, rect in Car_components:
            self.fill(color, rect)

        # when heading is 0:
        #   logical center = image center + logical_center
        self.logical_center = (0, -10)

class rotatable_sprite(pygame.sprite.Sprite):
    def __init__(self, name, group, image):
        super(rotatable_sprite, self).__init__(group)
        self.name = name
        self.base_image = image
        self.heading = 0.0
        self.image = image
        self.rect = self.image.get_rect()
        lcx, lcy = self.base_image.logical_center
        cx, cy = self.rect.center
        self.offset = lcx, lcy
        self.position = cx + lcx, cy + lcy
        #print self.name, "initial position", self.position

    def update(self, fn, *args):
        getattr(self, fn)(*args)

    def move_to(self, pos):
        px, py = self.position = pos
        lcx, lcy = self.offset
        self.rect.center = round(px - lcx), round(py - lcy)
        return self.rect

    def rotate(self, angle):
        #print self.name, "pre-rotated rect", self.rect, \
        #                 "center", self.rect.center, \
        #                 "at heading", self.heading

        self.heading += angle
        self.image = pygame.transform.rotate(self.base_image, -self.heading)
        self.rect = self.image.get_rect()

        # This shows the influence of x at heading h.
        #
        #         |
        #         |
        # --------+-------> x+
        #         |\h |
        #         | \ | sin
        #         |  \|
        #         |---+
        #         |cos  
        #         |
        #         V
        #         y+

        # This shows the influence of y at heading h.
        #
        #         |
        #         |
        # --------+-------> x+
        #     |  /|
        # cos | /h|
        #     |/  |
        #     +---|
        #      sin|  
        #         |
        #         V
        #         y+

        ra = math.radians(self.heading)
        sin, cos = math.sin(ra), math.cos(ra)
        x, y = self.base_image.logical_center
        #print self.name, "logical_center offset at heading 0", (x, y)
        self.offset = x * cos - y * sin, y * cos + x * sin
        #print self.name, "new logical center offset", self.offset
        #print self.name, "position", self.position, \
        #                 "rotated rect.center", self.rect.center
        self.move_to(self.position)
        #print self.name, "adjusted rect.center", self.rect.center
        #print self.name, "rotated rect", self.rect, "at heading", self.heading


class robot_sprite(rotatable_sprite):
    def __init__(self, name, group, image):
        super(robot_sprite, self).__init__(name, group, image)
        self.move_to(group.position)

class range_finder_image(pygame.Surface):
    def __init__(self):
        super(range_finder_image, self).__init__((Range_width, Range_distance))
        self.set_colorkey(robot_simulator.White, pygame.RLEACCEL)
        self.set_alpha(80, pygame.RLEACCEL)
        self.fill(robot_simulator.Red)

        # when heading is 0:
        #   logical center = image center + logical_center
        self.logical_center = 0, Range_distance/2

class robot(pygame.sprite.RenderUpdates):
    def __init__(self, posx, posy):
        super(robot, self).__init__()
        self.heading = 0.0
        self.heading_per_tick = 0.0
        self.direction = 0
        self.position = posx, posy
        self.rf = robot_sprite('range_finder', self, range_finder_image())
        self.remove(self.rf)
        self.rf_angle = None

    def set_steering(self, rate):
        self.heading_per_tick = rate/10.0

    def set_rf(self, angle=None):
        r'''Set range finder angle.

        An angle of None turns off the range finder.
        '''
        self.erase_image()
        if angle is None:
            if self.rf_angle is not None:
                self.remove(self.rf)
        else:
            if self.rf_angle is None:
                self.add(self.rf)
                self.rf.move_to(self.position)
            self.rf.rotate(self.heading + angle - self.rf.heading)
        self.rf_angle = angle
        self.draw_image()

    def set_direction(self, dir):
        self.direction = dir

    def erase_image(self):
        self.clear(robot_simulator.Screen, background.Background)

    def draw_image(self):
        pygame.display.update(self.draw(robot_simulator.Screen))

    def tick(self):
        if self.direction:
            self.erase_image()
            ra = math.radians(self.heading)
            dx, dy = \
              self.direction * math.sin(ra), -self.direction * math.cos(ra)
            #print "heading", self.heading, "dx", dx, "dy", dy
            ans = self.move_to((self.position[0] + dx, self.position[1] + dy))
            if self.heading_per_tick:
                self.rotate(self.heading_per_tick * self.direction)
            self.draw_image()
            return ans

    def forward(self, distance):
        self.set_direction(1)
        return self.go(distance)

    def backward(self, distance):
        self.set_direction(-1)
        return self.go(distance)

    def go(self, distance):
        for i in xrange(distance):
            for event in pygame.event.get():
                if event.type == pygame.QUIT: sys.exit()
            self.tick()
            time.sleep(0.005)
        return distance

    def move_to(self, pos):
        #print "move_to", pos
        self.position = pos
        ans = None
        for s in self:
            r = s.move_to(pos)
            #print "move got", r, "from", s
            if ans is None: ans = r
            else: ans = ans.union(r)
        return ans

    def rotate(self, angle):
        self.heading += angle
        for s in self:
            s.rotate(angle)

