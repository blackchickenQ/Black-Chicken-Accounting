import dataPreferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import { ASSET_PALETTE } from './AppTheme';
import { BillItem } from '../pages/Index';

// ---------- 成就系统：勋章定义 / 等级表 / 经验值引擎 ----------

// 勋章定义
export interface AchievementDef {
  id: string;
  name: string;
  desc: string;
  kind: string;    // 判定维度（billCount/streak/...）
  target: number;  // 达成阈值
  reward: number;  // 解锁奖励经验
  icon: Resource;
  color: string;   // 勋章底色
}

// 成就判定数据（由账单/存钱目标/预算/信用账户汇总而来）
export interface AchievementCriteria {
  billCount: number;
  incomeCount: number;
  expenseTotal: number;
  incomeTotal: number;
  streakDays: number;
  goalDoneCount: number;
  hasBudget: boolean;
  creditCount: number;
  guideDone: boolean;  // 新手引导已完成
}

export interface LevelDef {
  level: number;
  name: string;
  xp: number;  // 该级起始累计经验
}

export interface LevelInfo {
  level: number;
  name: string;
  totalXp: number;
  curLevelXp: number;
  nextLevelXp: number;  // 满级时与 curLevelXp 相同
  maxed: boolean;
}

// 等级表（10 级，累计经验阈值）
export const LEVELS: LevelDef[] = [
  { level: 1, name: '记账小白', xp: 0 },
  { level: 2, name: '记账新手', xp: 100 },
  { level: 3, name: '记账学徒', xp: 300 },
  { level: 4, name: '记账达人', xp: 600 },
  { level: 5, name: '理财行家', xp: 1000 },
  { level: 6, name: '理财高手', xp: 1600 },
  { level: 7, name: '财富管家', xp: 2500 },
  { level: 8, name: '财富达人', xp: 3800 },
  { level: 9, name: '财富大师', xp: 5600 },
  { level: 10, name: '传说账神', xp: 8000 }
];

// ---------- 小鸡养成：成长形态（10 级映射 5 形态） ----------

export interface ChickStage {
  stage: number;      // 形态序号 1-5
  minLevel: number;   // 达到该形态的最低等级
  name: string;       // 形态名
  image: Resource;    // 形象图片（用户设计稿）
  desc: string;       // 形态描述
  tapLines: string[]; // 点击小鸡时的随机台词
}

export const CHICK_STAGES: ChickStage[] = [
  {
    stage: 1, minLevel: 1, name: '安静的小蛋', image: $r('app.media.chick_stage1'),
    desc: '一颗安静的蛋，正在积蓄破壳的力量',
    tapLines: ['（蛋壳里好像有动静…）', '（滚了滚）', '（嘘，它在睡觉）']
  },
  {
    stage: 2, minLevel: 2, name: '破壳小鸡', image: $r('app.media.chick_stage2'),
    desc: '探出了毛茸茸的小脑袋',
    tapLines: ['叽！', '（好奇地张望）', '叽叽？']
  },
  {
    stage: 3, minLevel: 4, name: '毛茸雏鸡', image: $r('app.media.chick_stage3'),
    desc: '叽叽喳喳，整天跟在你身边',
    tapLines: ['叽叽喳喳！', '米米米~', '陪我记一笔账嘛', '（歪头看你）']
  },
  {
    stage: 4, minLevel: 6, name: '少年乌鸡', image: $r('app.media.chick_stage4'),
    desc: '羽毛渐丰，开始学着打鸣',
    tapLines: ['咕咕哒！', '今天记账了吗？', '我可是乌鸡！', '（抖了抖羽毛）']
  },
  {
    stage: 5, minLevel: 9, name: '传说金乌鸡', image: $r('app.media.chick_stage5'),
    desc: '头戴金冠的传说之鸡，记账界的传奇',
    tapLines: ['本鸡即是传说！', '咕咕哒——！', '记账不息，成长不止', '（金冠闪闪发光）']
  }
];

// 由等级取当前小鸡形态
export function getChickStage(level: number): ChickStage {
  let cur: ChickStage = CHICK_STAGES[0];
  for (let i = 0; i < CHICK_STAGES.length; i++) {
    if (level >= CHICK_STAGES[i].minLevel) {
      cur = CHICK_STAGES[i];
    }
  }
  return cur;
}

// 勋章定义表（17 枚）
export const ACHIEVEMENT_DEFS: AchievementDef[] = [
  { id: 'first_bill', name: '初出茅庐', desc: '记下第一笔账单', kind: 'billCount', target: 1, reward: 20, icon: $r('sys.symbol.seal'), color: ASSET_PALETTE[3] },
  { id: 'bill_10', name: '小试牛刀', desc: '累计记账 10 笔', kind: 'billCount', target: 10, reward: 30, icon: $r('sys.symbol.list_bullet'), color: ASSET_PALETTE[0] },
  { id: 'bill_50', name: '渐入佳境', desc: '累计记账 50 笔', kind: 'billCount', target: 50, reward: 50, icon: $r('sys.symbol.star'), color: ASSET_PALETTE[6] },
  { id: 'bill_100', name: '百炼成钢', desc: '累计记账 100 笔', kind: 'billCount', target: 100, reward: 80, icon: $r('sys.symbol.medal'), color: ASSET_PALETTE[12] },
  { id: 'bill_500', name: '记账狂人', desc: '累计记账 500 笔', kind: 'billCount', target: 500, reward: 150, icon: $r('sys.symbol.bolt'), color: ASSET_PALETTE[8] },
  { id: 'bill_1000', name: '千锤百炼', desc: '累计记账 1000 笔', kind: 'billCount', target: 1000, reward: 300, icon: $r('sys.symbol.star_trophy'), color: ASSET_PALETTE[9] },
  { id: 'streak_3', name: '三日之约', desc: '连续记账 3 天', kind: 'streak', target: 3, reward: 30, icon: $r('sys.symbol.hourglass'), color: ASSET_PALETTE[2] },
  { id: 'streak_7', name: '七日不辍', desc: '连续记账 7 天', kind: 'streak', target: 7, reward: 60, icon: $r('sys.symbol.calendar_badge_checkmark'), color: ASSET_PALETTE[10] },
  { id: 'streak_30', name: '坚持一月', desc: '连续记账 30 天', kind: 'streak', target: 30, reward: 150, icon: $r('sys.symbol.flame'), color: ASSET_PALETTE[7] },
  { id: 'streak_100', name: '百日传奇', desc: '连续记账 100 天', kind: 'streak', target: 100, reward: 400, icon: $r('sys.symbol.firework'), color: ASSET_PALETTE[11] },
  { id: 'income_1', name: '第一桶金', desc: '记录第一笔收入', kind: 'incomeCount', target: 1, reward: 30, icon: $r('sys.symbol.goldcoin'), color: ASSET_PALETTE[9] },
  { id: 'income_10', name: '财源广进', desc: '累计记录 10 笔收入', kind: 'incomeCount', target: 10, reward: 50, icon: $r('sys.symbol.coins'), color: ASSET_PALETTE[4] },
  { id: 'expense_1k', name: '消费入门', desc: '累计支出达 1000 元', kind: 'expenseTotal', target: 1000, reward: 30, icon: $r('sys.symbol.yuansign_circle'), color: ASSET_PALETTE[5] },
  { id: 'expense_10k', name: '万级消费', desc: '累计支出达 1 万元', kind: 'expenseTotal', target: 10000, reward: 80, icon: $r('sys.symbol.moneybag'), color: ASSET_PALETTE[7] },
  { id: 'income_10k', name: '万元入账', desc: '累计收入达 1 万元', kind: 'incomeTotal', target: 10000, reward: 100, icon: $r('sys.symbol.yuansign_moneybag'), color: ASSET_PALETTE[6] },
  { id: 'goal_done', name: '梦想成真', desc: '完成第一个存钱目标', kind: 'goalDone', target: 1, reward: 100, icon: $r('sys.symbol.flag_checkered'), color: ASSET_PALETTE[1] },
  { id: 'budget_set', name: '预算管家', desc: '设置过预算', kind: 'budget', target: 1, reward: 20, icon: $r('sys.symbol.wallet'), color: ASSET_PALETTE[12] },
  { id: 'credit_first', name: '信用初体验', desc: '添加第一个信用账户', kind: 'credit', target: 1, reward: 30, icon: $r('sys.symbol.creditcard'), color: ASSET_PALETTE[13] },
  { id: 'guide_done', name: '初来乍到', desc: '完成新手引导', kind: 'guide', target: 1, reward: 20, icon: $r('sys.symbol.firework'), color: ASSET_PALETTE[2] }
];

// 按维度取当前进度值
export function getCriteriaValue(criteria: AchievementCriteria, kind: string): number {
  switch (kind) {
    case 'billCount':
      return criteria.billCount;
    case 'incomeCount':
      return criteria.incomeCount;
    case 'expenseTotal':
      return criteria.expenseTotal;
    case 'incomeTotal':
      return criteria.incomeTotal;
    case 'streak':
      return criteria.streakDays;
    case 'goalDone':
      return criteria.goalDoneCount;
    case 'budget':
      return criteria.hasBudget ? 1 : 0;
    case 'credit':
      return criteria.creditCount;
    case 'guide':
      return criteria.guideDone ? 1 : 0;
    default:
      return 0;
  }
}

// 由累计经验推算等级
export function getLevelInfo(xp: number): LevelInfo {
  let idx = 0;
  for (let i = 0; i < LEVELS.length; i++) {
    if (xp >= LEVELS[i].xp) {
      idx = i;
    }
  }
  const cur = LEVELS[idx];
  const maxed = idx >= LEVELS.length - 1;
  const next = maxed ? cur : LEVELS[idx + 1];
  return {
    level: cur.level,
    name: cur.name,
    totalXp: xp,
    curLevelXp: cur.xp,
    nextLevelXp: next.xp,
    maxed: maxed
  };
}

// 连续记账天数：账单日期按日去重后，从今天（或昨天）向前数连续有账单的天数
export function computeStreakDays(dates: number[]): number {
  if (dates.length === 0) {
    return 0;
  }
  const daySet: Set<number> = new Set<number>();
  for (const ts of dates) {
    const d = new Date(ts);
    daySet.add(new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime());
  }
  const now = new Date();
  let cursor = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
  if (!daySet.has(cursor)) {
    cursor -= 86400000;  // 今天还没记账则从昨天起算
  }
  let streak = 0;
  while (daySet.has(cursor)) {
    streak++;
    cursor -= 86400000;
  }
  return streak;
}

// ---------- 经验值 / 解锁记录持久化 ----------

export async function loadXp(context: common.UIAbilityContext): Promise<number> {
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    const data = await prefs.get('user_xp', '0') as string;
    const v = parseInt(data, 10);
    return isNaN(v) ? 0 : v;
  } catch (e) {
    console.error('读取经验值失败', e);
    return 0;
  }
}

export async function addXp(context: common.UIAbilityContext, amount: number): Promise<void> {
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    const data = await prefs.get('user_xp', '0') as string;
    const cur = parseInt(data, 10);
    await prefs.put('user_xp', String((isNaN(cur) ? 0 : cur) + amount));
    await prefs.flush();
  } catch (e) {
    console.error('写入经验值失败', e);
  }
}

export async function loadUnlocked(context: common.UIAbilityContext): Promise<string[]> {
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    const data = await prefs.get('unlocked_achievements', '[]') as string;
    return JSON.parse(data) as string[];
  } catch (e) {
    console.error('读取成就解锁记录失败', e);
    return [];
  }
}

export async function saveUnlocked(context: common.UIAbilityContext, ids: string[]): Promise<void> {
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    await prefs.put('unlocked_achievements', JSON.stringify(ids));
    await prefs.flush();
  } catch (e) {
    console.error('保存成就解锁记录失败', e);
  }
}

// 检查并解锁：达成且未解锁的勋章写入记录并发放经验，返回新解锁列表（调用方负责提示）
export async function checkAndUnlock(context: common.UIAbilityContext,
  criteria: AchievementCriteria): Promise<AchievementDef[]> {
  const unlocked = await loadUnlocked(context);
  const unlockedSet: Set<string> = new Set<string>(unlocked);
  const fresh: AchievementDef[] = [];
  for (const def of ACHIEVEMENT_DEFS) {
    if (!unlockedSet.has(def.id) && getCriteriaValue(criteria, def.kind) >= def.target) {
      fresh.push(def);
    }
  }
  if (fresh.length > 0) {
    const freshIds: string[] = fresh.map((d: AchievementDef): string => d.id);
    await saveUnlocked(context, [...unlocked, ...freshIds]);
    let reward = 0;
    for (const d of fresh) {
      reward += d.reward;
    }
    await addXp(context, reward);
  }
  return fresh;
}

// ---------- 判定数据组装 ----------

interface GoalLike {
  id: number;
  name: string;
  target: number;
  saved: number;
}

interface CreditLike {
  id: number;
  name: string;
  debt: number;
  dueDate?: number;
}

// 从持久化数据构建成就判定数据（成就页 / 记账后检查共用）
export async function buildCriteriaFromPrefs(context: common.UIAbilityContext): Promise<AchievementCriteria> {
  const criteria: AchievementCriteria = {
    billCount: 0,
    incomeCount: 0,
    expenseTotal: 0,
    incomeTotal: 0,
    streakDays: 0,
    goalDoneCount: 0,
    hasBudget: false,
    creditCount: 0,
    guideDone: false
  };
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    // 账单：笔数 / 收入笔数 / 累计收支 / 连续天数
    const billsData = await prefs.get('bills_key', '[]') as string;
    const bills = JSON.parse(billsData) as BillItem[];
    const dates: number[] = [];
    for (const b of bills) {
      dates.push(b.date);
      if (b.type === '收入') {
        criteria.incomeCount++;
        criteria.incomeTotal += b.amount;
      } else {
        criteria.expenseTotal += b.amount;
      }
    }
    criteria.billCount = bills.length;
    criteria.streakDays = computeStreakDays(dates);
    // 存钱目标：已完成数
    const goalsData = await prefs.get('saving_goals', '[]') as string;
    const goals = JSON.parse(goalsData) as GoalLike[];
    for (const g of goals) {
      if (g.target > 0 && g.saved >= g.target) {
        criteria.goalDoneCount++;
      }
    }
    // 预算：任一账本任一月份设置过
    const budgetData = await prefs.get('budget', '') as string;
    if (budgetData) {
      const parsed = JSON.parse(budgetData) as Record<string, number>;
      criteria.hasBudget = Object.keys(parsed).length > 0;
    }
    // 信用账户：数量
    const creditData = await prefs.get('credit_accounts', '[]') as string;
    const credits = JSON.parse(creditData) as CreditLike[];
    criteria.creditCount = credits.length;
    // 新手引导
    criteria.guideDone = await prefs.get('guide_done', false) as boolean;
  } catch (e) {
    console.error('构建成就判定数据失败', e);
  }
  return criteria;
}
