# __init__.py

from __future__ import division

# temp until event loop moved into robot
import sys
import time

import pygame

Size = Width, Height = 640, 480

White = pygame.Color(255, 255, 255)
Red = pygame.Color(255, 0, 0)
Green = pygame.Color(0, 255, 0)
Blue = pygame.Color(0, 0, 255)
LtBlue = pygame.Color(128, 128, 255)
Black = pygame.Color(0, 0, 0)

from robot_simulator import robot, background

Robot = robot.robot((Width + 150)//2 + 10, (Height + 200)//2 + 10)
Car = robot.robot_sprite(robot.car_image())
Range_finder = robot.robot_sprite(robot.range_finder_image())
#Car.update('rotate', 30.0)

Obstacles = pygame.sprite.Group()
Building = background.obstacle((Width - 150)//2, (Height - 200)//2, 150, 200)
print "making Background mask"
background.Background.make_mask()
print "done making Background mask"

def test():
    print "collide", pygame.sprite.collide_mask(Car, Building)
    Robot.move(((Width - 150)//2, (Height - 200)//2))
    print "collide", pygame.sprite.collide_mask(Car, Building)

def start():
    global Screen
    Screen = pygame.display.set_mode(Size)
    Screen.blit(background.Background, (0, 0))
    Robot.draw(Screen)
    pygame.display.flip()
    return Robot

def run():
    robot = start()
    #robot.set_steering(3.0)
    #robot.set_direction(1.0)

    #robot.forward(100)

