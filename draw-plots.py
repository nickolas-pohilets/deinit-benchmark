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

    params = data[:, 0:2]
    scheduling = data[:, 2:3] 
    total = data[:, 3:4] 
    execution = total - scheduling
    data = np.concatenate([params, scheduling, execution, total], axis=1)
    return data


def draw_isolated_no_hop_copy():
	for kind in ['tree', 'array']:
		data = read_data(f'data/isolated_no_hop_copy_{kind}.txt')
		tri = Delaunay(data[:, 0:2] / [[200, 50000]])

		fig = plt.figure(figsize=(30,10))
		fig.suptitle(kind.capitalize())

		ax = fig.add_subplot(1, 3, 1)
		ax.set_title('Scheduling')
		ax.set_xlabel('# of task-local values')
		ax.set_ylabel('# of objects')
		cntr = ax.tricontourf(data[:, 0], data[:, 1], tri.simplices, data[:, 2], levels=21, vmin=0, vmax=1.2e6, cmap="tab20b")
		fig.colorbar(cntr, ax=ax, label='ns')
		plt.xticks(range(0, 200, 25)) 
		plt.yticks(range(0, 50000, 6250))
		plt.grid()

		ax = fig.add_subplot(1, 3, 2)
		ax.set_title('Execution')
		ax.set_xlabel('# of task-local values')
		ax.set_ylabel('# of objects')
		cntr = ax.tricontourf(data[:, 0], data[:, 1], tri.simplices, data[:, 3], levels=21, cmap="tab20b")
		fig.colorbar(cntr, ax=ax, label='ns')
		plt.xticks(range(0, 200, 25)) 
		plt.yticks(range(0, 50000, 6250))
		plt.grid()

		ax = fig.add_subplot(1, 3, 3)
		ax.set_title('Total')
		ax.set_xlabel('# of task-local values')
		ax.set_ylabel('# of objects')
		cntr = ax.tricontourf(data[:, 0], data[:, 1], tri.simplices, data[:, 4], levels=21, vmin=0, vmax=1.2e6, cmap="tab20b")
		fig.colorbar(cntr, ax=ax, label='ns')
		plt.xticks(range(0, 200, 25)) 
		plt.yticks(range(0, 50000, 6250))
		plt.grid()

		plt.savefig(f'img/isolated_no_hop_copy_{kind}.png')

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

		plt.savefig(f'img/async_{kind}-vs-values.png')


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

def draw_async_copy_tree():
	tree = read_data(f'data/async_copy_tree.txt')
	tri = Delaunay(tree[:, 0:2] / [[200, 50000]])

	fig = plt.figure(figsize=(20,10))

	ax = fig.add_subplot(1, 2, 1)
	ax.set_title('Scheduling')
	ax.set_xlabel('# of task-local values')
	ax.set_ylabel('# of objects')
	cntr = ax.tricontourf(tree[:, 0], tree[:, 1], tri.simplices, tree[:, 2], levels=21, cmap="tab20b")
	fig.colorbar(cntr, ax=ax, label='ns')
	plt.xticks(range(0, 200, 25)) 
	plt.yticks(range(0, 50000, 6250))
	plt.grid()

	ax = fig.add_subplot(1, 2, 2)
	ax.set_title('Total')
	ax.set_xlabel('# of task-local values')
	ax.set_ylabel('# of objects')
	cntr = ax.tricontourf(tree[:, 0], tree[:, 1], tri.simplices, tree[:, 4], levels=21, vmin=0, vmax=4e8, cmap="tab20b")
	fig.colorbar(cntr, ax=ax, label='ns')
	plt.xticks(range(0, 200, 25)) 
	plt.yticks(range(0, 50000, 6250))
	plt.grid()

	plt.savefig(f'img/async_copy_tree.png')

def draw_async_copy_array():
	array = read_data(f'data/async_copy_array.txt')
	tri = Delaunay(array[:, 0:2] / [[200, 50000]])

	fig = plt.figure(figsize=(30,10))

	ax = fig.add_subplot(1, 3, 1)
	ax.set_title('Scheduling')
	ax.set_xlabel('# of task-local values')
	ax.set_ylabel('# of objects')
	cntr = ax.tricontourf(array[:, 0], array[:, 1], tri.simplices, array[:, 2], levels=21, cmap="tab20b")
	fig.colorbar(cntr, ax=ax, label='ns')
	plt.xticks(range(0, 200, 25)) 
	plt.yticks(range(0, 50000, 6250))
	plt.grid()

	ax = fig.add_subplot(1, 3, 2)
	ax.set_title('Execution')
	ax.set_xlabel('# of task-local values')
	ax.set_ylabel('# of objects')
	cntr = ax.tricontourf(array[:, 0], array[:, 1], tri.simplices, array[:, 3], levels=21, cmap="tab20b")
	fig.colorbar(cntr, ax=ax, label='ns')
	plt.xticks(range(0, 200, 25)) 
	plt.yticks(range(0, 50000, 6250))
	plt.grid()

	ax = fig.add_subplot(1, 3, 3)
	ax.set_title('Total')
	ax.set_xlabel('# of task-local values')
	ax.set_ylabel('# of objects')
	cntr = ax.tricontourf(array[:, 0], array[:, 1], tri.simplices, array[:, 4], levels=21, vmin=0, vmax=4e8, cmap="tab20b")
	fig.colorbar(cntr, ax=ax, label='ns')
	plt.xticks(range(0, 200, 25)) 
	plt.yticks(range(0, 50000, 6250))
	plt.grid()

	plt.savefig(f'img/async_copy_array.png')


def main():
	draw_isolated_no_hop_copy()
	draw_async_vs_values()
	draw_async_vs_objects()
	draw_async_copy_tree()
	draw_async_copy_array()

if __name__ == '__main__':
	main()