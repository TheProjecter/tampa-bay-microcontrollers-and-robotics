# commands.py

from __future__ import division
import sys
import time

Inches_per_sec2_for_1g = 385.28
G = 50  # for testing

def signed(char):
    r'''
        >>> signed(0x00)
        0
        >>> signed(0x01)
        1
        >>> signed(0x7F)
        127
        >>> signed(0xFF)
        -1
        >>> signed(0x80)
        -128
        >>> signed('\x00')
        0
        >>> signed('\x01')
        1
        >>> signed('\x7F')
        127
        >>> signed('\xFF')
        -1
        >>> signed('\x80')
        -128
    '''
    ans = ord(char) if isinstance(char, str) else char
    if ans < 128: return ans
    return ans - 256

def unsigned(signed):
    r'''
        >>> unsigned(0)
        0
        >>> unsigned(1)
        1
        >>> unsigned(127)
        127
        >>> unsigned(-1)
        255
        >>> unsigned(-128)
        128
        '''
    if signed >= 0: return signed
    return 256 + signed

def in_per_sec2(reading):
    r'''
        >>> def eq(a, b):
        ...     return abs(a - b) < 1e-6
        >>> G
        50
        >>> eq(Inches_per_sec2_for_1g, 385.28)
        True
        >>> foo = Inches_per_sec2_for_1g / G
        >>> in_per_sec2(0)
        0.0
        >>> eq(in_per_sec2(1), foo)
        True
        >>> eq(in_per_sec2(-1), -foo)
        True
        >>> eq(in_per_sec2(2), 2*foo)
        True
        >>> eq(in_per_sec2(-2), -2*foo)
        True
        >>> eq(in_per_sec2(50), Inches_per_sec2_for_1g)
        True
        >>> eq(in_per_sec2(-50), -Inches_per_sec2_for_1g)
        True
    '''
    return float(reading) / G * Inches_per_sec2_for_1g

def avg(histogram):
    r'''
        >>> avg([3,2,3])
        1.0
        >>> avg([0,2,0])
        1.0
        >>> avg([2,0,0])
        0.0
        >>> avg([0,0,2])
        2.0
        >>> avg([0] * 128 + [2])
        -128.0
        >>> avg([0] * 255 + [2])
        -1.0
    '''
    total_count = sum = 0
    for i, count in enumerate(histogram):
        total_count += count
        sum += signed(i) * count
    return sum / total_count

def command(desc):
    r''' Function decorator for command functions.

    Argument is description to come up in help listing, with command name
    substituted for %(name)s in string.
    '''
    def fn_dec(fn):
        global Commands
        fn.description = desc
        Commands[fn.__name__] = surrogate
        return fn
    return fn_dec

class streamers(object):
    read_len = 6
    arduino_command = 's'
    description = "%(name)s num_samples"
    def __init__(self, output, close_output, arduino, num_samples):
        self.output = output
        self.arduino = arduino
        self.num_samples = int(num_samples)
        self.close_output = close_output
        self.samples_seen = 0
        self.buffer = ''
        self.producer = None
        try:
            arduino.push_consumer(self)
            arduino.write("%s%d\n" % (self.arduino_command, self.num_samples))
            self.do_init()
        except Exception, e:
            #sys.stderr.write("streamers.__init__: caught %r exception\n" % e)
            if self.close_output: self.output.close()
            raise
    def listening_to(self, producer):
        assert self.producer is None
        self.producer = producer
    def not_listening_to(self, producer):
        assert self.producer == producer
        self.producer = None
    def do_init(self): pass
    def write(self, s):
        try:
            buf = self.buffer + s
            while len(buf) >= self.read_len:
                self.samples_seen += 1
                done = self.process(*(ord(x) for x in buf[:self.read_len]))
                buf = buf[self.read_len:]
                if done or self.samples_seen >= self.num_samples:
                    self.arduino.pop_consumer(self)
                    if buf:
                        self.output.write("Excess samples returned\n")
                    self.wrapup()
                    if self.close_output:
                        #sys.stderr.write("closing %s\n" % self.output.name)
                        self.output.close()
                    return
            self.buffer = buf
        except Exception, e:
            #sys.stderr.write("streamers.write: caught %r exception\n" % e)
            if self.close_output: self.output.close()
            raise
    def wrapup(self): pass

class histogram(streamers):
    def do_init(self):
        self.counts = [[0] * 256 for i in range(3)]
        self.num_overruns = 0
    def process(self, timeh, timel, status, *readings):
        for i, reading in enumerate(readings):
            self.counts[i][reading] += 1
        if self.samples_seen > 1 and status: self.num_overruns += 1
    def wrapup(self):
        for name, readings in zip(('x', 'y', 'z'), self.counts):
            self.output.write(name + ":\n")
            for i, count in enumerate(readings):
                if count:
                    self.output.write("  %d: %d\n" % (signed(i), count))
        self.output.write("%d: overruns\n" % self.num_overruns)

class calibrate(histogram):
    def wrapup(self):
        global Offsets, G
        Offsets = tuple(avg(counts_for_axis) for counts_for_axis in self.counts)
        G = float(Offsets[2])
        self.output.write(str(Offsets) + '\n')
        self.output.write("%d: overruns\n" % self.num_overruns)

class timestamps(streamers):
    def do_init(self):
        self.num_overruns = 0
        self.time_inc = 0
        self.do_init2()
    def do_init2(self): pass
    def process(self, timeh, timel, status, *readings):
        time = (timeh << 8 | timel) + self.time_inc;
        if self.samples_seen == 1: delta = 0
        else:
            if status: self.num_overruns += 1
            if time < self.last_time:
                self.time_inc += 65536
                time += 65536
            delta = time - self.last_time
        self.last_time = time
        if self.samples_seen > 1 and status: self.num_overruns += 1
        return self.process_time(time * 4e-6, delta * 4e-6, status, readings)
    def wrapup(self):
        self.output.write("%d: overruns\n" % self.num_overruns)

class track(timestamps):
    description = "%(name)s num_samples [max_adj]"
    def __init__(self, output, close_output, arduino, num_samples,
                       max_adj = '0'):
        super(track, self).__init__(output, close_output, arduino, num_samples)
        self.max_adj = float(max_adj)
    def do_init2(self):
        self.v = [0.0] * 3
        self.s = [0.0] * 3
        self.time_since_output = 0.0
    def process_time(self, time, delta, status, readings):
        self.time_since_output += delta
        if self.samples_seen > 1:
            dt = (self.last_delta + delta) / 2.0
            a = []
            adj = []
            for i, reading in enumerate(self.last_readings):
                a_n = in_per_sec2(signed(reading) - Offsets[i])
                a.append(a_n)
                adj_n = -self.max_adj if self.v[i] >= 0 else self.max_adj
                if abs(adj_n) * dt > abs(self.v[i]): adj_n = -self.v[i] / dt
                adj.append(adj_n)
                self.v[i] += (a_n + adj_n) * dt
                self.s[i] += (self.v[i] + adj_n * dt) * dt
            self.report(time, dt, a, adj)
        self.last_delta = delta
        self.last_readings = readings
    def report(self, time, dt, a, adj):
        if self.time_since_output >= 1.0:
            self.output.write("v(%f,%f,%f)\n" % tuple(self.v))
            self.output.write("s(%f,%f,%f)\n\n" % tuple(self.s))
            self.time_since_output = 0.0

class echo_track(track):
    def report(self, time, dt, a, adj):
        self.output.write("%f(%f)ms: " % (time, dt))
        self.output.write("a(%f,%f,%f) " % tuple(a))
        self.output.write("adj(%f,%f,%f) " % tuple(adj))
        self.output.write("v(%f,%f,%f) " % tuple(self.v))
        self.output.write("s(%f,%f,%f)\n" % tuple(self.s))
        self.time_since_output = 0.0

class echo(timestamps):
    def process_time(self, time, delta, status, readings):
        self.output.write("%f(%f)ms: 0x%x " % (time, delta, status))
        sep = '('
        for i, reading in enumerate(readings):
            self.output.write("%s%d" % (sep, signed(reading) - Offsets[i]))
            sep = ', '
        self.output.write(")\n")

class timings(streamers):
    read_len = 4
    arduino_command = 'T'
    def do_init(self):
        self.time_inc = 0
    def process(self, tcnthigh, tcntlow, int1, status):
        #self.output.write("timings: %r, %r, 0x%x, 0x%x\n" %
        #                   (tcnthigh, tcntlow, int1, status))
        if tcnthigh == tcntlow == int1 == status == 0:
            self.output.write("done\n")
            return True
        time = (tcnthigh << 8 | tcntlow) + self.time_inc;
        if self.samples_seen == 1: delta = 0
        else:
            if time < self.last_time:
                self.time_inc += 65536
                time += 65536
            delta = time - self.last_time
        self.last_time = time
        self.output.write("%f(%f)ms: %s 0x%x\n" %
                           (time * 4e-3, delta * 4e-3, bool(int1), status))
        return False

class help(object):
    description = "%(name)s"
    def __init__(self, output, close_output, arduino):
        output.write("Python commands:\n")
        for command_name in sorted(Commands.iterkeys()):
            cmd = Commands[command_name]
            output.write('  ' + cmd.description % {'name': cmd.__name__} + '\n')
        if close_output: output.close()

class audio(object):
    pulse_freq = 1/350
    #sample_rate = 1/2000
    sample_rate = 1/4000
    samples_per_pulse = pulse_freq / sample_rate
    description = "%(name)s f_v1 f_v2 f_r1 f_r2"
    def __init__(self, output, close_output, arduino, f_v1, f_v2, f_r1, f_r2):
        self.output = output
        self.arduino = arduino
        self.close_output = close_output
        self.f_v1 = float(f_v1)
        self.f_v2 = float(f_v2)
        self.f_r1 = float(f_r1)
        self.f_r2 = float(f_r2)
        try:
            arduino.write("p\n")
            self.run()
        except Exception, e:
            sys.stderr.write("audio.__init__: caught %r exception\n" % e)
            if self.close_output: self.output.close()
            raise
    def source(self, i):
        if i >= self.next_pulse:
            self.next_pulse += self.samples_per_pulse
            return 127
        return 0
    def run(self):
        source = self.source
        sample_rate = self.sample_rate
        now = time.time
        write = self.arduino.write
        sleep = time.sleep
        f_v1, f_v2, f_r1, f_r2 = self.f_v1, self.f_v2, self.f_r1, self.f_r2
        total = 0
        skipped = 0
        self.next_pulse = 0
        v1 = v2 = 0
        r1 = r2 = 0
        for i in xrange(int(2 / sample_rate)):
            t = i * sample_rate
            v0 = source(i)
            v = v0 + f_v1 * v1 + f_v2 * v2 + f_r1 * r1 + f_r2 * r2
            v1, v2 = v0, v1
            r1, r2 = v, r1
            if i:
                delay = start_time + t - now()
                #print "delay", delay
                if delay > 0: sleep(delay)
                else: skipped += 1
                total += 1
            else: start_time = now()
            c = v + 128
            if c < 0:
                print "underflow"
                c = 0
            if c > 255:
                print "overflow"
                c = 255
            write(chr(c))
        print "skipped", skipped, "out of", total

Commands = {
    'histogram': histogram,
    'calibrate': calibrate,
    'track': track,
    'timings': timings,
    'echo': echo,
    'echo_track': echo_track,
    'help': help,
    'audio': audio,
}

def test():
    import doctest
    doctest.testmod()

if __name__ == "__main__":
    test()

