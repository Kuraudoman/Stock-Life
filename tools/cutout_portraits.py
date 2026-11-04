#!/usr/bin/env python3
"""把立绘白底抠成透明，并清掉发丝线稿围住的近白背景。

边缘漫水够不到这些封闭的白块（外圈有一圈细棕色线）。这里先用 rembg 的
isnet-anime 得到人物轮廓，再丢掉「邻居主要是头发或透明、又不贴着皮肤 /
制服 / 大块白布」的近白连通块。衬衫、袖口、领口、口罩、毯子、枕头、病号服
贴着皮肤或蓝布，会留下来。离人物较远的火花和头晕云纹，用原来的边缘漫水
把它们从白底里捡回来。

依赖：pip install "rembg[cpu]" scipy

用法：
    python3 tools/cutout_portraits.py 输入目录 输出目录
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage


def _clean_edges(orig: np.ndarray, alpha: np.ndarray, protect: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
	"""清掉贴着轮廓的淡白半透明边。有颜色的发丝保持原色，不做白底反解。"""
	r = orig[:, :, 0].astype(np.float32)
	g = orig[:, :, 1].astype(np.float32)
	b = orig[:, :, 2].astype(np.float32)
	mx = np.maximum(np.maximum(r, g), b)
	mn = np.minimum(np.minimum(r, g), b)
	sat = (mx - mn) / np.maximum(mx, 1.0)
	lum = (r + g + b) / 3.0
	pale = (lum >= 198.0) & (sat <= 0.12)
	alpha = alpha.copy()
	kill = pale & (alpha > 0) & (alpha < 235) & ~protect
	alpha[kill] = 0
	# 再收一圈已经贴着透明区的淡白，衬衫和口罩在 protect 里。
	touch = ndimage.binary_dilation(alpha == 0, iterations=1) & pale & (alpha > 0) & ~protect
	alpha[touch] = 0
	rgb = orig.copy()
	rgb[alpha == 0] = 0
	return rgb, alpha


def _edge_flood_foreground(orig: np.ndarray) -> np.ndarray:
	"""从四边漫过近白，得到「旧方法会留下」的前景。用来捡火花和云纹。"""
	r = orig[:, :, 0].astype(np.int16)
	g = orig[:, :, 1].astype(np.int16)
	b = orig[:, :, 2].astype(np.int16)
	mx = np.maximum(np.maximum(r, g), b)
	mn = np.minimum(np.minimum(r, g), b)
	bg = (mn >= 246) & ((mx - mn) <= 12)
	# 贴着画面边缘的近白是背景。线稿围住的白块和有颜色的火花不在这里。
	structure = np.ones((3, 3), bool)
	lab, _n = ndimage.label(bg, structure=structure)
	edge_ids = np.unique(np.concatenate([lab[0, :], lab[-1, :], lab[:, 0], lab[:, -1]]))
	edge_ids = edge_ids[edge_ids != 0]
	reached = np.isin(lab, edge_ids)
	return ~reached


def _drop_enclosed_white(orig: np.ndarray, alpha: np.ndarray) -> np.ndarray:
	"""去掉发丝之间、线稿围住的近白背景。返回要变成透明的蒙版。"""
	r = orig[:, :, 0].astype(np.float32)
	g = orig[:, :, 1].astype(np.float32)
	b = orig[:, :, 2].astype(np.float32)
	mx = np.maximum(np.maximum(r, g), b)
	mn = np.minimum(np.minimum(r, g), b)
	sat = (mx - mn) / np.maximum(mx, 1.0)
	lum = (r + g + b) / 3.0

	cand = (lum >= 178.0) & (sat <= 0.105) & (mx >= 170.0) & (alpha > 18)
	skin_raw = (
		(r > 175.0) & (b > 145.0) & ((r - g) > 22.0) & ((g - b) < 22.0) & ((r - b) > 28.0)
		& (sat > 0.14) & (sat < 0.45) & (lum > 160.0) & (lum < 242.0) & ~cand
	)
	slab, sn = ndimage.label(skin_raw)
	skin = np.zeros(cand.shape, bool)
	if sn:
		sizes = ndimage.sum(skin_raw, slab, range(1, sn + 1))
		for i, sz in enumerate(sizes, start=1):
			if sz >= 140:
				skin[slab == i] = True
	hair = (
		(r > 80.0) & (g > 48.0) & (b > 15.0)
		& (g > b + 14.0) & (r + 36.0 >= g) & ((r - b) > 22.0)
		& (sat > 0.09) & (sat < 0.80)
		& (lum > 32.0) & (lum < 250.0) & ~cand & ~skin
	)
	blue = (
		(b > r + 6.0) & (b + 8.0 >= g) & (sat > 0.09) & (lum > 12.0) & (lum < 230.0)
		& ~cand & ~skin
	)

	lab, n = ndimage.label(cand)
	drop = np.zeros(cand.shape, bool)
	for i in range(1, n + 1):
		comp = lab == i
		cc = int(comp.sum())
		if cc < 12:
			continue
		ring = ndimage.binary_dilation(comp, iterations=2) & ~comp
		hair_n = int((ring & hair).sum())
		skin_n = int((ring & skin).sum())
		blue_n = int((ring & blue).sum())
		trans_n = int((ring & (alpha <= 18)).sum())
		other_n = int(ring.sum()) - hair_n - skin_n - blue_n - trans_n
		if other_n < 0:
			other_n = 0
		touches_skin = skin_n > 25
		# 贴着制服的衬衫、袖口。发缝两边都是头发，蓝布接触比头发少。
		body_cloth = blue_n > 80 and blue_n > hair_n * 1.15 and cc > 120
		# 枕头、毯子、病号服：大块浅色，皮肤或蓝布比头发多。
		big_prop = cc > 2500 and (blue_n + skin_n) > hair_n
		kill = (
			(not touches_skin) and (not body_cloth) and (not big_prop)
			and hair_n > 20 and hair_n > blue_n * 1.05 and hair_n > other_n * 0.7
			and cc < 16000
		)
		if kill:
			drop[comp] = True

	# 线稿最多大约 3 像素。只往头发那边扩，不吃领口和徽章上的高光。
	hair_dist = ndimage.distance_transform_edt(~hair)
	near = ndimage.binary_dilation(drop, iterations=3) & cand & ~drop
	near &= ~ndimage.binary_dilation(skin, iterations=2)
	near &= ~ndimage.binary_dilation(blue, iterations=1)
	near &= hair_dist <= 8.0
	drop |= near
	# 只保护贴着皮肤或蓝布的浅色（衬衫、袖口、口罩、枕头）。
	# 发丝边上没被主规则丢掉的淡白不在里面。
	kept = cand & ~drop
	cloth = ndimage.binary_dilation(skin | blue, iterations=3)
	protect = ndimage.binary_dilation((kept & cloth) | skin | blue, iterations=1)
	return drop, protect


def _restore_detached(orig: np.ndarray, alpha: np.ndarray) -> np.ndarray:
	"""捡回离身体远的火花、头晕云纹。发缝里的白块离头发近，不会进来。"""
	kept = _edge_flood_foreground(orig)
	fg = alpha > 40
	dist = ndimage.distance_transform_edt(~fg)
	take = kept & (alpha < 12) & (dist > 16.0)
	lab, n = ndimage.label(take)
	keep = np.zeros(take.shape, bool)
	if n:
		sizes = ndimage.sum(take, lab, range(1, n + 1))
		for i, sz in enumerate(sizes, start=1):
			if not (8 <= sz <= 2500):
				continue
			ys, xs = np.where(lab == i)
			if (xs.max() - xs.min()) < 180 and (ys.max() - ys.min()) < 180:
				keep[lab == i] = True
	return keep


def cutout(src: Image.Image, session) -> Image.Image:
	from rembg import remove

	rgb_im = src.convert("RGB")
	orig = np.array(rgb_im)
	matted = remove(rgb_im, session=session)
	rgba = np.array(matted.convert("RGBA"))
	alpha = rgba[:, :, 3].copy()
	drop, protect = _drop_enclosed_white(orig, alpha)
	alpha = alpha.copy()
	alpha[drop] = 0
	rgb, alpha = _clean_edges(orig, alpha, protect)
	restore = _restore_detached(orig, alpha)
	out = np.zeros((*orig.shape[:2], 4), np.uint8)
	out[:, :, :3] = rgb
	out[:, :, 3] = alpha
	out[restore, :3] = orig[restore]
	out[restore, 3] = 255
	out[out[:, :, 3] == 0, :3] = 0
	return Image.fromarray(out, "RGBA")


def main() -> None:
	if len(sys.argv) != 3:
		print("用法: python3 tools/cutout_portraits.py 输入目录 输出目录", file=sys.stderr)
		sys.exit(2)
	try:
		from rembg import new_session
	except ImportError:
		print("需要 rembg：pip install \"rembg[cpu]\"", file=sys.stderr)
		sys.exit(1)
	src_dir = Path(sys.argv[1])
	dst_dir = Path(sys.argv[2])
	dst_dir.mkdir(parents=True, exist_ok=True)
	files = sorted(p for p in src_dir.glob("*.png") if not p.name.startswith("."))
	if not files:
		print("输入目录里没有 png", file=sys.stderr)
		sys.exit(1)
	session = new_session("isnet-anime")
	for path in files:
		out = cutout(Image.open(path), session)
		dest = dst_dir / path.name
		out.save(dest, "PNG")
		arr = np.array(out)
		transparent = int((arr[:, :, 3] == 0).sum())
		print(f"{path.name}: {out.size[0]}x{out.size[1]} 透明 {transparent / arr[:, :, 3].size:.1%}")


if __name__ == "__main__":
	main()
