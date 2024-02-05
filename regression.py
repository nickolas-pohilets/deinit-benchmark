#!python3
import sys
import numpy as np
import math
import argparse
import re

p = argparse.ArgumentParser(formatter_class=argparse.ArgumentDefaultsHelpFormatter)
p.add_argument('inputs')
p.add_argument('dataset')
p.add_argument('-d', '--diff', metavar='BASELINE', help='Apply regression to difference between dataset and baseline')
p.add_argument('-p', '--params', default='vo,v,o,1', help='Parameters for fit against. Comma-separated list of vo2,vo,v,o2,o,1')
p.add_argument('-y', '--phases', default='S,T', help='Values for fit against. Comma-separated list of S,T - Scheduling, Total')
p.add_argument('--min-values', type=int, default=0)
p.add_argument('--max-values', type=int, default=float('inf'))
p.add_argument('--min-objects', type=int, default=0)
p.add_argument('--max-objects', type=int, default=float('inf'))
args = p.parse_args()

def parse_data(file):
    data = []
    with open(file, 'rt') as f:
        for line in f:
            if line.startswith('#'):
                continue
            nums = [int(x) for x in line.split('\t')]
            data.append(nums)
    return np.array(data)

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

inputs = parse_data(args.inputs)
outputs = parse_data(args.dataset)
if args.diff:
    baseline = parse_data(args.diff)
    outputs -= baseline

v = inputs[:, 0:1]
o = inputs[:, 1:2]
indices = (v >= args.min_values) & (v <= args.max_values) & (o >= args.min_objects) & (o <= args.max_objects)
if indices.sum() < len(inputs):
    v = v[indices[:, 0]]
    o = o[indices[:, 0]]
    outputs = outputs[indices[:, 0]]

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
        self.eq = []
        for k, n in zip(self.beta[:, 0], names):
            if not self.eq:
                self.eq.append(f"{k:.0f}{n}")
            elif k < 0:
                self.eq.append(f" - {-k:.0f}{n}")
            else:
                self.eq.append(f" + {k:.0f}{n}")
        rss = np.sum(np.square(Y - self.pY))
        mean = np.mean(Y)
        sst = np.sum(np.square(Y - mean))
        self.r_square = 1 - (rss/sst)
        self.r_square_str = f'{self.r_square:.4f}'

        MSE = np.square(self.pY - Y).mean() 
        self.RMSE = math.sqrt(MSE)

        # Adjusted R²
        self.adjusted_r_square = 1 - ((rss/sst) * (len(Y) - 1)) / (len(Y) - len(names) - 1)
        self.adjusted_r_square_str = f'{self.adjusted_r_square:.4f}'
        self.columns = [self.name] + self.eq + [self.r_square_str, self.adjusted_r_square_str]

YS = outputs[:, 0:1]
YT = outputs[:, 1:2]
phase_names = args.phases.split(',')
phases = []
if 'S' in phase_names:
    phases.append(Phase('Scheduling', YS))
if 'T' in phase_names:
    phases.append(Phase('Total', YT))

column_lengths = [0] * (3 + X.shape[1])
for p in phases:
    for (i, s) in enumerate(p.columns):
        column_lengths[i] = max(column_lengths[i], len(s))

for p in phases:
    msg = f'{p.name.ljust(column_lengths[0], " ")}: '
    for i, term in enumerate(p.eq):
        msg += term.rjust(column_lengths[1+i], " ")
    msg += f', R² = {p.r_square_str.rjust(column_lengths[-2], " ")}, Adjusted R² = {p.adjusted_r_square_str.rjust(column_lengths[-1], " ")}'
    print(msg)
