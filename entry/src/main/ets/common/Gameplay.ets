import dataPreferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';

// ========== 玩法系统：鸡蛋币 / 每日任务 / 鸡窝场景 / 愿望清单 / 52周挑战 ==========

// ---------- 鸡蛋币（小鸡养成玩法的通用货币） ----------

export async function loadEggCoins(context: common.UIAbilityContext): Promise<number> {
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    const data = await prefs.get('egg_coins', '0') as string;
    const v = parseInt(data, 10);
    return isNaN(v) ? 0 : v;
  } catch (e) {
    console.error('读取鸡蛋币失败', e);
    return 0;
  }
}

export async function addEggCoins(context: common.UIAbilityContext, delta: number): Promise<number> {
  let result = 0;
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    const data = await prefs.get('egg_coins', '0') as string;
    const cur = parseInt(data, 10);
    result = Math.max(0, (isNaN(cur) ? 0 : cur) + delta);
    await prefs.put('egg_coins', String(result));
    await prefs.flush();
  } catch (e) {
    console.error('写入鸡蛋币失败', e);
  }
  return result;
}

// ---------- 连击加成：按连续记账天数放大记账经验 ----------

export function getStreakMultiplier(streakDays: number): number {
  if (streakDays >= 30) {
    return 2.0;
  }
  if (streakDays >= 7) {
    return 1.5;
  }
  if (streakDays >= 3) {
    return 1.2;
  }
  return 1.0;
}

export function getMultiplierText(multiplier: number): string {
  if (multiplier >= 2) {
    return 'x2.0';
  }
  return 'x' + multiplier.toFixed(1);
}

// ---------- 每日任务 ----------

export interface DailyTaskDef {
  id: string;
  emoji: string;
  name: string;
  reward: number;  // 领取奖励的鸡蛋币
}

export const DAILY_TASK_DEFS: DailyTaskDef[] = [
  { id: 'bill', emoji: '📝', name: '记一笔账', reward: 10 },
  { id: 'deposit', emoji: '🐷', name: '往存钱目标存一笔', reward: 10 },
  { id: 'feed', emoji: '🌾', name: '喂小鸡一把米', reward: 5 },
  { id: 'visit_chick', emoji: '🐣', name: '去看看小鸡', reward: 5 }
];

export interface DailyTaskState {
  date: string;       // 任务归属日（本地日期 YYYY-MM-DD），跨天自动重置
  done: string[];     // 已完成的任务 id
  claimed: string[];  // 已领取奖励的任务 id
}

function todayString(): string {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

function emptyTaskState(): DailyTaskState {
  return { date: todayString(), done: [], claimed: [] };
}

// 读取每日任务状态；跨天自动重置并写回
export async function loadDailyTasks(context: common.UIAbilityContext): Promise<DailyTaskState> {
  let state = emptyTaskState();
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    const data = await prefs.get('daily_tasks', '') as string;
    if (data.length > 0) {
      const parsed = JSON.parse(data) as DailyTaskState;
      if (parsed.date === todayString()) {
        state = {
          date: parsed.date,
          done: parsed.done ? parsed.done : [],
          claimed: parsed.claimed ? parsed.claimed : []
        };
      }
    }
    await prefs.put('daily_tasks', JSON.stringify(state));
    await prefs.flush();
  } catch (e) {
    console.error('读取每日任务失败', e);
  }
  return state;
}

async function saveDailyTasks(context: common.UIAbilityContext, state: DailyTaskState): Promise<void> {
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    await prefs.put('daily_tasks', JSON.stringify(state));
    await prefs.flush();
  } catch (e) {
    console.error('保存每日任务失败', e);
  }
}

// 完成某项任务（重复标记无副作用），返回是否为今日首次完成
export async function markDailyTask(context: common.UIAbilityContext, taskId: string): Promise<boolean> {
  const state = await loadDailyTasks(context);
  if (state.done.indexOf(taskId) !== -1) {
    return false;
  }
  state.done.push(taskId);
  await saveDailyTasks(context, state);
  return true;
}

// 领取任务奖励：完成且未领取时发放鸡蛋币，返回奖励数额；不可领取返回 -1
export async function claimDailyTask(context: common.UIAbilityContext, taskId: string): Promise<number> {
  const state = await loadDailyTasks(context);
  if (state.done.indexOf(taskId) === -1 || state.claimed.indexOf(taskId) !== -1) {
    return -1;
  }
  let reward = 0;
  for (const def of DAILY_TASK_DEFS) {
    if (def.id === taskId) {
      reward = def.reward;
      break;
    }
  }
  state.claimed.push(taskId);
  await saveDailyTasks(context, state);
  await addEggCoins(context, reward);
  return reward;
}

// ---------- 鸡窝场景（鸡蛋币装修小鸡的家，小鸡舞台整体换肤） ----------

export interface SceneDef {
  id: string;
  name: string;
  price: number;
  desc: string;
  image: Resource;  // 场景背景图（纯背景，小鸡叠加展示）
}

export const SCENE_DEFS: SceneDef[] = [
  { id: 'default', name: '草地鸡窝', price: 0, desc: '阳光洒在草地上', image: $r('app.media.scene_default') },
  { id: 'snow', name: '冬日雪原', price: 30, desc: '安静的落雪午后', image: $r('app.media.scene_snow') },
  { id: 'spring', name: '樱花庭院', price: 35, desc: '花瓣落在鸡窝上', image: $r('app.media.scene_spring') },
  { id: 'sunset', name: '黄昏农场', price: 40, desc: '金色余晖的傍晚', image: $r('app.media.scene_sunset') },
  { id: 'night', name: '星空月夜', price: 50, desc: '陪小鸡数星星', image: $r('app.media.scene_night') },
  { id: 'beach', name: '海边沙滩', price: 60, desc: '听海浪晒太阳', image: $r('app.media.scene_beach') },
  { id: 'golden', name: '黄金宫殿', price: 150, desc: '传说之鸡的排面', image: $r('app.media.scene_golden') }
];

export interface SceneState {
  owned: string[];   // 已拥有的场景 id
  using: string;     // 当前使用的场景 id
}

async function loadSceneStateRaw(context: common.UIAbilityContext): Promise<SceneState> {
  let state: SceneState = { owned: ['default'], using: 'default' };
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    const data = await prefs.get('scene_state', '') as string;
    if (data.length > 0) {
      const parsed = JSON.parse(data) as SceneState;
      const owned = parsed.owned ? parsed.owned : [];
      if (owned.indexOf('default') === -1) {
        owned.unshift('default');
      }
      state = { owned: owned, using: parsed.using ? parsed.using : 'default' };
    }
  } catch (e) {
    console.error('读取鸡窝场景失败', e);
  }
  return state;
}

export async function loadScenes(context: common.UIAbilityContext): Promise<SceneState> {
  return loadSceneStateRaw(context);
}

async function saveSceneState(context: common.UIAbilityContext, state: SceneState): Promise<void> {
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    await prefs.put('scene_state', JSON.stringify(state));
    await prefs.flush();
  } catch (e) {
    console.error('保存鸡窝场景失败', e);
  }
}

// 购买场景：鸡蛋币足够时扣币解锁，返回是否成功
export async function buyScene(context: common.UIAbilityContext, sceneId: string): Promise<boolean> {
  let price = 0;
  let exists = false;
  for (const def of SCENE_DEFS) {
    if (def.id === sceneId) {
      price = def.price;
      exists = true;
      break;
    }
  }
  if (!exists) {
    return false;
  }
  const state = await loadSceneStateRaw(context);
  if (state.owned.indexOf(sceneId) !== -1) {
    return false;
  }
  const coins = await loadEggCoins(context);
  if (coins < price) {
    return false;
  }
  await addEggCoins(context, -price);
  state.owned.push(sceneId);
  await saveSceneState(context, state);
  return true;
}

// 切换使用的场景
export async function useScene(context: common.UIAbilityContext, sceneId: string): Promise<void> {
  const state = await loadSceneStateRaw(context);
  if (state.owned.indexOf(sceneId) === -1) {
    return;
  }
  state.using = sceneId;
  await saveSceneState(context, state);
}

export function getSceneDef(sceneId: string): SceneDef {
  for (const def of SCENE_DEFS) {
    if (def.id === sceneId) {
      return def;
    }
  }
  return SCENE_DEFS[0];
}

// ---------- 愿望清单（30 天冷静期） ----------

export interface WishItem {
  id: number;
  name: string;
  price: number;
  createdAt: number;
  status: string;  // 'cooling' 冷静期 | 'want' 冷静期满还想买 | 'dropped' 已放下
}

export const WISH_COOLING_DAYS = 30;

export async function loadWishes(context: common.UIAbilityContext): Promise<WishItem[]> {
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    const data = await prefs.get('wish_list', '[]') as string;
    return JSON.parse(data) as WishItem[];
  } catch (e) {
    console.error('读取愿望清单失败', e);
    return [];
  }
}

export async function saveWishes(context: common.UIAbilityContext, wishes: WishItem[]): Promise<void> {
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    await prefs.put('wish_list', JSON.stringify(wishes));
    await prefs.flush();
  } catch (e) {
    console.error('保存愿望清单失败', e);
  }
}

// 冷静期剩余天数（0 表示已期满，该做决定了）
export function wishCoolingRemain(item: WishItem): number {
  const end = item.createdAt + WISH_COOLING_DAYS * 86400000;
  const remain = Math.ceil((end - Date.now()) / 86400000);
  return remain > 0 ? remain : 0;
}

// ---------- 52 周 / 30 天存钱挑战 ----------

export interface ChallengeTemplate {
  id: string;         // 'week52' | 'day30'
  emoji: string;
  name: string;
  desc: string;
  totalAmount: number;  // 全程累计金额
  periods: number;      // 总期数（52 周 / 30 天）
  firstAmount: number;  // 第 1 期应存金额
  step: number;         // 每期递增金额
  periodDays: number;   // 每期天数（7 / 1）
}

export const CHALLENGE_TEMPLATES: ChallengeTemplate[] = [
  {
    id: 'week52', emoji: '🗓️', name: '52周阶梯挑战',
    desc: '第1周存¥10，每周多存¥10',
    totalAmount: 13780, periods: 52, firstAmount: 10, step: 10, periodDays: 7
  },
  {
    id: 'day30', emoji: '⚡', name: '30天递增挑战',
    desc: '第1天存¥5，每天多存¥5',
    totalAmount: 4650, periods: 30, firstAmount: 5, step: 5, periodDays: 1
  }
];

export function getChallengeTemplate(id: string): ChallengeTemplate | null {
  for (const tpl of CHALLENGE_TEMPLATES) {
    if (tpl.id === id) {
      return tpl;
    }
  }
  return null;
}

// 当前应处于第几期（1 起，超期封顶到总期数）
export function getChallengeCurrentPeriod(tpl: ChallengeTemplate, startTs: number): number {
  const elapsedDays = Math.floor((Date.now() - startTs) / 86400000);
  const period = Math.floor(elapsedDays / tpl.periodDays) + 1;
  if (period < 1) {
    return 1;
  }
  return period > tpl.periods ? tpl.periods : period;
}

// 第 period 期应存金额
export function getChallengePeriodAmount(tpl: ChallengeTemplate, period: number): number {
  return tpl.firstAmount + tpl.step * (period - 1);
}

// 前 k 期的计划累计金额
export function getChallengePlannedTotal(tpl: ChallengeTemplate, k: number): number {
  const n = Math.min(k, tpl.periods);
  return Math.round((tpl.firstAmount * n + tpl.step * n * (n - 1) / 2) * 100) / 100;
}

// ---------- 幸运存钱罐：每笔记账随机掉金币，攒满开罐 ----------

export interface PiggyBankState {
  coins: number;     // 罐内金币
  capacity: number;  // 罐容量（攒满可开）
}

export const PIGGY_CAPACITY = 50;

export async function loadPiggyBank(context: common.UIAbilityContext): Promise<PiggyBankState> {
  let state: PiggyBankState = { coins: 0, capacity: PIGGY_CAPACITY };
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    const data = await prefs.get('piggy_bank', '') as string;
    if (data.length > 0) {
      const parsed = JSON.parse(data) as PiggyBankState;
      state = { coins: Math.max(0, parsed.coins ? parsed.coins : 0), capacity: PIGGY_CAPACITY };
    }
  } catch (e) {
    console.error('读取幸运存钱罐失败', e);
  }
  return state;
}

// 记账掉金币：随机 1~3 枚入罐（罐满不掉），返回入罐数量
export async function dropCoinsIntoPiggy(context: common.UIAbilityContext): Promise<number> {
  const state = await loadPiggyBank(context);
  if (state.coins >= state.capacity) {
    return 0;
  }
  const drop = Math.min(state.capacity - state.coins, 1 + Math.floor(Math.random() * 3));
  state.coins += drop;
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    await prefs.put('piggy_bank', JSON.stringify(state));
    await prefs.flush();
  } catch (e) {
    console.error('掉落金币失败', e);
    return 0;
  }
  return drop;
}

// 开罐：罐内有金币时全部转入鸡蛋币并清空，返回金额；空罐返回 -1
export async function openPiggyBank(context: common.UIAbilityContext): Promise<number> {
  const state = await loadPiggyBank(context);
  if (state.coins <= 0) {
    return -1;
  }
  const coins = state.coins;
  state.coins = 0;
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    await prefs.put('piggy_bank', JSON.stringify(state));
    await prefs.flush();
  } catch (e) {
    console.error('开罐失败', e);
    return -1;
  }
  await addEggCoins(context, coins);
  return coins;
}

// ---------- 小鸡旅行：花鸡蛋币派小鸡出门，记账加速归期，回来领奖 ----------

export interface TravelDestination {
  id: string;
  emoji: string;
  name: string;
  desc: string;
  cost: number;      // 出发花费（鸡蛋币）
  hours: number;     // 基础行程时长
  minReward: number; // 归来随机奖励下限
  maxReward: number; // 归来随机奖励上限
  souvenir: string;  // 带回的纪念品
}

export const TRAVEL_DESTINATIONS: TravelDestination[] = [
  { id: 'hill', emoji: '🌿', name: '后山草地', desc: '12 小时短途游', cost: 15, hours: 12, minReward: 25, maxReward: 40, souvenir: '一根闪着微光的漂亮羽毛' },
  { id: 'market', emoji: '🏮', name: '热闹集市', desc: '24 小时赶集之旅', cost: 30, hours: 24, minReward: 50, maxReward: 80, souvenir: '一包香喷喷的零食小米' },
  { id: 'volcano', emoji: '🌋', name: '远方火山', desc: '48 小时传说之旅', cost: 60, hours: 48, minReward: 100, maxReward: 160, souvenir: '一枚暖烘烘的火山石' }
];

export const TRAVEL_BOOST_HOURS = 2; // 旅途中每记一笔账提前 N 小时

export interface TravelState {
  destId: string;
  startTs: number;
  endTs: number;        // 预计归来时间
  billsBoosted: number; // 旅途中记账加速次数
}

export function getTravelDestination(id: string): TravelDestination {
  for (const d of TRAVEL_DESTINATIONS) {
    if (d.id === id) {
      return d;
    }
  }
  return TRAVEL_DESTINATIONS[0];
}

export async function loadTravel(context: common.UIAbilityContext): Promise<TravelState | null> {
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    const data = await prefs.get('chick_travel', '') as string;
    if (data.length === 0) {
      return null;
    }
    return JSON.parse(data) as TravelState;
  } catch (e) {
    console.error('读取小鸡旅行失败', e);
    return null;
  }
}

async function saveTravel(context: common.UIAbilityContext, state: TravelState | null): Promise<void> {
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    await prefs.put('chick_travel', state === null ? '' : JSON.stringify(state));
    await prefs.flush();
  } catch (e) {
    console.error('保存小鸡旅行失败', e);
  }
}

// 出发：鸡蛋币足够时扣币开启旅程，返回是否成功
export async function startTravel(context: common.UIAbilityContext, destId: string): Promise<boolean> {
  const dest = getTravelDestination(destId);
  const coins = await loadEggCoins(context);
  if (coins < dest.cost) {
    return false;
  }
  const state: TravelState = {
    destId: dest.id,
    startTs: Date.now(),
    endTs: Date.now() + dest.hours * 3600000,
    billsBoosted: 0
  };
  await addEggCoins(context, -dest.cost);
  await saveTravel(context, state);
  return true;
}

// 记账加速：旅途中每笔记账提前 2 小时（不早于当前时间），返回是否加速成功
export async function boostTravel(context: common.UIAbilityContext): Promise<boolean> {
  const state = await loadTravel(context);
  if (state === null || state.endTs <= Date.now()) {
    return false;
  }
  state.endTs = Math.max(Date.now(), state.endTs - TRAVEL_BOOST_HOURS * 3600000);
  state.billsBoosted += 1;
  await saveTravel(context, state);
  return true;
}

// 旅行是否已到家
export function isTravelDone(state: TravelState): boolean {
  return Date.now() >= state.endTs;
}

// 迎接小鸡回家：发随机奖励并清空旅程，返回奖励金额；未到家返回 -1
export async function claimTravelReward(context: common.UIAbilityContext): Promise<number> {
  const state = await loadTravel(context);
  if (state === null || !isTravelDone(state)) {
    return -1;
  }
  const dest = getTravelDestination(state.destId);
  const reward = dest.minReward + Math.floor(Math.random() * (dest.maxReward - dest.minReward + 1));
  await addEggCoins(context, reward);
  await saveTravel(context, null);
  return reward;
}

// ---------- 每日鸡运签：每天一签，完成签上任务领好运奖励 ----------

export interface FortuneState {
  date: string;      // 抽签日 YYYY-MM-DD
  level: number;     // 0 平 | 1 小吉 | 2 中吉 | 3 大吉
  text: string;      // 签文
  billsDone: number; // 今日记账笔数
  claimed: boolean;
}

export const FORTUNE_LEVEL_NAMES: string[] = ['平', '小吉', '中吉', '大吉'];
export const FORTUNE_LEVEL_EMOJI: string[] = ['🍃', '🍀', '⭐', '🌈'];
export const FORTUNE_TASK_BILLS: number[] = [3, 2, 2, 1];  // 各档需记账笔数
export const FORTUNE_REWARDS: number[] = [5, 8, 12, 20];   // 各档奖励鸡蛋币
const FORTUNE_TEXTS: string[][] = [
  ['今天平平淡淡也是福，稳稳记账就很好', '不急不躁，小钱也是钱～'],
  ['今天有点小运气，适合盘一盘账本', '记两笔账，好运悄悄靠近'],
  ['财气不错，小金库今天有进账的征兆', '中吉之日，宜存钱宜开心'],
  ['大吉！金光护体，记账运 MAX', '传说中欧气满满的一天，冲！']
];

async function saveFortune(context: common.UIAbilityContext, state: FortuneState): Promise<void> {
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    await prefs.put('daily_fortune', JSON.stringify(state));
    await prefs.flush();
  } catch (e) {
    console.error('保存鸡运签失败', e);
  }
}

// 读取今日签（跨天自动作废返回 null）
export async function loadFortune(context: common.UIAbilityContext): Promise<FortuneState | null> {
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    const data = await prefs.get('daily_fortune', '') as string;
    if (data.length === 0) {
      return null;
    }
    const parsed = JSON.parse(data) as FortuneState;
    if (parsed.date !== todayString()) {
      return null;
    }
    return parsed;
  } catch (e) {
    console.error('读取鸡运签失败', e);
    return null;
  }
}

// 抽签：今日未抽则随机一签（大吉 10% / 中吉 25% / 小吉 40% / 平 25%），返回今日签
export async function drawFortune(context: common.UIAbilityContext): Promise<FortuneState> {
  const existing = await loadFortune(context);
  if (existing !== null) {
    return existing;
  }
  const r = Math.random();
  const level = r < 0.10 ? 3 : (r < 0.35 ? 2 : (r < 0.75 ? 1 : 0));
  const texts = FORTUNE_TEXTS[level];
  const state: FortuneState = {
    date: todayString(),
    level: level,
    text: texts[Math.floor(Math.random() * texts.length)],
    billsDone: 0,
    claimed: false
  };
  await saveFortune(context, state);
  return state;
}

// 记账推进签上任务：今日已抽签且未领奖时计数 +1
export async function trackFortuneBill(context: common.UIAbilityContext): Promise<void> {
  const state = await loadFortune(context);
  if (state === null || state.claimed) {
    return;
  }
  state.billsDone += 1;
  await saveFortune(context, state);
}

// 领取好运奖励：任务完成且未领取时发放，返回奖励；否则 -1
export async function claimFortuneReward(context: common.UIAbilityContext): Promise<number> {
  const state = await loadFortune(context);
  if (state === null || state.claimed || state.billsDone < FORTUNE_TASK_BILLS[state.level]) {
    return -1;
  }
  state.claimed = true;
  await saveFortune(context, state);
  const reward = FORTUNE_REWARDS[state.level];
  await addEggCoins(context, reward);
  return reward;
}

// ---------- 月度小鸡报告：小鸡总结当月收支习惯 ----------

export interface ReportBillInput {
  amount: number;
  type: string;    // '收入' | '支出'
  date: number;
  category: string;
}

export interface MonthlyReportData {
  monthLabel: string;        // 如 '2026年9月'
  billCount: number;
  expenseTotal: number;
  incomeTotal: number;
  savedAmount: number;       // 收入 - 支出
  topCategory: string;
  topCategoryAmount: number;
  expenseChangePct: number;  // 支出环比上月（%），上月无数据为 0
  comments: string[];        // 小鸡评语
}

function isSameMonth(ts: number, year: number, month: number): boolean {
  const d = new Date(ts);
  return d.getFullYear() === year && d.getMonth() === month;
}

export function buildMonthlyReport(bills: ReportBillInput[]): MonthlyReportData {
  const now = new Date();
  const year = now.getFullYear();
  const month = now.getMonth();
  let billCount = 0;
  let expenseTotal = 0;
  let incomeTotal = 0;
  const categoryNames: string[] = [];
  const categoryAmounts: number[] = [];
  for (const b of bills) {
    if (!isSameMonth(b.date, year, month)) {
      continue;
    }
    billCount++;
    if (b.type === '收入') {
      incomeTotal += b.amount;
    } else if (b.type === '支出') {
      expenseTotal += b.amount;
      const idx = categoryNames.indexOf(b.category);
      if (idx === -1) {
        categoryNames.push(b.category);
        categoryAmounts.push(b.amount);
      } else {
        categoryAmounts[idx] += b.amount;
      }
    }
  }
  // 上月支出（环比）
  const last = new Date(year, month - 1, 1);
  let lastExpense = 0;
  for (const b of bills) {
    if (b.type === '支出' && isSameMonth(b.date, last.getFullYear(), last.getMonth())) {
      lastExpense += b.amount;
    }
  }
  let topCategory = '';
  let topCategoryAmount = 0;
  for (let i = 0; i < categoryNames.length; i++) {
    if (categoryAmounts[i] > topCategoryAmount) {
      topCategoryAmount = categoryAmounts[i];
      topCategory = categoryNames[i];
    }
  }
  let expenseChangePct = 0;
  if (lastExpense > 0 && expenseTotal > 0) {
    expenseChangePct = Math.round((expenseTotal - lastExpense) / lastExpense * 100);
  }
  expenseTotal = Math.round(expenseTotal * 100) / 100;
  incomeTotal = Math.round(incomeTotal * 100) / 100;
  const savedAmount = Math.round((incomeTotal - expenseTotal) * 100) / 100;
  // 小鸡评语
  const comments: string[] = [];
  if (billCount === 0) {
    comments.push('这个月还没记过账，小鸡都替你着急啦');
    comments.push('从今天开始记一笔，改变从一本账开始');
  } else {
    if (topCategory.length > 0) {
      const ratio = expenseTotal > 0 ? topCategoryAmount / expenseTotal : 0;
      if (ratio >= 0.4) {
        comments.push(`「${topCategory}」花掉 ¥${topCategoryAmount.toFixed(0)}，占支出 ${(ratio * 100).toFixed(0)}%，有点上头哦`);
      } else {
        comments.push(`花得最多的是「${topCategory}」，共 ¥${topCategoryAmount.toFixed(0)}`);
      }
    }
    if (savedAmount > 0) {
      comments.push(`这个月存下了 ¥${savedAmount.toFixed(0)}，小鸡为你骄傲！`);
    } else if (savedAmount < 0) {
      comments.push('这个月花得比赚得多，钱包在喊救命…');
    }
    if (expenseChangePct >= 20) {
      comments.push(`支出比上月多了 ${expenseChangePct}%，要看好小金库呀`);
    } else if (expenseChangePct <= -20) {
      comments.push(`支出比上月省了 ${-expenseChangePct}%，太会过日子了！`);
    }
    if (billCount >= 30) {
      comments.push(`这个月记了 ${billCount} 笔账，你是小鸡的榜样！`);
    }
  }
  if (comments.length === 0) {
    comments.push('平平稳稳的一个月，继续保持呀');
  }
  return {
    monthLabel: `${year}年${month + 1}月`,
    billCount: billCount,
    expenseTotal: expenseTotal,
    incomeTotal: incomeTotal,
    savedAmount: savedAmount,
    topCategory: topCategory,
    topCategoryAmount: Math.round(topCategoryAmount * 100) / 100,
    expenseChangePct: expenseChangePct,
    comments: comments
  };
}

// ---------- 新手引导 ----------

// 引导介绍页（首次启动展示）是否已看过
export async function isGuideIntroDone(context: common.UIAbilityContext): Promise<boolean> {
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    return await prefs.get('guide_intro_done', false) as boolean;
  } catch (e) {
    return false;
  }
}

export async function setGuideIntroDone(context: common.UIAbilityContext): Promise<void> {
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    await prefs.put('guide_intro_done', true);
    await prefs.flush();
  } catch (e) {
    console.error('保存引导介绍页状态失败', e);
  }
}

// 新手引导是否已完成（决定礼包与「初来乍到」成就）
export async function isGuideDone(context: common.UIAbilityContext): Promise<boolean> {
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    return await prefs.get('guide_done', false) as boolean;
  } catch (e) {
    return false;
  }
}

// 完成引导：落库 + 发放新手礼包（鸡蛋币 +50、樱花庭院场景解锁）
export async function finishGuide(context: common.UIAbilityContext): Promise<void> {
  try {
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    await prefs.put('guide_done', true);
    await prefs.flush();
  } catch (e) {
    console.error('保存引导状态失败', e);
  }
  await addEggCoins(context, 50);
  const sceneState = await loadSceneStateRaw(context);
  if (sceneState.owned.indexOf('spring') === -1) {
    sceneState.owned.push('spring');
    await saveSceneState(context, sceneState);
  }
}
