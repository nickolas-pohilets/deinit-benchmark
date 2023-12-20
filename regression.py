#!python3
import sys
import numpy as np
import math
import argparse

p = argparse.ArgumentParser()
p.add_argument('dataset')
p.add_argument('-p', '--params', default='vo2,vo,v,o2,o,1', help='Parameters for fit against. Comma-separated list of vo2,vo,v,o2,o,1')
p.add_argument('-y', '--phases', default='S,E,T', help='Values for fit against. Comma-separated list of S,E,T - Scheduling, Execution, Total')
p.add_argument('--min-values', type=int, default=0)
p.add_argument('--max-values', type=int, default=float('inf'))
p.add_argument('--min-objects', type=int, default=0)
p.add_argument('--max-objects', type=int, default=float('inf'))
args = p.parse_args()

data = []
with open(args.dataset, 'rt') as f:
    for line in f:
        if line.startswith('#'):
            continue
        nums = [int(x) for x in line.split('\t')]
        v = nums[0]
        o = nums[1]
        if args.min_values <= v <= args.max_values and args.min_objects <= o <= args.max_objects:
          data.append(nums)


def normalize(x):
    mx = np.max(x)
    mn = np.min(x)
    return x / (mx - mn)

params = {
    '1': ('', lambda v, o: np.ones(v.shape)),
    'o': ('⋅o', lambda v, o: o),
    'o2': ('⋅o²', lambda v, o: np.square(o)),
    'v': ('⋅v', lambda v, o: v),
    'vo': ('⋅v⋅o', lambda v, o: np.multiply(v, o)),
    'vo2': ('⋅v⋅o²', lambda v, o: np.multiply(v, np.square(o))),
}

data = np.array(data)
v = data[:, 0:1]
o = data[:, 1:2]
X = []
names = []
for arg in args.params.split(','):
    X.append(params[arg][1](v, o))
    names.append(params[arg][0])
X = np.concatenate(X, axis=1)
Z = np.linalg.inv(np.dot(X.T, X))

class Phase:
    def __init__(self, name, Y):
        self.name = name
        self.Y = Y
        self.beta = np.dot(Z, np.dot(X.T, Y))
        self.pY = np.dot(X, self.beta)
        self.eq = ' + '.join(f"{k}{n}" for k, n in zip(self.beta[:, 0], names))
        rss = np.sum(np.square(Y - self.pY))
        mean = np.mean(Y)
        sst = np.sum(np.square(Y - mean))
        self.r_square = 1 - (rss/sst)
        self.r_square_str = f'{self.r_square:.4f}'

        # Adjusted R²
        self.adjusted_r_square = 1 - ((rss/sst) * (len(Y) - 1)) / (len(Y) - len(names) - 1)
        self.adjusted_r_square_str = f'{self.r_square:.4f}'
        self.columns = [self.name, self.eq, self.r_square_str, self.adjusted_r_square_str]

YS = data[:, 2:3]
YT = data[:, 3:4]
phases = []
if 'S' in args.phases:
    phases.append(Phase('Scheduling', YS))
if 'E' in args.phases:
    phases.append(Phase('Execution', YT - YS))
if 'T' in args.phases:
    phases.append(Phase('Total', YT))


column_lengths = [0, 0, 0, 0]
for p in phases:
    for (i, s) in enumerate(p.columns):
        column_lengths[i] = max(column_lengths[i], len(s))

for p in phases:
    print(f'{p.name.ljust(column_lengths[0], " ")}: {p.eq.rjust(column_lengths[1], " ")}, R² = {p.r_square_str.rjust(column_lengths[2], " ")}, Adjusted R² = {p.r_square_str.rjust(column_lengths[3], " ")}')
