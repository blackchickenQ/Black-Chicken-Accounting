import dataPreferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';

// ========== 赚钱计时：设定时薪或总价，实时显示已赚金额 ==========
// 数据与逻辑模块：设置、进行中的计时会话、历史记录均持久化于 bill_data；
// 计时采用「时间戳累积法」——只记录片段起点与已累计毫秒，
// 切后台/锁屏/应用重启后按时间差自动校正，不依赖前台 tick。

// ---------- 数据模型 ----------

// 计费设置：mode 'hourly' 时薪 | 'fixed' 总价
export interface EarningSettings {
  mode: string;
  hourlyRate: number;     // 时薪 ¥/小时
  fixedTotal: number;     // 总价模式：约定总价
  fixedHours: number;     // 总价模式：预计工时（小时，支持小数）
  overtimePolicy: string; // 总价模式超时：'stop' 停在总价 | 'continue' 按比例继续累加
  endAction: string;      // 结束后：'manual' 手动确认记账 | 'auto' 自动记一笔 | 'none' 不记账
  defaultNote: string;    // 上次使用的备注（作为下次默认值）
}

// 进行中的计时会话（实时落盘，闪退/重启可恢复）
export interface EarningSession {
  mode: string;
  hourlyRate: number;
  fixedTotal: number;
  fixedMinutes: number;   // 预计时长（分钟）
  overtimePolicy: string;
  endAction: string;
  note: string;
  startTs: number;        // 本次赚钱开始时间戳
  accumMs: number;        // 已结束片段累计毫秒
  segmentStartTs: number; // 当前计时片段开始时间戳（0 = 暂停中）
}

// 历史记录
export interface EarningRecord {
  id: number;
  startTime: number;
  endTime: number;
  durationMs: number;
  amount: number;
  mode: string;
  hourlyRate: number;
  fixedTotal: number;
  fixedMinutes: number;
  note: string;
  billId: number;         // 已入账的账单 id（0 = 未入账）
}

const MAX_RECORDS: number = 100;

// ---------- 设置 ----------

export function defaultEarningSettings(): EarningSettings {
  return {
    mode: 'hourly',
    hourlyRate: 30,
    fixedTotal: 200,
    fixedHours: 4,
    overtimePolicy: 'continue',
    endAction: 'manual',
    defaultNote: ''
  };
}

export async function loadEarningSettings(context: common.UIAbilityContext): Promise<EarningSettings> {
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    const raw = await prefs.get('earning_settings', '') as string;
    if (raw.length > 0) {
      const parsed = JSON.parse(raw) as EarningSettings;
      const def = defaultEarningSettings();
      return {
        mode: parsed.mode === 'fixed' ? 'fixed' : 'hourly',
        hourlyRate: parsed.hourlyRate > 0 ? parsed.hourlyRate : def.hourlyRate,
        fixedTotal: parsed.fixedTotal > 0 ? parsed.fixedTotal : def.fixedTotal,
        fixedHours: parsed.fixedHours > 0 ? parsed.fixedHours : def.fixedHours,
        overtimePolicy: parsed.overtimePolicy === 'stop' ? 'stop' : 'continue',
        endAction: parsed.endAction === 'auto' || parsed.endAction === 'none' ? parsed.endAction : 'manual',
        defaultNote: parsed.defaultNote !== undefined ? parsed.defaultNote : ''
      };
    }
  } catch (e) {
    console.error('读取赚钱计时设置失败', e);
  }
  return defaultEarningSettings();
}

export async function saveEarningSettings(context: common.UIAbilityContext, s: EarningSettings): Promise<void> {
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    await prefs.put('earning_settings', JSON.stringify(s));
    await prefs.flush();
  } catch (e) {
    console.error('保存赚钱计时设置失败', e);
  }
}

// ---------- 进行中的会话 ----------

export async function loadEarningSession(context: common.UIAbilityContext): Promise<EarningSession | null> {
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    const raw = await prefs.get('earning_session', '') as string;
    if (raw.length > 0) {
      return JSON.parse(raw) as EarningSession;
    }
  } catch (e) {
    console.error('读取赚钱计时会话失败', e);
  }
  return null;
}

export async function saveEarningSession(context: common.UIAbilityContext, s: EarningSession): Promise<void> {
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    await prefs.put('earning_session', JSON.stringify(s));
    await prefs.flush();
  } catch (e) {
    console.error('保存赚钱计时会话失败', e);
  }
}

export async function clearEarningSession(context: common.UIAbilityContext): Promise<void> {
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    await prefs.put('earning_session', '');
    await prefs.flush();
  } catch (e) {
    console.error('清除赚钱计时会话失败', e);
  }
}

// ---------- 历史记录 ----------

export async function loadEarningRecords(context: common.UIAbilityContext): Promise<EarningRecord[]> {
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    const raw = await prefs.get('earning_records', '[]') as string;
    return JSON.parse(raw) as EarningRecord[];
  } catch (e) {
    console.error('读取赚钱计时历史失败', e);
    return [];
  }
}

export async function appendEarningRecord(context: common.UIAbilityContext, r: EarningRecord): Promise<void> {
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    const raw = await prefs.get('earning_records', '[]') as string;
    const list = JSON.parse(raw) as EarningRecord[];
    list.unshift(r);
    if (list.length > MAX_RECORDS) {
      list.splice(MAX_RECORDS);
    }
    await prefs.put('earning_records', JSON.stringify(list));
    await prefs.flush();
  } catch (e) {
    console.error('保存赚钱计时历史失败', e);
  }
}

export async function deleteEarningRecord(context: common.UIAbilityContext, id: number): Promise<void> {
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    const raw = await prefs.get('earning_records', '[]') as string;
    const list = (JSON.parse(raw) as EarningRecord[]).filter((r: EarningRecord): boolean => r.id !== id);
    await prefs.put('earning_records', JSON.stringify(list));
    await prefs.flush();
  } catch (e) {
    console.error('删除赚钱计时历史失败', e);
  }
}

export async function updateEarningRecordBill(context: common.UIAbilityContext,
  recordId: number, billId: number): Promise<void> {
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    const raw = await prefs.get('earning_records', '[]') as string;
    const list = (JSON.parse(raw) as EarningRecord[]).map((r: EarningRecord): EarningRecord => {
      if (r.id === recordId) {
        r.billId = billId;
      }
      return r;
    });
    await prefs.put('earning_records', JSON.stringify(list));
    await prefs.flush();
  } catch (e) {
    console.error('更新赚钱计时入账标记失败', e);
  }
}

// ---------- 计算与格式化 ----------

// 按已工作时长计算已赚金额（展示时再取 2 位小数）
export function computeEarnedAmount(session: EarningSession, elapsedMs: number): number {
  if (session.mode === 'fixed') {
    const plannedMs = session.fixedMinutes * 60 * 1000;
    if (plannedMs <= 0) {
      return 0;
    }
    if (elapsedMs >= plannedMs) {
      if (session.overtimePolicy === 'stop') {
        return session.fixedTotal;
      }
      return session.fixedTotal + session.fixedTotal * (elapsedMs - plannedMs) / plannedMs;
    }
    return session.fixedTotal * elapsedMs / plannedMs;
  }
  return session.hourlyRate * elapsedMs / 3600000;
}

// 每分钟进账（用于速率提示）
export function perMinuteRate(session: EarningSession): number {
  if (session.mode === 'fixed') {
    if (session.fixedMinutes <= 0) {
      return 0;
    }
    return session.fixedTotal / session.fixedMinutes;
  }
  return session.hourlyRate / 60;
}

// HH:MM:SS
export function formatDurationHMS(ms: number): string {
  const totalSec = Math.floor(Math.max(0, ms) / 1000);
  const h = Math.floor(totalSec / 3600);
  const m = Math.floor((totalSec % 3600) / 60);
  const s = totalSec % 60;
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
}

// 人类可读短时长：'2小时15分' / '45分钟'
export function formatDurationShort(ms: number): string {
  const totalMin = Math.floor(Math.max(0, ms) / 60000);
  const h = Math.floor(totalMin / 60);
  const m = totalMin % 60;
  if (h > 0) {
    return m > 0 ? `${h}小时${m}分` : `${h}小时`;
  }
  return `${m}分钟`;
}

// '11月20日 14:05'
export function formatRecordTime(ts: number): string {
  const d = new Date(ts);
  return `${d.getMonth() + 1}月${d.getDate()}日 ` +
    `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
}
