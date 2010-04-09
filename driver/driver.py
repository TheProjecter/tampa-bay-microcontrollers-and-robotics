# driver.py

import itertools
from pyke import knowledge_engine

import robot_simulator

Engine = knowledge_engine.engine(__file__)

def run():
    global Robot

    Robot = robot_simulator.start()

    # Add the following universal facts:
    #
    #   layout.board(width, height)
    #   layout.building(left, top, width, height)
    #   layout.car(width, height)
    #   layout.car_logical_center(x_offset, y_offset)
    #   layout.range_finder(width, length)
    #   layout.safety_factor(safety_factor)
    #   layout.track(left, top, right, bottom)

    Engine.add_universal_fact('layout', 'board',
                              (robot_simulator.Width, robot_simulator.Height))
    Engine.add_universal_fact('layout', 'building',
                              robot_simulator.Building.get_rect())
    Engine.add_universal_fact('layout', 'car',
                              Robot.car.get_rect()[2:])
    Engine.add_universal_fact('layout', 'car_logical_center',
                              Robot.car.logical_center())
    Engine.add_universal_fact('layout', 'range_finder',
                              Robot.rf.get_rect()[2:])
    safety_factor = max(Robot.car.get_rect().size) + 5
    Engine.add_universal_fact('layout', 'safety_factor',
                              (safety_factor,))
    Engine.add_universal_fact('layout', 'track',
      (robot_simulator.Building.get_rect().left - safety_factor,
       robot_simulator.Building.get_rect().top - safety_factor,
       robot_simulator.Building.get_rect().right + safety_factor,
       robot_simulator.Building.get_rect().bottom + safety_factor,
    ))

    for step in itertools.count():
        x, y = Robot.position
        Engine.add_universal_fact('history', 'position', (step, x, y))
        Engine.add_universal_fact('history', 'heading', (step, Robot.heading))
        Engine.reset()
        Engine.activate('rules')
        vars, plan = Engine.prove_1_goal('rules.get_plan($step, $done)',
                                         step=step)
        if vars['done']:
            print "Success!"
            break
        Engine.add_universal_fact('history', 'result', (step, plan()))

