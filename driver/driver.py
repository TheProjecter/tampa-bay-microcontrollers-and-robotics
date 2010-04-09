# driver.py

import sys
import itertools
from pyke import knowledge_engine, krb_traceback

import robot_simulator

Engine = knowledge_engine.engine(__file__)

def run():
    global Robot

    Robot = robot_simulator.start()

    # Add the following universal facts:
    #
    #   layout.board(width, height)
    #   layout.building(left, top, right, bottom)
    #   layout.car(width, height)
    #   layout.car_logical_center(x_offset, y_offset)
    #   layout.range_finder(width, length)
    #   layout.safety_factor(safety_factor)
    #   layout.track(left, top, right, bottom)
    #   layout.direction(cc|ccw)

    Engine.add_universal_fact('layout', 'board',
                              (robot_simulator.Width, robot_simulator.Height))
    corners = left, top, right, bottom = \
             robot_simulator.Building.left, \
             robot_simulator.Building.top, \
             robot_simulator.Building.right, \
             robot_simulator.Building.bottom
    print "building corners", corners
    Engine.add_universal_fact('layout', 'building',
                              corners)
    Engine.add_universal_fact('layout', 'car',
                              Robot.car.rect[2:])
    Engine.add_universal_fact('layout', 'car_logical_center',
                              Robot.car.image.logical_center)
    Engine.add_universal_fact('layout', 'range_finder',
                              Robot.rf.rect[2:])
    safety_factor = max(Robot.car.rect.size) + 5
    Engine.add_universal_fact('layout', 'safety_factor',
                              (safety_factor,))
    track = (left - safety_factor,
             top - safety_factor,
             right + safety_factor,
             bottom + safety_factor)
    print "track", track
    Engine.add_universal_fact('layout', 'track', track)
    x, y = Robot.position
    heading = Robot.heading % 360
    if x <= left:
        direction = 'ccw' if 90 <= heading <= 270 else 'cw'
    elif x >= right:
        direction = 'cw' if 90 <= heading <= 270 else 'ccw'
    elif y <= top:
        direction = 'cw' if heading <= 180 else 'ccw'
    elif y >= bottom:
        direction = 'ccw' if heading <= 180 else 'cw'
    else:
        raise AssertionError("car starting inside building!")
    print "direction", direction
    Engine.add_universal_fact('layout', 'direction', (direction,))

    for step in itertools.count():
        x, y = Robot.position
        print "Robot position %d, %d" % Robot.position
        Engine.add_universal_fact('history', 'position', (step, x, y))
        print "Robot heading %d" % Robot.heading
        Engine.add_universal_fact('history', 'heading', (step, Robot.heading))
        Engine.reset()
        Engine.activate('rules')
        print "proving step", step
        try:
            vars, plan = Engine.prove_1_goal('rules.get_plan($step, $done)',
                                             step=step)
        except:
            krb_traceback.print_exc()
            sys.exit(1)
        if vars['done']:
            print "Success!"
            break
        ans = plan()
        print "plan done, Robot at (%d, %d)" % Robot.position
        Engine.add_universal_fact('history', 'result', (step, ans))

