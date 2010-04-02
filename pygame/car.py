# car.py

from __future__ import division

import sys
import time
import math
import pygame

Size = Width, Height = 640, 480
Speed = [1, 1]

White = pygame.Color(255, 255, 255)
Red = pygame.Color(255, 0, 0)
Green = pygame.Color(0, 255, 0)
Blue = pygame.Color(0, 0, 255)
LtBlue = pygame.Color(128, 128, 255)
Black = pygame.Color(0, 0, 0)

Car_body = (3, 2, 10, 20)

Car_components = (
    (Blue, Car_body),         # main body
    (Black, (0, 0, 3, 6)),    # lf wheel
    (Black, (13, 0, 3, 6)),   # rf wheel
    (Black, (0, 18, 3, 6)),   # lr wheel
    (Black, (13, 18, 3, 6)),  # rr wheel
)

class car_image(pygame.Surface):
    def __init__(self):
        super(car_image, self).__init__((16, 24))
        self.set_colorkey(White, pygame.RLEACCEL)
        self.fill(White)
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

    def rotate(self, angle):
        x, y = self.offset
        logical_centerx = self.rect.left + x
        logical_centery = self.rect.top + y
        print "pre-rotated rect", self.rect, "at heading", self.heading
        print "logical_centerx", logical_centerx, "logical_centery", logical_centery

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
        super(robot_sprite, self).__init__(Robot, image)

Range_width, Range_distance = 20, 96

class range_finder_image(pygame.Surface):
    def __init__(self):
        super(range_finder_image, self).__init__((Range_width, Range_distance))
        self.set_colorkey(White, pygame.RLEACCEL)
        self.fill(Red)
        self.fill(White, (2, 2, Range_width - 4, Range_distance - 4))

        # from image center to logical center
        self.logical_center = 0, Range_distance/2

class robot(pygame.sprite.RenderUpdates):
    def __init__(self):
        super(robot, self).__init__()

    def move(self, delta):
        ans = None
        for s in self:
            r = s.move(delta)
            #print "move got", r, "from", s
            if ans is None: ans = r
            else: ans = ans.union(r)
        return ans

Robot = robot()
Car = robot_sprite(car_image())
Car.update('rotate', 30.0)

class background(pygame.Surface):
    def __init__(self):
        super(background, self).__init__((Width, Height))
        self.fill(White)

        self.mask = pygame.Mask((Width, Height))
        for x in range(Width):
            for y in range(Height):
                self.mask.set_at((x, y), 0)

Background = background()

class obstacle(pygame.sprite.Sprite):
    def __init__(self, x, y, width, height):
        super(obstacle, self).__init__(Obstacles)
        self.rect = pygame.Rect(x, y, width, height)
        self.image = pygame.Surface((width, height))
        self.image.fill(Black)
        Background.blit(self.image, self.rect)
        self.mask = pygame.mask.from_surface(self.image)

Obstacles = pygame.sprite.Group()
Building = obstacle((Width - 150)//2, (Height - 200)//2, 150, 200)

def test():
    print "collide", pygame.sprite.collide_mask(Car, Building)
    Robot.move(((Width - 150)//2, (Height - 200)//2))
    print "collide", pygame.sprite.collide_mask(Car, Building)

def init():
    global Screen
    Screen = pygame.display.set_mode(Size)
    Screen.blit(Background, (0, 0))
    Robot.draw(Screen)
    pygame.display.flip()

    while 1:
        for event in pygame.event.get():
            if event.type == pygame.QUIT: sys.exit()

        Robot.clear(Screen, Background)
        loc_rect = Robot.move(Speed)
        if loc_rect.left < 0 or loc_rect.right > Width:
            Speed[0] = -Speed[0]
        if loc_rect.top < 0 or loc_rect.bottom > Height:
            Speed[1] = -Speed[1]

        #Screen.blit(ball, ballrect)
        pygame.display.update(Robot.draw(Screen))
        time.sleep(0.005)

