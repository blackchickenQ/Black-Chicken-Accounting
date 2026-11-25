// ---------- 小票图片优化：旋转 / 灰度增强（提高端侧 OCR 识别率），全部在应用沙箱内完成 ----------
import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { ensurePhotoDir, sandboxPathFromUri, deleteBillPhoto } from './BillPhotos';

const FILE_PREFIX: string = 'file://';

// 解码沙箱小票图片为 PixelMap
async function loadPixelMap(uri: string): Promise<image.PixelMap> {
  const source: image.ImageSource = image.createImageSource(sandboxPathFromUri(uri));
  const pm: image.PixelMap = await source.createPixelMap();
  await source.release();
  return pm;
}

// 把处理后的 PixelMap 打包为 JPEG 存入沙箱，返回新 file:// URI
async function savePixelMapToSandbox(context: common.UIAbilityContext, pm: image.PixelMap): Promise<string> {
  const packer: image.ImagePacker = image.createImagePacker();
  const data: ArrayBuffer = await packer.packing(pm, { format: 'image/jpeg', quality: 92 });
  packer.release();
  const dir: string = ensurePhotoDir(context);
  const destPath: string = dir + '/' + Date.now() + '_'
    + util.generateRandomUUID().substring(0, 8) + '.jpg';
  const file: fs.File = fs.openSync(destPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  fs.writeSync(file.fd, data);
  fs.closeSync(file);
  return FILE_PREFIX + destPath;
}

// 旋转小票图片（±90 度）：生成新文件并删除原图，避免 Image 缓存不刷新
export async function rotateBillPhoto(context: common.UIAbilityContext, uri: string, degree: number): Promise<string> {
  const pm: image.PixelMap = await loadPixelMap(uri);
  await pm.rotate(degree);
  const newUri: string = await savePixelMapToSandbox(context, pm);
  await pm.release();
  deleteBillPhoto(uri);
  return newUri;
}

// 灰度化 + 自适应对比度拉伸：提高暗光 / 模糊小票的 OCR 识别率
export async function enhanceBillPhoto(context: common.UIAbilityContext, uri: string): Promise<string> {
  const source: image.ImageSource = image.createImageSource(sandboxPathFromUri(uri));
  const pm: image.PixelMap = await source.createPixelMap({ desiredPixelFormat: image.PixelMapFormat.BGRA_8888 });
  await source.release();
  const byteCount: number = pm.getPixelBytesNumber();
  const buffer: ArrayBuffer = new ArrayBuffer(byteCount);
  await pm.readPixelsToBuffer(buffer);
  const pixels: Uint8Array = new Uint8Array(buffer);
  // 第一次遍历：求亮度范围（BGRA_8888 内存布局为 B/G/R/A）
  let minLuma: number = 255;
  let maxLuma: number = 0;
  for (let i = 0; i + 3 < pixels.length; i += 4) {
    const luma: number = 0.299 * pixels[i + 2] + 0.587 * pixels[i + 1] + 0.114 * pixels[i];
    if (luma < minLuma) {
      minLuma = luma;
    }
    if (luma > maxLuma) {
      maxLuma = luma;
    }
  }
  // 第二次遍历：灰度化并按亮度范围拉伸对比度
  if (maxLuma > minLuma) {
    const scale: number = 255 / (maxLuma - minLuma);
    for (let i = 0; i + 3 < pixels.length; i += 4) {
      const luma: number = 0.299 * pixels[i + 2] + 0.587 * pixels[i + 1] + 0.114 * pixels[i];
      const stretched: number = Math.min(255, Math.round((luma - minLuma) * scale));
      pixels[i] = stretched;
      pixels[i + 1] = stretched;
      pixels[i + 2] = stretched;
    }
    await pm.writeBufferToPixels(buffer);
  }
  const newUri: string = await savePixelMapToSandbox(context, pm);
  await pm.release();
  deleteBillPhoto(uri);
  return newUri;
}
