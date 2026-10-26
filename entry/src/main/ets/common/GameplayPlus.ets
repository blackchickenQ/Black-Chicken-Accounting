import dataPreferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import { loadEggCoins, addEggCoins } from './Gameplay';

// ========== 新玩法系统：签到日历 / 摇钱树 / 记账盲盒机 / 预算守护战 / 无消费日挑战 ==========
// 五个玩法的进度/记录均按账本独立存档；鸡蛋币为全局共享货币。

const DEFAULT_LEDGER_ID: number = 1;

// ---------- 公共日期工具 ----------

function dateKey(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

function todayKey(): string {
  return dateKey(new Date());
}

function prevDayKey(key: string): string {
  const parts = key.split('-');
  const d = new Date(parseInt(parts[0], 10), parseInt(parts[1], 10) - 1, parseInt(parts[2], 10));
  d.setDate(d.getDate() - 1);
  return dateKey(d);
}

function nextDayKey(key: string): string {
  const parts = key.split('-');
  const d = new Date(parseInt(parts[0], 10), parseInt(parts[1], 10) - 1, parseInt(parts[2], 10));
  d.setDate(d.getDate() + 1);
  return dateKey(d);
}

function daysBetweenKeys(fromKey: string, toKey: string): number {
  const f = fromKey.split('-');
  const t = toKey.split('-');
  const fd = new Date(parseInt(f[0], 10), parseInt(f[1], 10) - 1, parseInt(f[2], 10)).getTime();
  const td = new Date(parseInt(t[0], 10), parseInt(t[1], 10) - 1, parseInt(t[2], 10)).getTime();
  return Math.round((td - fd) / 86400000);
}

function monthDaysOf(year: number, month: number): number {
  return new Date(year, month + 1, 0).getDate();
}

// 本周周一的日期 key（守护战按周刷新）
function mondayKeyOf(now: Date): string {
  const day = now.getDay();
  const diff = day === 0 ? 6 : day - 1;
  const d = new Date(now.getFullYear(), now.getMonth(), now.getDate() - diff);
  return dateKey(d);
}

// ---------- 账单读取（本地最小字段，避免与页面类型耦合） ----------

export interface PlaygroundBillInput {
  amount: number;
  type: string;
  date: number;
  ledgerId?: number;
}

async function loadPlaygroundBills(context: common.UIAbilityContext,
  ledgerId: number): Promise<PlaygroundBillInput[]> {
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    const data = await prefs.get('bills_key', '[]') as string;
    const all = JSON.parse(data) as PlaygroundBillInput[];
    const filtered: PlaygroundBillInput[] = [];
    for (const b of all) {
      if ((b.ledgerId ?? DEFAULT_LEDGER_ID) === ledgerId) {
        filtered.push(b);
      }
    }
    return filtered;
  } catch (e) {
    console.error('读取账单失败', e);
    return [];
  }
}

// 玩法乐园所选账本（-1 表示从未选择过）
export async function loadPlaygroundLedgerId(context: common.UIAbilityContext): Promise<number> {
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    const data = await prefs.get('playground_ledger_id', '') as string;
    if (data.length > 0) {
      const id = parseInt(data, 10);
      if (!isNaN(id)) {
        return id;
      }
    }
  } catch (e) {
    console.error('读取玩法乐园账本失败', e);
  }
  return -1;
}

export async function savePlaygroundLedgerId(context: common.UIAbilityContext, ledgerId: number): Promise<void> {
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    await prefs.put('playground_ledger_id', String(ledgerId));
    await prefs.flush();
  } catch (e) {
    console.error('保存玩法乐园账本失败', e);
  }
}

function expenseOnDay(bills: PlaygroundBillInput[], dayKeyStr: string): number {
  let total = 0;
  for (const b of bills) {
    if (b.type === '支出' && dateKey(new Date(b.date)) === dayKeyStr) {
      total += b.amount;
    }
  }
  return total;
}

// 本周（周一起至今）支出合计
function weeklyExpenseOf(bills: PlaygroundBillInput[]): number {
  const monday = mondayKeyOf(new Date());
  const today = todayKey();
  let total = 0;
  for (const b of bills) {
    if (b.type !== '支出') {
      continue;
    }
    const k = dateKey(new Date(b.date));
    if (k >= monday && k <= today) {
      total += b.amount;
    }
  }
  return Math.round(total * 100) / 100;
}

// 就地加经验（避免与成就模块互相引用）
async function addXpInline(context: common.UIAbilityContext, amount: number): Promise<void> {
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

// ========== 1. 签到日历：记一笔即打卡，连签递增奖励，满勤发大奖（按账本独立） ==========

interface CheckInPersist {
  days: string[];        // 已打卡日（YYYY-MM-DD）
  claimed: string[];     // 已领奖励的打卡日
  totalDays: number;     // 累计打卡天数
  bonusMonth: string;    // 最近已发满勤奖的月份（YYYY-MM）
}

function emptyCheckIn(): CheckInPersist {
  return { days: [], claimed: [], totalDays: 0, bonusMonth: '' };
}

async function loadCheckInRaw(context: common.UIAbilityContext, ledgerId: number): Promise<CheckInPersist> {
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    const data = await prefs.get(`check_in:${ledgerId}`, '') as string;
    if (data.length > 0) {
      const parsed = JSON.parse(data) as CheckInPersist;
      return {
        days: parsed.days ? parsed.days : [],
        claimed: parsed.claimed ? parsed.claimed : [],
        totalDays: parsed.totalDays ? parsed.totalDays : 0,
        bonusMonth: parsed.bonusMonth ? parsed.bonusMonth : ''
      };
    }
  } catch (e) {
    console.error('读取签到记录失败', e);
  }
  return emptyCheckIn();
}

async function saveCheckInRaw(context: common.UIAbilityContext,
  ledgerId: number, raw: CheckInPersist): Promise<void> {
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    await prefs.put(`check_in:${ledgerId}`, JSON.stringify(raw));
    await prefs.flush();
  } catch (e) {
    console.error('保存签到记录失败', e);
  }
}

// 连续打卡天数（含今天；今天未打则从昨天起算）
function checkInStreakOf(days: string[]): number {
  let cursor = todayKey();
  if (days.indexOf(cursor) === -1) {
    cursor = prevDayKey(cursor);
  }
  let streak = 0;
  while (days.indexOf(cursor) !== -1) {
    streak++;
    cursor = prevDayKey(cursor);
  }
  return streak;
}

// 打卡奖励：基础 5 币 + 连签加成（每天 +2，封顶 +15）
export function checkInRewardOf(streak: number): number {
  const s = streak > 0 ? streak : 1;
  return 5 + Math.min(15, (s - 1) * 2);
}

export const CHECK_IN_FULL_MONTH_BONUS = 100;

export interface CheckInData {
  year: number;
  month: number;          // 0 起
  daysInMonth: number;
  firstWeekday: number;   // 本月 1 号是周几（周一=0）
  checkedDayNums: number[]; // 本月已打卡的日期数字
  todayDayNum: number;
  todayChecked: boolean;
  todayClaimed: boolean;
  streak: number;
  totalDays: number;
  nextReward: number;
}

export async function loadCheckIn(context: common.UIAbilityContext, ledgerId: number): Promise<CheckInData> {
  const raw = await loadCheckInRaw(context, ledgerId);
  const now = new Date();
  const year = now.getFullYear();
  const month = now.getMonth();
  const dim = monthDaysOf(year, month);
  const firstWeekday = (new Date(year, month, 1).getDay() + 6) % 7;
  const today = todayKey();
  const checkedDayNums: number[] = [];
  const monthPrefix = `${year}-${String(month + 1).padStart(2, '0')}-`;
  for (const d of raw.days) {
    if (d.indexOf(monthPrefix) === 0) {
      checkedDayNums.push(parseInt(d.substring(monthPrefix.length), 10));
    }
  }
  return {
    year: year,
    month: month,
    daysInMonth: dim,
    firstWeekday: firstWeekday,
    checkedDayNums: checkedDayNums,
    todayDayNum: now.getDate(),
    todayChecked: raw.days.indexOf(today) !== -1,
    todayClaimed: raw.claimed.indexOf(today) !== -1,
    streak: checkInStreakOf(raw.days),
    totalDays: raw.totalDays,
    nextReward: checkInRewardOf(checkInStreakOf(raw.days) + (raw.days.indexOf(today) === -1 ? 1 : 0))
  };
}

// 记账打卡：今日首次打卡返回 true（按账本独立）
export async function checkInToday(context: common.UIAbilityContext, ledgerId: number): Promise<boolean> {
  const raw = await loadCheckInRaw(context, ledgerId);
  const today = todayKey();
  if (raw.days.indexOf(today) !== -1) {
    return false;
  }
  raw.days.push(today);
  raw.totalDays += 1;
  await saveCheckInRaw(context, ledgerId, raw);
  return true;
}

// 领取今日打卡奖励；返回奖励数额，不可领取返回 -1
export async function claimCheckInReward(context: common.UIAbilityContext, ledgerId: number): Promise<number> {
  const raw = await loadCheckInRaw(context, ledgerId);
  const today = todayKey();
  if (raw.days.indexOf(today) === -1 || raw.claimed.indexOf(today) !== -1) {
    return -1;
  }
  raw.claimed.push(today);
  await saveCheckInRaw(context, ledgerId, raw);
  const reward = checkInRewardOf(checkInStreakOf(raw.days));
  await addEggCoins(context, reward);
  return reward;
}

// 满勤奖励：本月每天都打卡后自动发放一次；返回奖励数额，未达成/已领返回 -1
export async function checkFullMonthBonus(context: common.UIAbilityContext, ledgerId: number): Promise<number> {
  const raw = await loadCheckInRaw(context, ledgerId);
  const now = new Date();
  const mk = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
  if (raw.bonusMonth === mk) {
    return -1;
  }
  const dim = monthDaysOf(now.getFullYear(), now.getMonth());
  for (let day = 1; day <= dim; day++) {
    const key = `${mk}-${String(day).padStart(2, '0')}`;
    if (raw.days.indexOf(key) === -1) {
      return -1;
    }
  }
  raw.bonusMonth = mk;
  await saveCheckInRaw(context, ledgerId, raw);
  await addEggCoins(context, CHECK_IN_FULL_MONTH_BONUS);
  return CHECK_IN_FULL_MONTH_BONUS;
}

// ========== 2. 摇钱树养成：花鸡蛋币种树，每天记账浇水，断签枯萎需重种（按账本独立） ==========

export const TREE_PLANT_COST = 20;
export const TREE_COINS_CAP = 50;
export const TREE_STAGE_EMOJI: string[] = ['🌰', '🌱', '🌿', '🌳', '🌟'];
export const TREE_STAGE_NAME: string[] = ['种子', '发芽', '树苗', '成树', '摇钱树'];
export const TREE_STAGE_DAYS: number[] = [0, 1, 3, 7, 14];    // 达到该形态所需连续浇水天数
export const TREE_STAGE_INCOME: number[] = [0, 0, 1, 2, 4];   // 每天掉落到树上的金币

interface MoneyTreePersist {
  planted: boolean;
  lastWater: string;    // 最近浇水日
  streak: number;       // 连续浇水天数
  coins: number;        // 树上待收金币
  harvestCount: number;
  lastAccrue: string;   // 最近掉落结算日
}

function emptyTree(): MoneyTreePersist {
  return { planted: false, lastWater: '', streak: 0, coins: 0, harvestCount: 0, lastAccrue: '' };
}

async function loadTreeRaw(context: common.UIAbilityContext, ledgerId: number): Promise<MoneyTreePersist> {
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    const data = await prefs.get(`money_tree:${ledgerId}`, '') as string;
    if (data.length > 0) {
      const parsed = JSON.parse(data) as MoneyTreePersist;
      return {
        planted: parsed.planted === true,
        lastWater: parsed.lastWater ? parsed.lastWater : '',
        streak: parsed.streak ? parsed.streak : 0,
        coins: parsed.coins ? parsed.coins : 0,
        harvestCount: parsed.harvestCount ? parsed.harvestCount : 0,
        lastAccrue: parsed.lastAccrue ? parsed.lastAccrue : ''
      };
    }
  } catch (e) {
    console.error('读取摇钱树失败', e);
  }
  return emptyTree();
}

async function saveTreeRaw(context: common.UIAbilityContext,
  ledgerId: number, raw: MoneyTreePersist): Promise<void> {
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    await prefs.put(`money_tree:${ledgerId}`, JSON.stringify(raw));
    await prefs.flush();
  } catch (e) {
    console.error('保存摇钱树失败', e);
  }
}

function treeStageOf(streak: number): number {
  let stage = 0;
  for (let i = 0; i < TREE_STAGE_DAYS.length; i++) {
    if (streak >= TREE_STAGE_DAYS[i]) {
      stage = i;
    }
  }
  return stage;
}

function treeAliveOf(raw: MoneyTreePersist): boolean {
  if (!raw.planted) {
    return false;
  }
  const today = todayKey();
  return raw.lastWater === today || raw.lastWater === prevDayKey(today);
}

export interface MoneyTreeData {
  planted: boolean;
  alive: boolean;
  stage: number;
  stageName: string;
  stageEmoji: string;
  streak: number;
  nextStageDays: number;   // 距下一形态还需浇水天数（满级为 0）
  coins: number;
  harvestCount: number;
}

export async function loadTree(context: common.UIAbilityContext, ledgerId: number): Promise<MoneyTreeData> {
  const raw = await loadTreeRaw(context, ledgerId);
  const alive = treeAliveOf(raw);
  const stage = treeStageOf(raw.streak);
  let nextStageDays = 0;
  if (stage < TREE_STAGE_DAYS.length - 1) {
    nextStageDays = TREE_STAGE_DAYS[stage + 1] - raw.streak;
    if (nextStageDays < 0) {
      nextStageDays = 0;
    }
  }
  return {
    planted: raw.planted && alive,
    alive: alive,
    stage: stage,
    stageName: TREE_STAGE_NAME[stage],
    stageEmoji: TREE_STAGE_EMOJI[stage],
    streak: raw.streak,
    nextStageDays: nextStageDays,
    coins: alive ? raw.coins : 0,
    harvestCount: raw.harvestCount
  };
}

// 种树：花费 TREE_PLANT_COST 鸡蛋币，种下即完成当日浇水
export async function plantTree(context: common.UIAbilityContext, ledgerId: number): Promise<boolean> {
  const raw = await loadTreeRaw(context, ledgerId);
  if (raw.planted && treeAliveOf(raw)) {
    return false;
  }
  const coins = await loadEggCoins(context);
  if (coins < TREE_PLANT_COST) {
    return false;
  }
  await addEggCoins(context, -TREE_PLANT_COST);
  const fresh = emptyTree();
  fresh.planted = true;
  fresh.lastWater = todayKey();
  fresh.streak = 1;
  fresh.lastAccrue = todayKey();
  await saveTreeRaw(context, ledgerId, fresh);
  return true;
}

// 浇水（记账触发）：返回 'notPlanted' | 'ok' | 'withered'
export async function waterTree(context: common.UIAbilityContext, ledgerId: number): Promise<string> {
  const raw = await loadTreeRaw(context, ledgerId);
  if (!raw.planted) {
    return 'notPlanted';
  }
  const today = todayKey();
  if (raw.lastWater === today) {
    return 'ok';
  }
  if (raw.lastWater !== prevDayKey(today)) {
    // 断签枯萎：重置为未种植
    await saveTreeRaw(context, ledgerId, emptyTree());
    return 'withered';
  }
  raw.streak += 1;
  raw.lastWater = today;
  await saveTreeRaw(context, ledgerId, raw);
  return 'ok';
}

// 每日掉落结算：树上按形态掉金币（封顶 TREE_COINS_CAP），返回结算后树上金币
export async function accrueTree(context: common.UIAbilityContext, ledgerId: number): Promise<number> {
  const raw = await loadTreeRaw(context, ledgerId);
  if (!raw.planted || !treeAliveOf(raw)) {
    return 0;
  }
  const today = todayKey();
  if (raw.lastAccrue === today) {
    return raw.coins;
  }
  let days = 1;
  if (raw.lastAccrue.length > 0) {
    days = daysBetweenKeys(raw.lastAccrue, today);
    if (days < 1) {
      days = 1;
    }
  }
  const add = days * TREE_STAGE_INCOME[treeStageOf(raw.streak)];
  raw.coins = Math.min(TREE_COINS_CAP, raw.coins + add);
  raw.lastAccrue = today;
  await saveTreeRaw(context, ledgerId, raw);
  return raw.coins;
}

// 收取树上金币转入鸡蛋币；返回收取数额，无可收返回 -1
export async function harvestTree(context: common.UIAbilityContext, ledgerId: number): Promise<number> {
  await accrueTree(context, ledgerId);
  const raw = await loadTreeRaw(context, ledgerId);
  if (!raw.planted || !treeAliveOf(raw) || raw.coins <= 0) {
    return -1;
  }
  const got = raw.coins;
  raw.coins = 0;
  raw.harvestCount += 1;
  await saveTreeRaw(context, ledgerId, raw);
  await addEggCoins(context, got);
  return got;
}

// ========== 3. 记账盲盒机：花鸡蛋币抽盒，随机开出鸡蛋币，小概率彩蛋（记录按账本独立） ==========

export interface BlindBoxTier {
  id: string;
  emoji: string;
  name: string;
  cost: number;        // 原价（每日首次抽任意档半价）
  min1: number;        // 普通档下限
  max1: number;        // 普通档上限
  min2: number;        // 高级档下限
  max2: number;        // 高级档上限
  jackpot: number;     // 彩蛋固定奖励
}

export const BLIND_BOX_TIERS: BlindBoxTier[] = [
  { id: 'small', emoji: '🥚', name: '小福盒', cost: 20, min1: 10, max1: 20, min2: 20, max2: 40, jackpot: 60 },
  { id: 'mid', emoji: '🧧', name: '中福盒', cost: 50, min1: 28, max1: 48, min2: 50, max2: 80, jackpot: 130 },
  { id: 'big', emoji: '💎', name: '大福盒', cost: 120, min1: 70, max1: 110, min2: 110, max2: 170, jackpot: 300 }
];

export function getBlindBoxTier(id: string): BlindBoxTier | null {
  for (const t of BLIND_BOX_TIERS) {
    if (t.id === id) {
      return t;
    }
  }
  return null;
}

interface BlindBoxPersist {
  halfDate: string;  // 最近一次享受半价的日期
  draws: number;
  jackpots: number;
}

async function loadBoxRaw(context: common.UIAbilityContext, ledgerId: number): Promise<BlindBoxPersist> {
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    const data = await prefs.get(`blind_box:${ledgerId}`, '') as string;
    if (data.length > 0) {
      const parsed = JSON.parse(data) as BlindBoxPersist;
      return {
        halfDate: parsed.halfDate ? parsed.halfDate : '',
        draws: parsed.draws ? parsed.draws : 0,
        jackpots: parsed.jackpots ? parsed.jackpots : 0
      };
    }
  } catch (e) {
    console.error('读取盲盒记录失败', e);
  }
  return { halfDate: '', draws: 0, jackpots: 0 };
}

async function saveBoxRaw(context: common.UIAbilityContext,
  ledgerId: number, raw: BlindBoxPersist): Promise<void> {
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    await prefs.put(`blind_box:${ledgerId}`, JSON.stringify(raw));
    await prefs.flush();
  } catch (e) {
    console.error('保存盲盒记录失败', e);
  }
}

export interface BlindBoxStateData {
  halfPriceToday: boolean;
  draws: number;
  jackpots: number;
}

export async function loadBlindBoxState(context: common.UIAbilityContext,
  ledgerId: number): Promise<BlindBoxStateData> {
  const raw = await loadBoxRaw(context, ledgerId);
  return {
    halfPriceToday: raw.halfDate !== todayKey(),
    draws: raw.draws,
    jackpots: raw.jackpots
  };
}

// 今日抽某档的实际花费（考虑每日首次半价）
export async function getBlindBoxCost(context: common.UIAbilityContext,
  ledgerId: number, tierId: string): Promise<number> {
  const tier = getBlindBoxTier(tierId);
  if (tier === null) {
    return -1;
  }
  const raw = await loadBoxRaw(context, ledgerId);
  return raw.halfDate !== todayKey() ? tier.cost / 2 : tier.cost;
}

export interface BlindBoxResult {
  tierName: string;
  tierEmoji: string;
  coins: number;
  jackpot: boolean;
  cost: number;
  halfPrice: boolean;
}

// 抽盒：扣费 → 随机开出奖励（65% 普通 / 27% 高级 / 8% 彩蛋）并附赠经验
export async function drawBlindBox(context: common.UIAbilityContext,
  ledgerId: number, tierId: string): Promise<BlindBoxResult | null> {
  const tier = getBlindBoxTier(tierId);
  if (tier === null) {
    return null;
  }
  const raw = await loadBoxRaw(context, ledgerId);
  const halfPrice = raw.halfDate !== todayKey();
  const cost = halfPrice ? tier.cost / 2 : tier.cost;
  const coins = await loadEggCoins(context);
  if (coins < cost) {
    return null;
  }
  const r = Math.random();
  let reward = 0;
  let jackpot = false;
  if (r < 0.65) {
    reward = tier.min1 + Math.floor(Math.random() * (tier.max1 - tier.min1 + 1));
  } else if (r < 0.92) {
    reward = tier.min2 + Math.floor(Math.random() * (tier.max2 - tier.min2 + 1));
  } else {
    reward = tier.jackpot;
    jackpot = true;
  }
  await addEggCoins(context, reward - cost);
  await addXpInline(context, 2 + Math.floor(Math.random() * 7));
  raw.halfDate = todayKey();
  raw.draws += 1;
  if (jackpot) {
    raw.jackpots += 1;
  }
  await saveBoxRaw(context, ledgerId, raw);
  return {
    tierName: tier.name,
    tierEmoji: tier.emoji,
    coins: reward,
    jackpot: jackpot,
    cost: cost,
    halfPrice: halfPrice
  };
}

// ========== 4. 预算守护战：每周一只吞金兽，预算内记账打它，超预算它回血 ==========

export const GUARDIAN_MAX_HP = 100;
export const GUARDIAN_REWARD = 60;
export const GUARDIAN_DEFAULT_WEEKLY_BUDGET = 300;

interface GuardianPersist {
  weekKey: string;       // 本周周一日期 key
  hp: number;
  defeated: boolean;
  rewarded: boolean;
  defeatedCount: number;
}

async function loadGuardianRaw(context: common.UIAbilityContext, ledgerId: number): Promise<GuardianPersist> {
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    const data = await prefs.get(`guardian_battle:${ledgerId}`, '') as string;
    if (data.length > 0) {
      const parsed = JSON.parse(data) as GuardianPersist;
      return {
        weekKey: parsed.weekKey ? parsed.weekKey : '',
        hp: parsed.hp !== undefined ? parsed.hp : GUARDIAN_MAX_HP,
        defeated: parsed.defeated === true,
        rewarded: parsed.rewarded === true,
        defeatedCount: parsed.defeatedCount ? parsed.defeatedCount : 0
      };
    }
  } catch (e) {
    console.error('读取守护战失败', e);
  }
  return { weekKey: '', hp: GUARDIAN_MAX_HP, defeated: false, rewarded: false, defeatedCount: 0 };
}

async function saveGuardianRaw(context: common.UIAbilityContext,
  ledgerId: number, raw: GuardianPersist): Promise<void> {
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    await prefs.put(`guardian_battle:${ledgerId}`, JSON.stringify(raw));
    await prefs.flush();
  } catch (e) {
    console.error('保存守护战失败', e);
  }
}

// 本周预算额度：所选账本的本月预算按周折算；未设预算用默认值
export async function loadWeeklyBudget(context: common.UIAbilityContext, ledgerId: number): Promise<number> {
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    const data = await prefs.get('budget', '') as string;
    if (data.length > 0) {
      const parsed = JSON.parse(data) as Record<string, number>;
      const now = new Date();
      const key = `${ledgerId}:${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
      const value = parsed[key];
      if (value !== undefined && value > 0) {
        const weekly = Math.round(value * 7 / monthDaysOf(now.getFullYear(), now.getMonth()));
        return weekly > 0 ? weekly : GUARDIAN_DEFAULT_WEEKLY_BUDGET;
      }
    }
  } catch (e) {
    console.error('读取周预算失败', e);
  }
  return GUARDIAN_DEFAULT_WEEKLY_BUDGET;
}

export interface GuardianData {
  hp: number;
  maxHp: number;
  defeated: boolean;
  rewarded: boolean;
  defeatedCount: number;
  weeklyExpense: number;
  weeklyBudget: number;
}

// 读取守护战状态（跨周自动重置 BOSS，按账本独立）
export async function loadGuardian(context: common.UIAbilityContext, ledgerId: number): Promise<GuardianData> {
  let raw = await loadGuardianRaw(context, ledgerId);
  const curWeek = mondayKeyOf(new Date());
  if (raw.weekKey !== curWeek) {
    raw = {
      weekKey: curWeek,
      hp: GUARDIAN_MAX_HP,
      defeated: false,
      rewarded: false,
      defeatedCount: raw.defeatedCount
    };
    await saveGuardianRaw(context, ledgerId, raw);
  }
  const bills = await loadPlaygroundBills(context, ledgerId);
  return {
    hp: raw.hp,
    maxHp: GUARDIAN_MAX_HP,
    defeated: raw.defeated,
    rewarded: raw.rewarded,
    defeatedCount: raw.defeatedCount,
    weeklyExpense: weeklyExpenseOf(bills),
    weeklyBudget: await loadWeeklyBudget(context, ledgerId)
  };
}

// 记一笔支出打 BOSS：预算内造成伤害（5 + 金额加成，上限 15），超预算回血 10
export async function hitGuardian(context: common.UIAbilityContext,
  ledgerId: number, billAmount: number): Promise<string> {
  let raw = await loadGuardianRaw(context, ledgerId);
  const curWeek = mondayKeyOf(new Date());
  if (raw.weekKey !== curWeek) {
    raw = {
      weekKey: curWeek,
      hp: GUARDIAN_MAX_HP,
      defeated: false,
      rewarded: false,
      defeatedCount: raw.defeatedCount
    };
  }
  if (raw.defeated) {
    await saveGuardianRaw(context, ledgerId, raw);
    return 'none';
  }
  const bills = await loadPlaygroundBills(context, ledgerId);
  const weeklyBudget = await loadWeeklyBudget(context, ledgerId);
  const weeklyExpense = weeklyExpenseOf(bills);
  if (weeklyExpense <= weeklyBudget) {
    const damage = 5 + Math.min(10, Math.floor(billAmount / 10));
    raw.hp = Math.max(0, raw.hp - damage);
    if (raw.hp === 0) {
      raw.defeated = true;
      raw.defeatedCount += 1;
      await saveGuardianRaw(context, ledgerId, raw);
      return 'defeated';
    }
    await saveGuardianRaw(context, ledgerId, raw);
    return 'hit';
  }
  raw.hp = Math.min(GUARDIAN_MAX_HP, raw.hp + 10);
  await saveGuardianRaw(context, ledgerId, raw);
  return 'healed';
}

// 领取击败奖励；返回奖励数额，不可领取返回 -1
export async function claimGuardianReward(context: common.UIAbilityContext, ledgerId: number): Promise<number> {
  const raw = await loadGuardianRaw(context, ledgerId);
  if (!raw.defeated || raw.rewarded) {
    return -1;
  }
  raw.rewarded = true;
  await saveGuardianRaw(context, ledgerId, raw);
  await addEggCoins(context, GUARDIAN_REWARD);
  await addXpInline(context, 20);
  return GUARDIAN_REWARD;
}

// ========== 5. 无消费日挑战：每日支出不超上限即"节流日"，连击奖励递增（按账本独立） ==========

// 节流日奖励：5 + 连击 × 3，封顶 30
export function noSpendRewardOf(streak: number): number {
  return Math.min(30, 5 + streak * 3);
}

interface NoSpendPersist {
  limit: number;         // 每日消费上限（0 = 完全不消费）
  lastSettle: string;    // 已结算到的日期（不含）
  streak: number;
  bestStreak: number;
  days: string[];        // 达标日列表（展示用，保留最近 90 天）
  pendingReward: number; // 待领取奖励
}

async function loadNoSpendRaw(context: common.UIAbilityContext, ledgerId: number): Promise<NoSpendPersist> {
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    const data = await prefs.get(`no_spend:${ledgerId}`, '') as string;
    if (data.length > 0) {
      const parsed = JSON.parse(data) as NoSpendPersist;
      return {
        limit: parsed.limit !== undefined ? parsed.limit : 0,
        lastSettle: parsed.lastSettle ? parsed.lastSettle : '',
        streak: parsed.streak ? parsed.streak : 0,
        bestStreak: parsed.bestStreak ? parsed.bestStreak : 0,
        days: parsed.days ? parsed.days : [],
        pendingReward: parsed.pendingReward ? parsed.pendingReward : 0
      };
    }
  } catch (e) {
    console.error('读取无消费挑战失败', e);
  }
  return { limit: 0, lastSettle: '', streak: 0, bestStreak: 0, days: [], pendingReward: 0 };
}

async function saveNoSpendRaw(context: common.UIAbilityContext,
  ledgerId: number, raw: NoSpendPersist): Promise<void> {
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    await prefs.put(`no_spend:${ledgerId}`, JSON.stringify(raw));
    await prefs.flush();
  } catch (e) {
    console.error('保存无消费挑战失败', e);
  }
}

// 设置每日消费上限（0 ~ 100000）
export async function setNoSpendLimit(context: common.UIAbilityContext,
  ledgerId: number, limit: number): Promise<void> {
  const raw = await loadNoSpendRaw(context, ledgerId);
  const v = Math.max(0, Math.min(100000, Math.round(limit * 100) / 100));
  raw.limit = v;
  await saveNoSpendRaw(context, ledgerId, raw);
}

export interface NoSpendSettleResult {
  qualified: boolean;  // 结算出的最近一天达标
  broke: boolean;      // 结算中出现断签
  settledDays: number; // 本次结算天数
}

// 结算：把上次结算日到昨天之间的每一天逐日判定（该账本支出 ≤ 上限 = 节流日），奖励累计到待领取
export async function settleNoSpend(context: common.UIAbilityContext,
  ledgerId: number): Promise<NoSpendSettleResult> {
  const raw = await loadNoSpendRaw(context, ledgerId);
  const result: NoSpendSettleResult = { qualified: false, broke: false, settledDays: 0 };
  const today = todayKey();
  if (raw.lastSettle.length === 0) {
    // 首次使用：从昨天起开始记录，不回溯历史
    raw.lastSettle = prevDayKey(today);
    await saveNoSpendRaw(context, ledgerId, raw);
    return result;
  }
  if (raw.lastSettle >= prevDayKey(today)) {
    return result;
  }
  const bills = await loadPlaygroundBills(context, ledgerId);
  let cursor = nextDayKey(raw.lastSettle);
  while (cursor < today) {
    const expense = expenseOnDay(bills, cursor);
    if (expense <= raw.limit) {
      raw.streak += 1;
      if (raw.streak > raw.bestStreak) {
        raw.bestStreak = raw.streak;
      }
      raw.days.push(cursor);
      if (raw.days.length > 90) {
        raw.days = raw.days.slice(raw.days.length - 90);
      }
      raw.pendingReward += noSpendRewardOf(raw.streak);
      result.qualified = true;
    } else {
      raw.streak = 0;
      result.broke = true;
      result.qualified = false;
    }
    result.settledDays += 1;
    cursor = nextDayKey(cursor);
  }
  raw.lastSettle = prevDayKey(today);
  await saveNoSpendRaw(context, ledgerId, raw);
  return result;
}

export interface NoSpendData {
  limit: number;
  streak: number;
  bestStreak: number;
  pendingReward: number;
  todayExpense: number;
  todayQualified: boolean;  // 今天（截至目前）支出 ≤ 上限
  recentDays: string[];     // 最近达标日
}

export async function loadNoSpend(context: common.UIAbilityContext, ledgerId: number): Promise<NoSpendData> {
  const raw = await loadNoSpendRaw(context, ledgerId);
  const bills = await loadPlaygroundBills(context, ledgerId);
  const todayExpense = expenseOnDay(bills, todayKey());
  return {
    limit: raw.limit,
    streak: raw.streak,
    bestStreak: raw.bestStreak,
    pendingReward: raw.pendingReward,
    todayExpense: todayExpense,
    todayQualified: todayExpense <= raw.limit,
    recentDays: raw.days
  };
}

// 领取节流日累计奖励；返回数额，无可领返回 -1
export async function claimNoSpendReward(context: common.UIAbilityContext, ledgerId: number): Promise<number> {
  const raw = await loadNoSpendRaw(context, ledgerId);
  if (raw.pendingReward <= 0) {
    return -1;
  }
  const reward = raw.pendingReward;
  raw.pendingReward = 0;
  await saveNoSpendRaw(context, ledgerId, raw);
  await addEggCoins(context, reward);
  return reward;
}

// ========== 记账统一钩子 ==========

export interface PlaygroundBillResult {
  treeWithered: boolean;
  checkedIn: boolean;
  guardian: string;          // 'defeated' | 'hit' | 'healed' | 'none'
  noSpendQualified: boolean; // 结算出新的达标日
  noSpendBroke: boolean;     // 结算出现断签
}

// 记一笔账后调用（全部按账单所属账本结算）：摇钱树浇水 + 签到打卡 + 守护战（支出才打）+ 无消费日结算
export async function trackPlaygroundOnBill(context: common.UIAbilityContext,
  ledgerId: number, amount: number, type: string): Promise<PlaygroundBillResult> {
  const result: PlaygroundBillResult = {
    treeWithered: false,
    checkedIn: false,
    guardian: 'none',
    noSpendQualified: false,
    noSpendBroke: false
  };
  try {
    const treeResult = await waterTree(context, ledgerId);
    result.treeWithered = treeResult === 'withered';
    result.checkedIn = await checkInToday(context, ledgerId);
    if (type === '支出') {
      result.guardian = await hitGuardian(context, ledgerId, amount);
    }
    const settle = await settleNoSpend(context, ledgerId);
    result.noSpendQualified = settle.qualified;
    result.noSpendBroke = settle.broke;
  } catch (e) {
    console.error('新玩法记账钩子失败', e);
  }
  return result;
}
