# car.py

import sys
import time
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
    (LtBlue, Car_body),       # main body
    (Black, (0, 0, 3, 6)),    # lf wheel
    (Black, (13, 0, 3, 6)),   # rf wheel
    (Black, (0, 18, 3, 6)),   # lr wheel
    (Black, (13, 18, 3, 6)),  # rr wheel
)

class car_image(pygame.Surface):
    def __init__(self):
        super(car_image, self).__init__((16, 24))
        self.fill(White)
        for color, rect in Car_components:
            self.fill(color, rect)

class rotatable_sprite(pygame.sprite.Sprite):
    def __init__(self, group):
        super(rotatable_sprite, self).__init__(group)

    def update(self, fn, *args):
        getattr(self, fn)(*args)

    def move(self, (dx, dy)):
        self.rect = self.rect.move(dx, dy)
        return self.rect


class car(rotatable_sprite):
    def __init__(self):
        super(car, self).__init__(Robot)
        self.image = car_image()
        self.rect = self.image.get_rect()
        #print 'car rect', self.rect

Range_width, Range_distance = 20, 96

class range_finder_image(pygame.Surface):
    def __init__(self):
        super(range_finder_image, self).__init__((Range_width, Range_distance))
        self.set_colorkey(White, pygame.RLEACCEL)
        self.fill(Red)
        self.fill(White, (2, 2, Range_width - 4, Range_distance - 4))

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
car()

class background(pygame.Surface):
    def __init__(self):
        super(background, self).__init__((Width, Height))
        self.fill(White)

Background = background()

class obstacle(pygame.Surface):
    def __init__(self, x, y, width, height):
        super(obstacle, self).__init__((width, height))
        self.fill(Black)
        self.rect = pygame.Rect(x, y, width, height)
        Background.blit(self, self.rect)

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

