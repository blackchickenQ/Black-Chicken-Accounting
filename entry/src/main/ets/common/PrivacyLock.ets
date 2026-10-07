// ---------- 隐私锁：PIN 密码的哈希与存取 ----------
import dataPreferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';

const PIN_KEY: string = 'privacy_pin';
const BACKUP_KEY: string = 'privacy_pin_backup';
const HINT_KEY: string = 'privacy_lock_hint';
const FINGERPRINT_KEY: string = 'fingerprint_unlock_enabled';
const HW_ACCOUNT_OPENID_KEY: string = 'hw_account_openid';
const HW_ACCOUNT_UNIONID_KEY: string = 'hw_account_unionid';
const HW_ACCOUNT_NICKNAME_KEY: string = 'hw_account_nickname';
const HW_ACCOUNT_AVATAR_KEY: string = 'hw_account_avatar';

// 简单字符串哈希（djb2 变体），避免明文存储 PIN
export function hashPin(pin: string): string {
  let hash: number = 5381;
  for (let i = 0; i < pin.length; i++) {
    hash = (((hash << 5) + hash) ^ pin.charCodeAt(i)) >>> 0;
  }
  return hash.toString();
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
  await prefs.put(PIN_KEY, hashPin(pin));
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
  await prefs.put(BACKUP_KEY, hashPin(pwd));
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
  return stored === hashPin(pwd);
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
  return stored === hashPin(pin);
}
