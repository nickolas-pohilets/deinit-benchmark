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


def draw_async_vs_values():
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


def draw_async_vs_objects():
	tree = read_data(f'data/async_tree-vs-objects.txt')
	array = read_data(f'data/async_array-vs-objects.txt')

	fig = plt.figure(figsize=(10,10))

	ax = fig.add_subplot(2, 1, 1)
	ax.set_title('Total')
	ax.set_xlabel('# of objects')
	ax.set_ylabel('ns')
	ax.scatter(tree[:, 1], tree[:, 4], s=10, c='g', marker="s", label='tree')
	ax.scatter(array[:, 1], array[:, 4], s=10, c='r', marker="o", label='array')
	ax.legend(loc='upper center', ncols=2)

	ax = fig.add_subplot(2, 1, 2)
	ax.set_title('Total (nornalized)')
	ax.set_xlabel('# of objects')
	ax.set_ylabel('ns per object')
	ax.scatter(tree[:, 1], tree[:, 4] / tree[:, 1], s=10, c='g', marker="s", label='tree')
	ax.scatter(array[:, 1], array[:, 4] / array[:, 1], s=10, c='r', marker="o", label='array')
	ax.legend(loc='upper center', ncols=2)

	plt.tight_layout()

	plt.savefig(f'img/async-vs-objects.png')


def main():
	draw_async_vs_values()
	draw_async_vs_objects()

if __name__ == '__main__':
	main()