// ---------- 隐私锁：PIN 密码的哈希与存取 ----------
import dataPreferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';

const PIN_KEY: string = 'privacy_pin';
const BACKUP_KEY: string = 'privacy_pin_backup';
const HINT_KEY: string = 'privacy_lock_hint';
const FINGERPRINT_KEY: string = 'fingerprint_unlock_enabled';
const HW_ACCOUNT_OPENID_KEY: string = 'hw_account_openid';
const HW_ACCOUNT_UNIONID_KEY: string = 'hw_account_unionid';
const HW_ACCOUNT_NICKNAME_KEY: string = 'hw_account_nickname';
const HW_ACCOUNT_AVATAR_KEY: string = 'hw_account_avatar';
// 新版存储格式前缀：v2:<saltHex>:<hmacHex>
const PIN_V2_PREFIX: string = 'v2:';

function bytesToHex(bytes: Uint8Array): string {
  let hex: string = '';
  for (let i = 0; i < bytes.length; i++) {
    hex += bytes[i].toString(16).padStart(2, '0');
  }
  return hex;
}

function hexToBytes(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = parseInt(hex.substring(i * 2, i * 2 + 2), 16);
  }
  return bytes;
}

// 旧版弱哈希（djb2 变体），仅用于兼容升级前已存储的数据，不再用于新存储
function legacyHashPin(pin: string): string {
  let hash: number = 5381;
  for (let i = 0; i < pin.length; i++) {
    hash = (((hash << 5) + hash) ^ pin.charCodeAt(i)) >>> 0;
  }
  return hash.toString();
}

// 生成 16 字节随机盐
function generateSaltHex(): string {
  const rand = cryptoFramework.createRandom();
  const salt = rand.generateRandomSync(16);
  return bytesToHex(salt.data);
}

// HMAC-SHA256(pin, salt)，返回 "v2:<saltHex>:<hmacHex>"
async function hashPinSecure(pin: string, saltHex: string): Promise<string> {
  const mac = cryptoFramework.createMac('SHA256');
  const keyGen = cryptoFramework.createSymKeyGenerator('HMAC');
  const symKey = await keyGen.convertKey({ data: hexToBytes(saltHex) });
  await mac.init(symKey);
  const encoder = new util.TextEncoder();
  await mac.update({ data: encoder.encodeInto(pin) });
  const result = await mac.doFinal();
  return PIN_V2_PREFIX + saltHex + ':' + bytesToHex(result.data);
}

// 校验：v2 格式走 HMAC 比对，旧格式走 djb2 比对
async function verifyStored(stored: string, pin: string): Promise<boolean> {
  if (stored.startsWith(PIN_V2_PREFIX)) {
    const parts = stored.substring(PIN_V2_PREFIX.length).split(':');
    if (parts.length !== 2 || parts[0].length === 0 || parts[1].length === 0) {
      return false;
    }
    const computed = await hashPinSecure(pin, parts[0]);
    return computed === stored;
  }
  return stored === legacyHashPin(pin);
}

export function isSixDigits(text: string): boolean {
  if (text.length !== 6) {
    return false;
  }
  for (let i = 0; i < text.length; i++) {
    const code = text.charCodeAt(i);
    if (code < 48 || code > 57) {
      return false;
    }
  }
  return true;
}

export async function savePin(context: common.Context, pin: string): Promise<void> {
  const prefs = await dataPreferences.getPreferences(context, 'bill_data');
  await prefs.put(PIN_KEY, await hashPinSecure(pin, generateSaltHex()));
  await prefs.flush();
}

export async function clearPin(context: common.Context): Promise<void> {
  const prefs = await dataPreferences.getPreferences(context, 'bill_data');
  await prefs.put(PIN_KEY, '');
  await prefs.put(BACKUP_KEY, '');
  await prefs.put(HINT_KEY, '');
  await prefs.put(FINGERPRINT_KEY, false);
  await prefs.flush();
}

// ---------- 指纹解锁开关 ----------
export async function saveFingerprintUnlockEnabled(context: common.Context, enabled: boolean): Promise<void> {
  const prefs = await dataPreferences.getPreferences(context, 'bill_data');
  await prefs.put(FINGERPRINT_KEY, enabled);
  await prefs.flush();
}

export async function getFingerprintUnlockEnabled(context: common.Context): Promise<boolean> {
  const prefs = await dataPreferences.getPreferences(context, 'bill_data');
  const stored = await prefs.get(FINGERPRINT_KEY, false) as boolean;
  return stored;
}

// ---------- 华为账号（仅本地标识 + 头像昵称展示） ----------
export class HuaweiAccountInfo {
  openId: string = '';
  unionId: string = '';
  nickname: string = '';
  avatarUri: string = '';
}

export async function saveHuaweiAccountInfo(context: common.Context, info: HuaweiAccountInfo): Promise<void> {
  const prefs = await dataPreferences.getPreferences(context, 'bill_data');
  await prefs.put(HW_ACCOUNT_OPENID_KEY, info.openId);
  await prefs.put(HW_ACCOUNT_UNIONID_KEY, info.unionId);
  await prefs.put(HW_ACCOUNT_NICKNAME_KEY, info.nickname);
  await prefs.put(HW_ACCOUNT_AVATAR_KEY, info.avatarUri);
  await prefs.flush();
}

export async function loadHuaweiAccountInfo(context: common.Context): Promise<HuaweiAccountInfo | undefined> {
  const prefs = await dataPreferences.getPreferences(context, 'bill_data');
  const openId = await prefs.get(HW_ACCOUNT_OPENID_KEY, '') as string;
  if (openId.length === 0) {
    return undefined;
  }
  const info = new HuaweiAccountInfo();
  info.openId = openId;
  info.unionId = await prefs.get(HW_ACCOUNT_UNIONID_KEY, '') as string;
  info.nickname = await prefs.get(HW_ACCOUNT_NICKNAME_KEY, '') as string;
  info.avatarUri = await prefs.get(HW_ACCOUNT_AVATAR_KEY, '') as string;
  return info;
}

export async function clearHuaweiAccountInfo(context: common.Context): Promise<void> {
  const prefs = await dataPreferences.getPreferences(context, 'bill_data');
  await prefs.put(HW_ACCOUNT_OPENID_KEY, '');
  await prefs.put(HW_ACCOUNT_UNIONID_KEY, '');
  await prefs.put(HW_ACCOUNT_NICKNAME_KEY, '');
  await prefs.put(HW_ACCOUNT_AVATAR_KEY, '');
  await prefs.flush();
}

// ---------- 备用密码（无位数限制）与密码提示 ----------
export async function saveBackupPassword(context: common.Context, pwd: string): Promise<void> {
  const prefs = await dataPreferences.getPreferences(context, 'bill_data');
  await prefs.put(BACKUP_KEY, await hashPinSecure(pwd, generateSaltHex()));
  await prefs.flush();
}

export async function isBackupSet(context: common.Context): Promise<boolean> {
  const prefs = await dataPreferences.getPreferences(context, 'bill_data');
  const stored = await prefs.get(BACKUP_KEY, '') as string;
  return stored.length > 0;
}

export async function verifyBackupPassword(context: common.Context, pwd: string): Promise<boolean> {
  const prefs = await dataPreferences.getPreferences(context, 'bill_data');
  const stored = await prefs.get(BACKUP_KEY, '') as string;
  if (stored.length === 0) {
    return false;
  }
  const ok = await verifyStored(stored, pwd);
  // 旧格式校验通过后平滑升级为新格式
  if (ok && !stored.startsWith(PIN_V2_PREFIX)) {
    await prefs.put(BACKUP_KEY, await hashPinSecure(pwd, generateSaltHex()));
    await prefs.flush();
  }
  return ok;
}

export async function saveLockHint(context: common.Context, hint: string): Promise<void> {
  const prefs = await dataPreferences.getPreferences(context, 'bill_data');
  await prefs.put(HINT_KEY, hint);
  await prefs.flush();
}

export async function getLockHint(context: common.Context): Promise<string> {
  const prefs = await dataPreferences.getPreferences(context, 'bill_data');
  return await prefs.get(HINT_KEY, '') as string;
}

export async function isPinSet(context: common.Context): Promise<boolean> {
  const prefs = await dataPreferences.getPreferences(context, 'bill_data');
  const stored = await prefs.get(PIN_KEY, '') as string;
  return stored.length > 0;
}

export async function verifyPin(context: common.Context, pin: string): Promise<boolean> {
  const prefs = await dataPreferences.getPreferences(context, 'bill_data');
  const stored = await prefs.get(PIN_KEY, '') as string;
  if (stored.length === 0) {
    return true;
  }
  const ok = await verifyStored(stored, pin);
  // 旧格式校验通过后平滑升级为新格式
  if (ok && !stored.startsWith(PIN_V2_PREFIX)) {
    await prefs.put(PIN_KEY, await hashPinSecure(pin, generateSaltHex()));
    await prefs.flush();
  }
  return ok;
}
