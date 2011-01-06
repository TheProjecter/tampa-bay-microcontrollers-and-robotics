# make_image.py

from __future__ import division
import math
from PIL import Image, ImageDraw

# (0, 0) is upper left

# constants:
Step = 44       # must be an even number
Radius = 8*Step
Diameter = 2*Radius
Border = 10
Size = (2*(Radius + Border), 2*(Radius + Border))
Center = (Radius + Border, Radius + Border)

def create():
    # im.show() is interesting
    return Image.new('RGB', Size)

def write(im, filename="coordinate_map.png"):
    im.save(filename)

def add(pt1, pt2):
    r'''Adds two points.

        >>> add((1,2) (3,4))
        (4, 6)
    '''
    return pt1[0] + pt2[0], pt1[1] + pt2[1]

def sub(pt1, pt2):
    r'''Subtracts two points.

        >>> sub((4,3) (1,2))
        (3, 1)
    '''
    return pt1[0] - pt2[0], pt1[1] - pt2[1]

def draw_circle(draw, center, diameter, **options):
    radius = diameter // 2
    draw.ellipse([sub(center, (radius, radius)), add(center, (radius, radius))],
                 **options)

def draw_polar(draw):
    # draw = ImageDraw.Draw(im)
    #draw.arc(xy, start_angle, end_angle, outline=color)
    #draw.line(xy, fill=color, width=pixels)
    #draw.ellipse(xy, fill=color, outline=color)
    #draw.ellipse([(50, 50), (1650, 1650)], outline='black')
    for step in range(0, 50):
        angle = math.radians(step * 360 / 50)
        c, s = math.cos(angle), math.sin(angle)
        draw.line([Center, add(Center, (Radius*c, Radius*s))], fill='#202020')
        for offset in range(Step // 2, Radius, Step):
            center = add(Center, (c * offset, s * offset))
            draw_circle(draw, center, 10, fill='yellow')

def draw_rect(draw):
    #draw.line(xy, fill=color, width=pixels)
    def offset(step):
        return step * Step + Border + Step // 2
    for i in range(16):
        i_offset = offset(i)
        # draw vertical line
        draw.line([(i_offset, Border), (i_offset, Border + Diameter)],
                  fill='#202020')
        # draw horizontal line
        draw.line([(Border, i_offset), (Border + Diameter, i_offset)],
                  fill='#202020')
    for x in range(16):
        x_offset = offset(x) 
        for y in range(16):
            y_offset = offset(y) 
            draw_circle(draw, (x_offset, y_offset), 10, fill='green')

def run():
    im = create()
    draw = ImageDraw.Draw(im)
    draw_polar(draw)
    draw_rect(draw)
    im.show()
    write(im)

if __name__ == "__main__":
    run()
