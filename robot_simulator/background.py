# background.py

from __future__ import division

import pygame

import robot_simulator

class background(pygame.Surface):
    def __init__(self):
        super(background, self).__init__((robot_simulator.Width,
                                          robot_simulator.Height))
        self.fill(robot_simulator.White)

    def make_mask(self):
        width, height = self.get_size()
        self.mask = pygame.Mask((width, height))
        for x in range(width):
            for y in range(height):
                pos = x, y
                if self.get_at(pos) != robot_simulator.White:
                    self.mask.set_at(pos, 1)

    def collides_with(self, sprite):
        #return self.mask.overlap_area(sprite.mask, sprite.rect.topleft)
        return self.mask.overlap(sprite.mask, sprite.rect.topleft)
        #return sprite.mask.overlap(self.mask,
        #                           (-sprite.rect.left, -sprite.rect.top))

    def overlap_mask(self, sprite):
        return self.mask.overlap_mask(sprite.mask, sprite.rect.topleft)
        #return sprite.mask.overlap_mask(self.mask,
        #                                (-sprite.rect.left, -sprite.rect.top))

    def show_mask(self, mask, color = robot_simulator.Red):
        size = width, height = self.get_size()
        assert size == mask.get_size()
        for x in range(width):
            for y in range(height):
                pos = x, y
                if mask.get_at(pos):
                    robot_simulator.Screen.set_at(pos, color)
        pygame.display.update()

Background = background()

def obstacle(x, y, width, height):
    rect = pygame.Rect(x, y, width, height)
    image = pygame.Surface((width, height))
    image.fill(robot_simulator.Blue)
    Background.blit(image, rect)

