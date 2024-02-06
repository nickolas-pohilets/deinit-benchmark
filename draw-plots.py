#!python3
import numpy as np
import math
from matplotlib import pyplot as plt
from scipy.spatial import Delaunay

def read_data(dataset):
    data = []
    with open(dataset, 'rt') as f:
        for line in f:
            if line.startswith('#'):
                continue
            nums = [int(x) for x in line.split('\t')]
            data.append(nums)
    data = np.array(data)
    return data

def draw_isolated_copy():
    inputs = read_data(f'data/inputs-5K.txt')
    reset = read_data(f'data/isolated_hop_reset_array-b100-5K.txt')
    copy = read_data(f'data/isolated_hop_copy_array-b100-5K.txt')
    low_values = inputs[:, 0] < 50
    cost = (copy - reset) / inputs[:, 1:2]
    inputs = inputs[low_values]
    cost = cost[low_values]
    
    fig = plt.figure(figsize=(10,10))
    ax = fig.add_subplot(2, 1, 1)
    ax.scatter(inputs[:, 0], cost[:, 0], s=1, c='b', marker="o", alpha=0.5)
    ax.set_xlabel('Task-local values')
    ax.set_ylabel('Scheduling cost per object (ns)')
    plt.ylim(-100, 2000)
    plt.yticks(range(0, 2000, 100))
    ax.grid()
    
    ax = fig.add_subplot(2, 1, 2)
    ax.scatter(inputs[:, 0], cost[:, 1], s=1, c='r', marker="o", alpha=0.5)
    ax.set_xlabel('Task-local values')
    ax.set_ylabel('Execution cost per object (ns)')
    plt.ylim(-500, 2000)
    plt.yticks(range(-500, 2000, 100))
    ax.grid()
    
    fig.tight_layout()

    plt.savefig(f'img/isolated_copy_array.png')

def main():
    draw_isolated_copy()

if __name__ == '__main__':
    main()