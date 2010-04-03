# robot.py

from __future__ import division

import sys
import time
import math
import pygame

import robot_simulator
from robot_simulator import background

Car_body = (3, 2, 10, 20)

Car_components = (
    (robot_simulator.Green, Car_body),        # main body
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
        self.logical_center = (0, -10)   # from image center to logical center

class rotatable_sprite(pygame.sprite.Sprite):
    def __init__(self, group, image):
        super(rotatable_sprite, self).__init__(group)
        self.base_image = image
        self.heading = 0.0
        self.image = image
        self.rect = self.image.get_rect()

        # rect.topleft + offset == logical image center
        cx, cy = self.rect.center
        lcx, lcy = self.image.logical_center
        self.offset = cx + lcx, cy + lcy

    def update(self, fn, *args):
        getattr(self, fn)(*args)

    def move(self, (dx, dy)):
        self.rect = self.rect.move(dx, dy)
        return self.rect

    def move_to(self, pos):
        self.rect.topleft = pos
        return self.rect

    def rotate(self, angle):
        x, y = self.offset
        logical_centerx = self.rect.left + x
        logical_centery = self.rect.top + y
        print "pre-rotated rect", self.rect, "at heading", self.heading
        print "logical_centerx", logical_centerx, \
              "logical_centery", logical_centery

        self.heading += angle
        self.image = pygame.transform.rotate(self.base_image, -self.heading)
        self.rect = self.image.get_rect()
        ra = math.radians(self.heading)
        sin, cos = math.sin(ra), math.cos(ra)
        x, y = self.base_image.logical_center
        cx, cy = self.rect.center
        lcx = x * cos - y * sin
        lcy = y * cos + x * sin
        ox = cx + lcx
        oy = cy + lcy
        self.offset = ox, oy
        print "new self.offset", self.offset
        self.rect.left = logical_centerx - ox
        self.rect.top = logical_centery - oy
        print "rotated rect", self.rect, "at heading", self.heading


class robot_sprite(rotatable_sprite):
    def __init__(self, image):
        super(robot_sprite, self).__init__(robot_simulator.Robot, image)

        # desired position of image logical center
        x, y = robot_simulator.Robot.position

        # from image center to logical center
        lcx, lcy = self.base_image.logical_center

        # image center
        cx, cy = x - lcx, y - lcy

        rect = self.base_image.get_rect()
        assert rect.top == rect.left == 0

        self.move_to((cx - rect.centerx, cy - rect.centery))

Range_width, Range_distance = 20, 96

class range_finder_image(pygame.Surface):
    def __init__(self):
        super(range_finder_image, self).__init__((Range_width, Range_distance))
        self.set_colorkey(robot_simulator.White, pygame.RLEACCEL)
        self.fill(robot_simulator.Red)
        self.fill(robot_simulator.White,
                  (2, 2, Range_width - 4, Range_distance - 4))

        # from image center to logical center
        self.logical_center = 0, Range_distance/2

class robot(pygame.sprite.RenderUpdates):
    def __init__(self, posx, posy):
        super(robot, self).__init__()
        self.heading = 0.0
        self.heading_per_tick = 0.0
        self.direction = 0
        self.int_position = self.position = posx, posy

    def set_steering(self, rate):
        self.heading_per_tick = rate/10.0

    def set_direction(self, dir):
        self.direction = dir

    def tick(self):
        if self.direction:
            self.clear(robot_simulator.Screen, background.Background)
            ra = math.radians(self.heading)
            dx, dy = \
              self.direction * math.sin(ra), -self.direction * math.cos(ra)
            print "heading", self.heading, "dx", dx, "dy", dy
            ans = self.move_to((self.position[0] + dx, self.position[1] + dy))
            if self.heading_per_tick:
                self.rotate(self.heading_per_tick * self.direction)
            pygame.display.update(self.draw(robot_simulator.Screen))
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

    def move(self, delta):
        ans = None
        for s in self:
            r = s.move(delta)
            #print "move got", r, "from", s
            if ans is None: ans = r
            else: ans = ans.union(r)
        return ans

    def move_to(self, pos):
        self.position = pos
        curx, cury = self.int_position
        self.int_position = newx, newy = int(round(pos[0])), int(round(pos[1]))
        return self.move((newx - curx, newy - cury))

    def rotate(self, angle):
        self.heading += angle
        for s in self:
            s.rotate(angle)

