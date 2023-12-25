#!python3
import numpy as np
import math
from matplotlib import pyplot as plt

def read_data(dataset):
    data = []
    with open(dataset, 'rt') as f:
        for line in f:
            if line.startswith('#'):
                continue
            nums = [int(x) for x in line.split('\t')]
            data.append(nums)
    data = np.array(data)

    params = data[:, 0:2]
    scheduling = data[:, 2:3] 
    total = data[:, 3:4] 
    execution = total - scheduling
    data = np.concatenate([params, scheduling, execution, total], axis=1)
    return data


for kind in ['tree', 'array']:
	x100 = read_data(f'data/async_{kind}-vs-values-100.txt')
	x1000 = read_data(f'data/async_{kind}-vs-values-1000.txt')
	x5000 = read_data(f'data/async_{kind}-vs-values-5000.txt')

	fig = plt.figure(figsize=(10,10))

	ax = fig.add_subplot(3, 1, 1)
	ax.set_title('Scheduling')
	ax.set_xlabel('# of task-local values')
	ax.set_ylabel('ns per object')
	ax.scatter(x100[:, 0], x100[:, 2] / 100, s=10, c='b', marker="s", label='x100')
	ax.scatter(x1000[:, 0], x1000[:, 2] / 1000, s=10, c='r', marker="o", label='x1000')
	ax.scatter(x5000[:, 0], x5000[:, 2] / 5000, s=10, c='g', marker="x", label='x5000')

	plt.legend(loc='upper center', ncols=3)

	ax = fig.add_subplot(3, 1, 2)
	ax.set_title('Execution')
	ax.set_xlabel('# of task-local values')
	ax.set_ylabel('ns per object')
	ax.scatter(x100[:, 0], x100[:, 3] / 100, s=10, c='b', marker="s", label='x100')
	ax.scatter(x1000[:, 0], x1000[:, 3] / 1000, s=10, c='r', marker="o", label='x1000')
	ax.scatter(x5000[:, 0], x5000[:, 3] / 5000, s=10, c='g', marker="x", label='x5000')


	ax = fig.add_subplot(3, 1, 3)
	ax.set_title('Total')
	ax.set_xlabel('# of task-local values')
	ax.set_ylabel('ns per object')
	ax.scatter(x100[:, 0], x100[:, 4] / 100, s=10, c='b', marker="s", label='x100')
	ax.scatter(x1000[:, 0], x1000[:, 4] / 1000, s=10, c='r', marker="o", label='x1000')
	ax.scatter(x5000[:, 0], x5000[:, 4] / 5000, s=10, c='g', marker="x", label='x5000')

	plt.tight_layout()

	plt.savefig(f'img/async-{kind}-vs-values.png')

