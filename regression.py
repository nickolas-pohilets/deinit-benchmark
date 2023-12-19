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
    'o': ('*o', lambda v, o: o),
    'o2': ('*o^2', lambda v, o: np.square(o)),
    'v': ('*v', lambda v, o: v),
    'vo': ('*v*o', lambda v, o: np.multiply(v, o)),
    'vo2': ('*v*o^2', lambda v, o: np.multiply(v, np.square(o))),
}

data = np.array(data)
v = data[:, 0:1]
o = data[:, 1:2]
X = []
names = []
for arg in args.params.split(','):
    X.append(params[arg][1](v, o))
    names.append(params[arg][0])
Y1 = data[:, 2:3]
Y2 = data[:, 3:4]
Y3 = Y2 - Y1
X = np.concatenate(X, axis=1)
Z = np.linalg.inv(np.dot(X.T, X))
beta1 = np.dot(Z, np.dot(X.T, Y1))
beta2 = np.dot(Z, np.dot(X.T, Y2))
beta3 = np.dot(Z, np.dot(X.T, Y3))
pY1 = np.dot(X, beta1)
pY2 = np.dot(X, beta2)
pY3 = np.dot(X, beta3)


def print_metrics(predictions, Y):

    #calculating mean absolute error
    MAE = np.abs(predictions - Y).mean()

    #calculating root mean square error
    MSE = np.square(predictions - Y).mean() 
    RMSE = math.sqrt(MSE)

    #calculating r_square
    rss = np.sum(np.square(Y - predictions))
    mean = np.mean(Y)
    sst = np.sum(np.square(Y - mean))
    r_square = 1 - (rss/sst)
    
    print(f"MAE={MAE}, RMSE={RMSE}, r_square={r_square}")


def print_eq(beta):
    print(' + '.join(f"{k}{n}" for k, n in zip(beta[:, 0], names)))

if 'S' in args.phases:
    print("= Scheduling:")
    print_eq(beta1)
    print_metrics(pY1, Y1)

if 'E' in args.phases:
    print("= Execution:")
    print_eq(beta3)
    print_metrics(pY3, Y3)

if 'T' in args.phases:
    print("= Total:")
    print_eq(beta2)
    print_metrics(pY2, Y2)

import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d import Axes3D

def plot_relative_error(Values, Predictions):
    fig = plt.figure()
    ax = fig.add_subplot(projection='3d')
    ax.scatter(v, o, np.minimum(np.maximum(100*(Values - Predictions) / Predictions, -100), +100))
    ax.set_xlabel('# values')
    ax.set_ylabel('# objects')
    ax.set_zlabel('relative error, %')

    def on_move(event):
        if event.inaxes == ax:
            ax.view_init(elev=event.ydata * 1000, azim=event.xdata * 1000)
            plt.draw()

    fig = ax.get_figure()
    fig.canvas.mpl_connect('motion_notify_event', on_move)


def plot_normalized(Values):
    fig = plt.figure()
    ax = fig.add_subplot(projection='3d')
    ax.scatter(v, o, Values / o / v)
    ax.set_xlabel('# values')
    ax.set_ylabel('# objects')
    ax.set_zlabel('ns')

    def on_move(event):
        if event.inaxes == ax:
            ax.view_init(elev=event.ydata * 1000, azim=event.xdata * 1000)
            plt.draw()

    fig = ax.get_figure()
    fig.canvas.mpl_connect('motion_notify_event', on_move)

def plot_normalized_per_object(Values):
    fig = plt.figure()
    ax = fig.add_subplot()
    ax.scatter(v, Values / o)
    ax.set_xlabel('# objects')
    ax.set_ylabel('ns')

def plot_normalized_per_value(Values):
    fig = plt.figure()
    ax = fig.add_subplot()
    ax.scatter(v, Values / o / v)
    ax.set_xlabel('# values')
    ax.set_ylabel('ns')

# plot_normalized(Y1)
# plot_normalized_per_object(Y1)
# plot_normalized_per_value(Y1)
# Underestimates for small objects (Y1 > pY1)
# Overestimates for small values (Y1 < pY1)


# fig = plt.figure()
# ax = fig.add_subplot()
# ax.scatter(o, Y1 / v)
# ax.set_xlabel('# objects')
# ax.set_ylabel('ns')

plt.show()