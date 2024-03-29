# __init__.py

from __future__ import division

# temp until event loop moved into robot
import sys
import time

import pygame

Size = Width, Height = 640, 480

White = pygame.Color(255, 255, 255)
Red = pygame.Color(255, 0, 0)
RedTransparent = pygame.Color(128, 0, 0, 128)
Green = pygame.Color(0, 255, 0)
Blue = pygame.Color(0, 0, 255)
LtBlue = pygame.Color(128, 128, 255)
Black = pygame.Color(0, 0, 0)

from robot_simulator import robot, background

Robot = robot.robot((Width + 150)//2 + 40, (Height + 200)//2 + 40)

Obstacles = pygame.sprite.Group()
Building = background.obstacle((Width - 150)//2, (Height - 200)//2, 150, 200)

# border -- to keep the car from leaving the screen...
background.obstacle(0, 0, 4, Height)
background.obstacle(Width - 4, 0, 4, Height)
background.obstacle(4, 0, Width - 8, 4)
background.obstacle(4, Height - 4, Width - 8, 4)

# Add obstacles here!

# Done adding obstacles...

def start():
    global Screen
    print "making Background mask"
    background.Background.make_mask()
    print "done making Background mask"
    Screen = pygame.display.set_mode(Size)
    Screen.blit(background.Background, (0, 0))
    #Robot.move_to(((Width + 150)//2 + 40, (Height + 200)//2 - 80))
    #Robot.rotate(180)
    Robot.draw(Screen)
    pygame.display.flip()
    return Robot

def run():
    robot = start()

    robot.set_rf(-5)
    robot.set_steering(-10.0)
    raw_input('waiting: ')
    print "went forward", robot.forward(200), "out of 200"
    print "range is", robot.get_range()

    #raw_input('waiting: ')
    #for i in xrange(100):
    #    robot.clear(Screen, background.Background)
    #    robot.rotate(1.8)
    #    pygame.display.update(robot.draw(Screen))

    #for i in range(36):
    #    raw_input('waiting: ')
    #    robot.forward(20.0)
    #    raw_input('waiting: ')
    #    robot.clear(Screen, background.Background)
    #    robot.rotate(10.0)
    #    pygame.display.update(robot.draw(Screen))

