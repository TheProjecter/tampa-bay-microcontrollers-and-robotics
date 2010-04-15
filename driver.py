# driver.py

import math
import sys
import itertools

if __name__ == "__main__":
    import doctest
    sys.exit(doctest.testmod()[0])
else:
    from pyke import knowledge_engine, krb_traceback
    import robot_simulator
    Engine = knowledge_engine.engine(__file__)

def run():
    global Robot, Building_center

    Robot = robot_simulator.start()

    # Add the following universal facts:
    #
    #   layout.board(width, height)
    #   layout.building(left, top, right, bottom)
    #   layout.building_center(x, y)
    #   layout.car(width, height)
    #   layout.car_logical_center(x_offset, y_offset)
    #   layout.range_finder(width, length)
    #   layout.safety_factor(safety_factor)
    #   layout.track(left, top, right, bottom)
    #   layout.direction(cc|ccw)
    #   layout.waypoint(x, y)

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
    Building_center = robot_simulator.Building.center
    Engine.add_universal_fact('layout', 'building_center',
                              Building_center)
    Engine.add_universal_fact('layout', 'car',
                              Robot.car.rect[2:])
    Engine.add_universal_fact('layout', 'car_logical_center',
                              Robot.car.base_image.logical_center)
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
    initial_direction = direction(Robot.heading)
    print "initial_direction", initial_direction
    Engine.add_universal_fact('layout', 'direction', (initial_direction,))
    Engine.add_universal_fact('layout', 'waypoint', (track[0], track[1]))
    Engine.add_universal_fact('layout', 'waypoint', (track[0], track[3]))
    Engine.add_universal_fact('layout', 'waypoint', (track[2], track[1]))
    Engine.add_universal_fact('layout', 'waypoint', (track[2], track[3]))
    Engine.add_universal_fact('layout', 'waypoint', Robot.position)

    for step in itertools.count():
        x, y = Robot.position
        print "Robot position %d, %d" % Robot.position
        Engine.add_universal_fact('history', 'position', (step, x, y))
        print "Robot heading %d" % Robot.heading
        Engine.add_universal_fact('history', 'heading', (step, Robot.heading))
        Engine.add_universal_fact('history', 'car_radial',
                                  (step,
                                   heading(Building_center, Robot.position)))
        Engine.reset()
        Engine.activate('rules')
        print "proving step", step
        try:
            vars, _ = Engine.prove_1_goal('rules.get_plan($step, $plan)',
                                          step=step)
        except:
            krb_traceback.print_exc()
            sys.exit(1)
        plan = vars['plan']
        if plan is None:
            print "Success!"
            break
        ans = plan()
        print "plan done, Robot at (%d, %d)" % Robot.position
        Engine.add_universal_fact('history', 'result', (step, ans))

def heading(from_pos, to_pos):
    r'''Returns heading in degrees from from_pos to to_pos.

    heading is an int between 0 and 359, with 0 up.

        >>> heading((100, 100), (100, 50))
        0
        >>> heading((100, 100), (100, 150))
        180
        >>> heading((100, 100), (50, 100))
        270
        >>> heading((100, 100), (150, 100))
        90
    '''
    fx, fy = from_pos
    tx, ty = to_pos
    return int(round(math.degrees(math.atan2(tx - fx, fy - ty)) % 360))

def direction(car_heading):
    car_radial = heading(Building_center, Robot.position)
    if (car_radial - car_heading) % 360 <= 180:
        return 'ccw'
    return 'cw'

def distance(from_pos, to_pos):
    fx, fy = from_pos
    tx, ty = to_pos
    return math.hypot(tx - fx, ty - fy)
