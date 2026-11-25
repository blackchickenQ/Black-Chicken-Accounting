// common/NetAsset.ets
// 净资产快照与历史回推估算工具（月报/年报共用，避免与 Index 的 BillItem 产生循环依赖）
import dataPreferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';

// 最小账单结构：仅需金额/类型/时间戳/账本 id 即可完成回推估算
export interface NetAssetBill {
  amount: number;
  type: string;      // '收入' | '支出'
  date: number;      // 记账时间戳
  ledgerId?: number; // 所在账本 id（可选）
}

// 净资产快照：资产合计 / 负债合计 / 净资产
export interface NetAssetSnapshot {
  fundTotal: number;
  totalDebt: number;
  net: number;
}

// 资产账户最小结构（asset_categories）
interface FundAccountLite {
  name: string;
  amount: number;
}

// 信用账户最小结构（credit_accounts）
interface CreditAccountLite {
  id: number;
  name: string;
  debt: number;
}

// 读取当前净资产快照（bill_data 库：asset_categories - credit_accounts）
export async function loadNetAssetSnapshot(context: common.UIAbilityContext): Promise<NetAssetSnapshot> {
  const snapshot: NetAssetSnapshot = { fundTotal: 0, totalDebt: 0, net: 0 };
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    const fundRaw = await prefs.get('asset_categories', '[]') as string;
    const funds = JSON.parse(fundRaw) as FundAccountLite[];
    for (const f of funds) {
      snapshot.fundTotal += f.amount;
    }
    const creditRaw = await prefs.get('credit_accounts', '[]') as string;
    const credits = JSON.parse(creditRaw) as CreditAccountLite[];
    for (const c of credits) {
      snapshot.totalDebt += c.debt;
    }
    snapshot.net = snapshot.fundTotal - snapshot.totalDebt;
  } catch (e) {
    console.error('加载净资产快照失败', e);
  }
  return snapshot;
}

// 回推某时点的净资产：net_at_t = 当前净资产 - t 之后收入 + t 之后支出
// （假设收支均经由资产账户，结果为估算值，调用方 UI 需标注“估算”）
// timestamp: 目标时点（一般取月末/年末最后一毫秒）；ledgerId > 0 时仅统计该账本
export function estimateNetAssetAt(currentNet: number, bills: NetAssetBill[],
  timestamp: number, ledgerId: number = 0): number {
  let incomeAfter = 0;
  let expenseAfter = 0;
  for (const b of bills) {
    if (ledgerId > 0 && (b.ledgerId ?? 1) !== ledgerId) {
      continue;
    }
    if (b.date < timestamp) {
      continue;
    }
    if (b.type === '收入') {
      incomeAfter += b.amount;
    } else if (b.type === '支出') {
      expenseAfter += b.amount;
    }
  }
  return currentNet - incomeAfter + expenseAfter;
}

// 月末时点（该月最后一毫秒）
export function monthEndTime(year: number, month: number): number {
  // month 为 1-12；下月 1 日 0 点减 1 毫秒
  return new Date(year, month, 1).getTime() - 1;
}
