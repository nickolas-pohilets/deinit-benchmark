#!python3
import sys
import argparse
import random

def parse_range(s):
    comps = s.split(':')
    if len(comps) != 2:
        raise ValueError()
    min_value = int(comps[0])
    max_value = int(comps[1])
    if min_value > max_value or min_value < 0:
        raise ValueError()
    return range(min_value, max_value + 1)

p = argparse.ArgumentParser(formatter_class=argparse.ArgumentDefaultsHelpFormatter)
p.add_argument('-v', '--values', type=parse_range, default='0:200', metavar='MIN:MAX', help='Range of number of task-local values')
p.add_argument('-o', '--objects', type=parse_range, default='1:5000', metavar='MIN:MAX', help='Range of number of objects')
p.add_argument('points', type=int, default=5000)
args = p.parse_args()

print('# ./gen-points.py ' + ' '.join(sys.argv[1:]))
print('#')
print('# values objects')
for _ in range(args.points):
    v = random.randrange(args.values.start, args.values.stop)
    o = random.randrange(args.objects.start, args.objects.stop)
    print(v, o, sep='\t')
