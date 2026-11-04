#!/usr/bin/env python3
"""把立绘四周的近白背景抠成透明，衬衫、口罩、毯子和枕头这种内部的白色留下。

只从图片四边开始漫水，够不到被轮廓围住的浅色。边缘 1–2 像素里偏白的抗锯齿
会收成半透明，避免贴到蓝底上出现白边。

用法：
    python3 tools/cutout_portraits.py 输入目录 输出目录
默认读仓库旁的解压目录不合适，两个参数都要给。
"""

from __future__ import annotations

import sys
from collections import deque
from pathlib import Path

from PIL import Image


def is_background(r: int, g: int, b: int) -> bool:
	# 背景几乎是纯白（实测 252–255）。枕头高光偏暖，蓝色通道更低，不会被算进去。
	return r >= 250 and g >= 250 and b >= 250 and (max(r, g, b) - min(r, g, b)) <= 8


def cutout(src: Image.Image) -> Image.Image:
	im = src.convert("RGBA")
	w, h = im.size
	pix = im.load()
	bg = bytearray(w * h)
	q: deque[tuple[int, int]] = deque()

	def push(x: int, y: int) -> None:
		i = y * w + x
		if bg[i]:
			return
		r, g, b, _a = pix[x, y]
		if not is_background(r, g, b):
			return
		bg[i] = 1
		q.append((x, y))

	for x in range(w):
		push(x, 0)
		push(x, h - 1)
	for y in range(h):
		push(0, y)
		push(w - 1, y)

	while q:
		x, y = q.popleft()
		for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
			if 0 <= nx < w and 0 <= ny < h:
				push(nx, ny)

	# 到背景的切比雪夫距离，只算到 2，用来收软边。
	dist = bytearray(w * h)
	fringe: deque[tuple[int, int]] = deque()
	for y in range(h):
		row = y * w
		for x in range(w):
			if bg[row + x]:
				dist[row + x] = 0
				fringe.append((x, y))
			else:
				dist[row + x] = 3
	while fringe:
		x, y = fringe.popleft()
		base = dist[y * w + x]
		if base >= 2:
			continue
		nd = base + 1
		for ny in range(max(0, y - 1), min(h, y + 2)):
			for nx in range(max(0, x - 1), min(w, x + 2)):
				i = ny * w + nx
				if dist[i] > nd:
					dist[i] = nd
					fringe.append((nx, ny))

	for y in range(h):
		row = y * w
		for x in range(w):
			i = row + x
			r, g, b, a = pix[x, y]
			if bg[i]:
				pix[x, y] = (r, g, b, 0)
				continue
			d = dist[i]
			if d <= 2 and min(r, g, b) >= 206:
				# 越接近纯白越透明，深色头发贴着背景仍然不透明。
				fade = int((min(r, g, b) - 206) * 255 / 49)
				fade = 0 if fade < 0 else 255 if fade > 255 else fade
				# 距离 2 的那一圈少削一点，避免边发虚。
				if d == 2:
					fade = fade // 2
				pix[x, y] = (r, g, b, 255 - fade)
			else:
				pix[x, y] = (r, g, b, 255 if a == 0 else a)
	return im


def main() -> None:
	if len(sys.argv) != 3:
		print("用法: python3 tools/cutout_portraits.py 输入目录 输出目录", file=sys.stderr)
		sys.exit(2)
	src_dir = Path(sys.argv[1])
	dst_dir = Path(sys.argv[2])
	dst_dir.mkdir(parents=True, exist_ok=True)
	files = sorted(src_dir.glob("*.png"))
	if not files:
		print("输入目录里没有 png", file=sys.stderr)
		sys.exit(1)
	for path in files:
		out = cutout(Image.open(path))
		dest = dst_dir / path.name
		out.save(dest, "PNG")
		w, h = out.size
		transparent = sum(1 for px in out.getdata() if px[3] == 0)
		print(f"{path.name}: {w}x{h} 透明 {transparent / (w * h):.1%}")


if __name__ == "__main__":
	main()
