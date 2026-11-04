#!/usr/bin/env python3
"""把立绘四周的近白背景抠成透明，衬衫、口罩、毯子和枕头这种内部的白色留下。

只从图片四边开始漫水。贴着背景的发丝白边会一起去掉：阈值放宽到
连着背景的浅白像素，再把轮廓往里收大约 1 像素，最后把剩下的半透明边
按「原先叠在白底上」还原颜色，避免灰底上还留一圈白边。

用法：
    python3 tools/cutout_portraits.py 输入目录 输出目录
"""

from __future__ import annotations

import sys
from collections import deque
from pathlib import Path

from PIL import Image


def _chroma(r: int, g: int, b: int) -> int:
	return max(r, g, b) - min(r, g, b)


def _is_core_bg(r: int, g: int, b: int) -> bool:
	# 背景几乎是纯白。枕头高光偏暖，进不了这一档。
	return min(r, g, b) >= 246 and _chroma(r, g, b) <= 12


def _is_fringe_bg(r: int, g: int, b: int) -> bool:
	# 发丝之间、贴着白底的淡白抗锯齿。必须已经连着背景才会被收进来。
	return min(r, g, b) >= 226 and _chroma(r, g, b) <= 22


def _decontaminate(r: int, g: int, b: int, a: int) -> tuple[int, int, int, int]:
	"""半透明像素按叠在白底上还原前景色：c = (观测 - (1-a)*白) / a。"""
	if a <= 0:
		return (r, g, b, 0)
	if a >= 255:
		return (r, g, b, 255)
	af = a / 255.0
	out = []
	for c in (r, g, b):
		v = (c / 255.0 - (1.0 - af)) / af
		if v < 0.0:
			v = 0.0
		elif v > 1.0:
			v = 1.0
		out.append(int(round(v * 255.0)))
	return (out[0], out[1], out[2], a)


def cutout(src: Image.Image) -> Image.Image:
	im = src.convert("RGBA")
	w, h = im.size
	pix = im.load()
	bg = bytearray(w * h)
	q: deque[tuple[int, int]] = deque()

	def try_push(x: int, y: int, fringe: bool) -> None:
		if not (0 <= x < w and 0 <= y < h):
			return
		i = y * w + x
		if bg[i]:
			return
		r, g, b, _a = pix[x, y]
		if not (_is_core_bg(r, g, b) or (fringe and _is_fringe_bg(r, g, b))):
			return
		bg[i] = 1
		q.append((x, y))

	for x in range(w):
		try_push(x, 0, False)
		try_push(x, h - 1, False)
	for y in range(h):
		try_push(0, y, False)
		try_push(w - 1, y, False)

	# 8 邻域。纯白先铺开，贴着它的淡白发边再跟着进来。
	nbrs = ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1))
	while q:
		x, y = q.popleft()
		for dx, dy in nbrs:
			try_push(x + dx, y + dy, True)

	# 贴着背景再收两圈浅色。第一圈连淡金发边一起收，第二圈只收还接近纯白的残边。
	# 衬衫、口罩、毯子在身体里面，够不着。
	erode = bytearray(bg)
	for min_thr, chroma_thr in ((168, 42), (214, 28)):
		grown = bytearray(erode)
		for y in range(h):
			row = y * w
			for x in range(w):
				i = row + x
				if erode[i]:
					continue
				touch = False
				for dx, dy in nbrs:
					nx, ny = x + dx, y + dy
					if 0 <= nx < w and 0 <= ny < h and erode[ny * w + nx]:
						touch = True
						break
				if not touch:
					continue
				r, g, b, _a = pix[x, y]
				if min(r, g, b) >= min_thr and _chroma(r, g, b) <= chroma_thr:
					grown[i] = 1
		erode = grown
	edge: list[tuple[int, int]] = []
	for y in range(h):
		row = y * w
		for x in range(w):
			if erode[row + x]:
				continue
			for dx, dy in nbrs:
				nx, ny = x + dx, y + dy
				if 0 <= nx < w and 0 <= ny < h and erode[ny * w + nx]:
					edge.append((x, y))
					break

	for y in range(h):
		row = y * w
		for x in range(w):
			i = row + x
			r, g, b, _a = pix[x, y]
			if erode[i]:
				pix[x, y] = (r, g, b, 0)

	# 新的轮廓收成半透明，并去掉白底混进去的颜色。
	for x, y in edge:
		r, g, b, _a = pix[x, y]
		# 越接近白，越当成还混着背景。
		m = min(r, g, b)
		if m >= 210 and _chroma(r, g, b) <= 28:
			a = int((248 - m) * 255 / 50)
			a = 40 if a < 40 else 210 if a > 210 else a
			pix[x, y] = _decontaminate(r, g, b, a)
		else:
			pix[x, y] = _decontaminate(r, g, b, 232)
	return im


def main() -> None:
	if len(sys.argv) != 3:
		print("用法: python3 tools/cutout_portraits.py 输入目录 输出目录", file=sys.stderr)
		sys.exit(2)
	src_dir = Path(sys.argv[1])
	dst_dir = Path(sys.argv[2])
	dst_dir.mkdir(parents=True, exist_ok=True)
	files = sorted(p for p in src_dir.glob("*.png") if not p.name.startswith("."))
	if not files:
		print("输入目录里没有 png", file=sys.stderr)
		sys.exit(1)
	for path in files:
		out = cutout(Image.open(path))
		dest = dst_dir / path.name
		out.save(dest, "PNG")
		w, h = out.size
		transparent = 0
		for px in out.getdata():
			if px[3] == 0:
				transparent += 1
		print(f"{path.name}: {w}x{h} 透明 {transparent / (w * h):.1%}")


if __name__ == "__main__":
	main()
