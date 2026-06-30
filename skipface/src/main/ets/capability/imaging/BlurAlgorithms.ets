/**
 * BlurAlgorithms.ets
 * 分层：capability / 图像处理（纯像素算法）
 *
 * 职责：在 RGBA8888 像素缓冲上实现三种遮挡效果，均为纯函数(输入缓冲→输出新缓冲)，
 *       不依赖任何画布/UI API，可单测、可在预览与导出两条路径复用。
 *   - gaussianBlur：三次盒状模糊近似高斯(可分离，O(n))；
 *   - pixelate    ：按单元取平均色铺块(马赛克)；
 *   - halftone    ：平均色块底 + 按亮度的网点(六边形错位)。
 *
 * 缓冲约定：Uint8Array，长度 = width*height*4，逐像素 [R,G,B,A]，行无额外对齐。
 */
export class BlurAlgorithms {
  /**
   * 自适应"单元尺寸/模糊半径"：混合"全局尺寸"与"区域尺寸"，区域权重更高。
   * @param regionW/regionH 区域(代理图)宽高。
   * @param imgW/imgH       整图宽高。
   * @param divisor         全局尺寸除数(越大→越精细)。
   * @param cells           区域期望被切成的单元数。
   * @param regionWeight    区域占比(0~1)，默认 0.8。
   */
  static adaptiveCellSize(
    regionW: number, regionH: number,
    imgW: number, imgH: number,
    divisor: number, cells: number, regionWeight: number = 0.8
  ): number {
    const globalSize: number = Math.floor(Math.max(imgW, imgH) / divisor);
    const regionSize: number = Math.max(regionW, regionH);
    const regionCell: number = Math.floor(regionSize / cells);
    const hybrid: number = Math.floor(regionCell * regionWeight + globalSize * (1 - regionWeight));
    return Math.max(1, hybrid);
  }

  /**
   * 高斯模糊(三次盒状模糊近似)。返回新缓冲。
   * @param radius 模糊半径(像素)，<=0 时原样返回拷贝。
   */
  static gaussianBlur(src: Uint8Array, width: number, height: number, radius: number): Uint8Array {
    const out: Uint8Array = src.slice();
    if (radius <= 0 || width <= 0 || height <= 0) {
      return out;
    }
    // 盒状半径：三次盒模糊 ≈ 高斯，半径取 radius 的 1/3 较接近。
    const boxR: number = Math.max(1, Math.round(radius / 3));
    for (let pass: number = 0; pass < 3; pass++) {
      BlurAlgorithms.boxBlurHorizontal(out, width, height, boxR);
      BlurAlgorithms.boxBlurVertical(out, width, height, boxR);
    }
    return out;
  }

  /** 水平方向滑动窗口盒模糊(就地)。 */
  private static boxBlurHorizontal(buf: Uint8Array, width: number, height: number, r: number): void {
    const win: number = r * 2 + 1;
    const row: Uint8Array = new Uint8Array(width * 4);
    for (let y: number = 0; y < height; y++) {
      const base: number = y * width * 4;
      row.set(buf.subarray(base, base + width * 4));
      let sr: number = 0;
      let sg: number = 0;
      let sb: number = 0;
      let sa: number = 0;
      // 初始化窗口 [-r, r]，越界用边缘像素(clamp)。
      for (let k: number = -r; k <= r; k++) {
        const xi: number = Math.min(width - 1, Math.max(0, k));
        const p: number = xi * 4;
        sr += row[p];
        sg += row[p + 1];
        sb += row[p + 2];
        sa += row[p + 3];
      }
      for (let x: number = 0; x < width; x++) {
        const o: number = base + x * 4;
        buf[o] = Math.round(sr / win);
        buf[o + 1] = Math.round(sg / win);
        buf[o + 2] = Math.round(sb / win);
        buf[o + 3] = Math.round(sa / win);
        // 滑窗：移出 x-r，移入 x+r+1。
        const outX: number = Math.min(width - 1, Math.max(0, x - r));
        const inX: number = Math.min(width - 1, Math.max(0, x + r + 1));
        const po: number = outX * 4;
        const pi: number = inX * 4;
        sr += row[pi] - row[po];
        sg += row[pi + 1] - row[po + 1];
        sb += row[pi + 2] - row[po + 2];
        sa += row[pi + 3] - row[po + 3];
      }
    }
  }

  /** 垂直方向滑动窗口盒模糊(就地)。 */
  private static boxBlurVertical(buf: Uint8Array, width: number, height: number, r: number): void {
    const win: number = r * 2 + 1;
    const col: Uint8Array = new Uint8Array(height * 4);
    for (let x: number = 0; x < width; x++) {
      // 取出该列。
      for (let y: number = 0; y < height; y++) {
        const src: number = (y * width + x) * 4;
        const d: number = y * 4;
        col[d] = buf[src];
        col[d + 1] = buf[src + 1];
        col[d + 2] = buf[src + 2];
        col[d + 3] = buf[src + 3];
      }
      let sr: number = 0;
      let sg: number = 0;
      let sb: number = 0;
      let sa: number = 0;
      for (let k: number = -r; k <= r; k++) {
        const yi: number = Math.min(height - 1, Math.max(0, k));
        const p: number = yi * 4;
        sr += col[p];
        sg += col[p + 1];
        sb += col[p + 2];
        sa += col[p + 3];
      }
      for (let y: number = 0; y < height; y++) {
        const o: number = (y * width + x) * 4;
        buf[o] = Math.round(sr / win);
        buf[o + 1] = Math.round(sg / win);
        buf[o + 2] = Math.round(sb / win);
        buf[o + 3] = Math.round(sa / win);
        const outY: number = Math.min(height - 1, Math.max(0, y - r));
        const inY: number = Math.min(height - 1, Math.max(0, y + r + 1));
        const po: number = outY * 4;
        const pi: number = inY * 4;
        sr += col[pi] - col[po];
        sg += col[pi + 1] - col[po + 1];
        sb += col[pi + 2] - col[po + 2];
        sa += col[pi + 3] - col[po + 3];
      }
    }
  }

  /**
   * 像素化(马赛克)：每个 cell×cell 单元用其平均色填充。返回新缓冲。
   */
  static pixelate(src: Uint8Array, width: number, height: number, cell: number): Uint8Array {
    const out: Uint8Array = src.slice();
    const c: number = Math.max(1, cell);
    for (let by: number = 0; by < height; by += c) {
      for (let bx: number = 0; bx < width; bx += c) {
        const ex: number = Math.min(bx + c, width);
        const ey: number = Math.min(by + c, height);
        let r: number = 0;
        let g: number = 0;
        let b: number = 0;
        let a: number = 0;
        let n: number = 0;
        for (let y: number = by; y < ey; y++) {
          for (let x: number = bx; x < ex; x++) {
            const p: number = (y * width + x) * 4;
            r += src[p];
            g += src[p + 1];
            b += src[p + 2];
            a += src[p + 3];
            n++;
          }
        }
        if (n === 0) {
          continue;
        }
        const ar: number = Math.round(r / n);
        const ag: number = Math.round(g / n);
        const ab: number = Math.round(b / n);
        const aa: number = Math.round(a / n);
        for (let y: number = by; y < ey; y++) {
          for (let x: number = bx; x < ex; x++) {
            const p: number = (y * width + x) * 4;
            out[p] = ar;
            out[p + 1] = ag;
            out[p + 2] = ab;
            out[p + 3] = aa;
          }
        }
      }
    }
    return out;
  }

  /**
   * 半色调：先用平均色铺块并轻模糊作为平滑底，再按每格亮度叠加深色网点(奇偶行错位)。
   */
  static halftone(src: Uint8Array, width: number, height: number, cell: number): Uint8Array {
    const c: number = Math.max(2, cell);
    // 1) 平均色块底。
    const blocky: Uint8Array = BlurAlgorithms.pixelate(src, width, height, c);
    // 2) 轻模糊底，过渡更自然。
    const out: Uint8Array = BlurAlgorithms.gaussianBlur(blocky, width, height, Math.max(1, Math.round(c * 0.7)));
    // 3) 叠加网点。
    for (let by: number = 0; by < height; by += c) {
      const isOffsetRow: boolean = Math.floor(by / c) % 2 === 1;
      for (let bx: number = 0; bx < width; bx += c) {
        const ex: number = Math.min(bx + c, width);
        const ey: number = Math.min(by + c, height);
        let r: number = 0;
        let g: number = 0;
        let b: number = 0;
        let n: number = 0;
        for (let y: number = by; y < ey; y++) {
          for (let x: number = bx; x < ex; x++) {
            const p: number = (y * width + x) * 4;
            r += src[p];
            g += src[p + 1];
            b += src[p + 2];
            n++;
          }
        }
        if (n === 0) {
          continue;
        }
        const ar: number = r / n;
        const ag: number = g / n;
        const ab: number = b / n;
        // 亮度(感知加权) → 网点半径。
        const brightness: number = (ar * 0.299 + ag * 0.587 + ab * 0.114) / 255;
        const radius: number = brightness * c * 0.5;
        const cx: number = bx + c / 2 + (isOffsetRow ? c / 2 : 0);
        const cy: number = by + c / 2;
        const dotR: number = Math.round(ar * 0.8);
        const dotG: number = Math.round(ag * 0.8);
        const dotB: number = Math.round(ab * 0.8);
        BlurAlgorithms.fillCircle(out, width, height, cx, cy, radius, dotR, dotG, dotB);
      }
    }
    return out;
  }

  /** 在缓冲上光栅化一个实心圆(用于半色调网点)。 */
  private static fillCircle(
    buf: Uint8Array, width: number, height: number,
    cx: number, cy: number, radius: number, r: number, g: number, b: number
  ): void {
    if (radius < 0.5) {
      return;
    }
    const minX: number = Math.max(0, Math.floor(cx - radius));
    const maxX: number = Math.min(width - 1, Math.ceil(cx + radius));
    const minY: number = Math.max(0, Math.floor(cy - radius));
    const maxY: number = Math.min(height - 1, Math.ceil(cy + radius));
    const r2: number = radius * radius;
    for (let y: number = minY; y <= maxY; y++) {
      for (let x: number = minX; x <= maxX; x++) {
        const dx: number = x - cx;
        const dy: number = y - cy;
        if (dx * dx + dy * dy <= r2) {
          const p: number = (y * width + x) * 4;
          buf[p] = r;
          buf[p + 1] = g;
          buf[p + 2] = b;
        }
      }
    }
  }

  private constructor() {}
}
