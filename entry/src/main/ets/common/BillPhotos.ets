// ---------- 账单图片附件：相册选图、沙箱存储与清理 ----------
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';

export const MAX_BILL_PHOTOS: number = 3;
const PHOTO_DIR_NAME: string = 'bill_photos';
const FILE_PREFIX: string = 'file://';

// 图片存放在 filesDir（默认随系统备份恢复），避免 cacheDir 被清理导致丢图
function ensurePhotoDir(context: common.UIAbilityContext): string {
  const dir: string = context.filesDir + '/' + PHOTO_DIR_NAME;
  if (!fs.accessSync(dir)) {
    fs.mkdirSync(dir, true);
  }
  return dir;
}

function getFileExt(uri: string): string {
  const lower: string = uri.toLowerCase();
  if (lower.endsWith('.png')) {
    return '.png';
  }
  if (lower.endsWith('.gif')) {
    return '.gif';
  }
  if (lower.endsWith('.webp')) {
    return '.webp';
  }
  return '.jpg';
}

function sandboxPathFromUri(uri: string): string {
  if (uri.startsWith(FILE_PREFIX)) {
    return uri.substring(FILE_PREFIX.length);
  }
  return uri;
}

// 从系统相册选择图片（无需权限），拷贝到应用沙箱并返回沙箱 file:// URI 列表
export async function pickBillPhotos(context: common.UIAbilityContext, remainCount: number): Promise<string[]> {
  if (remainCount <= 0) {
    return [];
  }
  const selectOption = new photoAccessHelper.PhotoSelectOptions();
  selectOption.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
  selectOption.maxSelectNumber = remainCount;
  const picker = new photoAccessHelper.PhotoViewPicker();
  const result: photoAccessHelper.PhotoSelectResult = await picker.select(selectOption);
  if (result.photoUris.length === 0) {
    return [];
  }
  const dir: string = ensurePhotoDir(context);
  const saved: string[] = [];
  for (let i = 0; i < result.photoUris.length; i++) {
    let srcFile: fs.File | undefined = undefined;
    let destFile: fs.File | undefined = undefined;
    try {
      srcFile = fs.openSync(result.photoUris[i], fs.OpenMode.READ_ONLY);
      const destPath: string = dir + '/' + Date.now() + '_'
        + util.generateRandomUUID().substring(0, 8) + getFileExt(result.photoUris[i]);
      destFile = fs.openSync(destPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.copyFileSync(srcFile.fd, destFile.fd);
      saved.push(FILE_PREFIX + destPath);
    } catch (e) {
      console.error('保存账单图片失败: ' + JSON.stringify(e));
    } finally {
      if (srcFile) {
        fs.closeSync(srcFile);
      }
      if (destFile) {
        fs.closeSync(destFile);
      }
    }
  }
  return saved;
}

export function deleteBillPhoto(uri: string): void {
  try {
    const path: string = sandboxPathFromUri(uri);
    if (fs.accessSync(path)) {
      fs.unlinkSync(path);
    }
  } catch (e) {
    console.error('删除账单图片失败: ' + JSON.stringify(e));
  }
}

export function deleteBillPhotos(uris: string[]): void {
  for (let i = 0; i < uris.length; i++) {
    deleteBillPhoto(uris[i]);
  }
}

// 清空全部账单图片（清除应用数据时使用）
export function clearAllBillPhotos(context: common.UIAbilityContext): void {
  try {
    const dir: string = context.filesDir + '/' + PHOTO_DIR_NAME;
    if (fs.accessSync(dir)) {
      fs.rmdirSync(dir);
    }
  } catch (e) {
    console.error('清空账单图片失败: ' + JSON.stringify(e));
  }
}
