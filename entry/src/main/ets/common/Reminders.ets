// 应用内提醒中心：纯数据计算模块，不依赖 UI 与页面状态
// 提醒类型：信用账户还款日 / 预算执行 / 存钱目标停滞 / 存钱挑战每期存钱

import {
  ChallengeTemplate,
  getChallengeTemplate,
  getChallengeCurrentPeriod,
  getChallengePeriodAmount,
  getChallengePlannedTotal
} from './Gameplay';

// 信用账户（与财富页 credit_accounts 存储结构一致）
export interface ReminderCreditAccount {
  id: number;
  name: string;
  debt: number;
  dueDate: number;  // 还款日时间戳，0 = 未设置
}

// 存钱目标（与财富页 saving_goals 存储结构一致）
export interface ReminderSavingGoal {
  id: number;
  name: string;
  target: number;
  saved: number;
  deadline: number;  // 截止日时间戳，0 = 未设置
  challengeType?: string;    // 52周/30天挑战模板 id，普通目标无此字段
  challengeStart?: number;   // 挑战发起时间戳
  remindChallenge?: boolean; // 挑战目标：是否在提醒中心按每期（每天/每周）提醒
}

// 提醒计算输入（由页面侧从本地数据汇总）
export interface ReminderInput {
  monthExpenseByLedger: Record<string, number>;  // 账本ID → 本月支出合计
  ledgerNames: Record<string, string>;           // 账本ID → 账本名
  budgetMap: Record<string, number>;             // 预算键 `${ledgerId}:${yyyy-MM}`（旧版默认账本为 `${yyyy-MM}`）
  defaultLedgerId: number;
  creditAccounts: ReminderCreditAccount[];
  savingGoals: ReminderSavingGoal[];
  recentMonthlyBalance: number;                  // 近3个月平均结余（月均，<=0 视为攒钱停滞）
  dismissedKeys: Record<string, number>;         // 已删除（忽略）的提醒：key → 过期时间戳，过期后同条件会重新提醒
  readKeys: Record<string, number>;              // 已读的提醒：key → 已读时间戳，过期后同条件重新视为未读
  now: Date;
}

// 单条提醒
export interface ReminderItem {
  key: string;
  kind: string;   // 'credit' | 'budget' | 'goal'
  title: string;
  detail: string;
  level: number;  // 2 = 紧急(红) 1 = 提醒(橙)
  read?: boolean; // 是否已读（生成时由调用方按 readKeys 标记）
  targetLedgerId?: number; // budget 类提醒对应的账本ID（点击跳转用）
}

const DAY_MS = 24 * 60 * 60 * 1000;

export function buildReminders(input: ReminderInput): ReminderItem[] {
  const result: ReminderItem[] = [];
  const todayStart = new Date(input.now.getFullYear(), input.now.getMonth(), input.now.getDate()).getTime();

  // 1) 信用账户还款日：有欠款且还款日在3天内（或已逾期/就在今天）
  for (const acc of input.creditAccounts) {
    if (acc.debt <= 0 || acc.dueDate <= 0) {
      continue;
    }
    const daysLeft = Math.ceil((acc.dueDate - todayStart) / DAY_MS);
    if (daysLeft < 0) {
      result.push({
        key: `credit_overdue_${acc.id}_${acc.dueDate}`,
        kind: 'credit',
        level: 2,
        title: `${acc.name}还款已逾期`,
        detail: `欠款 ¥${acc.debt.toFixed(2)}，已逾期${-daysLeft}天，请尽快处理`
      });
    } else if (daysLeft === 0) {
      result.push({
        key: `credit_due_today_${acc.id}_${acc.dueDate}`,
        kind: 'credit',
        level: 2,
        title: `${acc.name}今天还款日`,
        detail: `欠款 ¥${acc.debt.toFixed(2)}，记得按时还款`
      });
    } else if (daysLeft <= 3) {
      result.push({
        key: `credit_soon_${acc.id}_${acc.dueDate}`,
        kind: 'credit',
        level: 1,
        title: `${acc.name}${daysLeft}天后还款`,
        detail: `欠款 ¥${acc.debt.toFixed(2)}，提前备好还款资金`
      });
    }
  }

  // 2) 预算执行（本月，逐账本）：>=100% 超支提醒，>=80% 接近上限提醒
  const ym = `${input.now.getFullYear()}-${String(input.now.getMonth() + 1).padStart(2, '0')}`;
  const ledgerIds = Object.keys(input.ledgerNames);
  for (const idStr of ledgerIds) {
    let budgetVal = input.budgetMap[`${idStr}:${ym}`];
    if (budgetVal === undefined && Number(idStr) === input.defaultLedgerId) {
      budgetVal = input.budgetMap[ym];
    }
    if (budgetVal === undefined || budgetVal <= 0) {
      continue;
    }
    const expense = input.monthExpenseByLedger[idStr];
    if (expense === undefined || expense <= 0) {
      continue;
    }
    const rate = expense / budgetVal * 100;
    const ledgerName = input.ledgerNames[idStr] ?? '账本';
    if (rate >= 100) {
      result.push({
        key: `budget_over_${idStr}_${ym}`,
        kind: 'budget',
        level: 2,
        targetLedgerId: Number(idStr),
        title: `${ledgerName}预算已超支`,
        detail: `本月已支出 ¥${expense.toFixed(2)}，超出预算 ¥${(expense - budgetVal).toFixed(2)}`
      });
    } else if (rate >= 80) {
      result.push({
        key: `budget_near_${idStr}_${ym}`,
        kind: 'budget',
        level: 1,
        targetLedgerId: Number(idStr),
        title: `${ledgerName}预算接近上限`,
        detail: `本月已用 ${rate.toFixed(0)}%（¥${expense.toFixed(2)} / ¥${budgetVal.toFixed(2)}）`
      });
    }
  }

  // 3) 存钱目标截止日：未完成且设了截止日期，7天内到期/当天/已过期提醒
  for (const g of input.savingGoals) {
    if (g.saved >= g.target || g.deadline <= 0) {
      continue;
    }
    const daysLeft = Math.ceil((g.deadline - todayStart) / DAY_MS);
    const remain = g.target - g.saved;
    if (daysLeft < 0) {
      result.push({
        key: `goal_deadline_over_${g.id}_${g.deadline}`,
        kind: 'goal',
        level: 2,
        title: `「${g.name}」已过截止日`,
        detail: `还差 ¥${remain.toFixed(2)} 未达成，可调整目标或延长期限`
      });
    } else if (daysLeft === 0) {
      result.push({
        key: `goal_deadline_today_${g.id}_${g.deadline}`,
        kind: 'goal',
        level: 2,
        title: `「${g.name}」今天截止`,
        detail: `还差 ¥${remain.toFixed(2)} 未达成`
      });
    } else if (daysLeft <= 7) {
      result.push({
        key: `goal_deadline_soon_${g.id}_${g.deadline}`,
        kind: 'goal',
        level: 1,
        title: `「${g.name}」${daysLeft}天后截止`,
        detail: `还差 ¥${remain.toFixed(2)}，抓紧攒钱`
      });
    }
  }

  // 4) 存钱目标：存在未完成目标但近3个月无结余，攒钱进度停滞
  const unfinishedGoals = input.savingGoals.filter((g: ReminderSavingGoal): boolean => g.saved < g.target);
  if (unfinishedGoals.length > 0 && input.recentMonthlyBalance <= 0) {
    result.push({
      key: `goal_stalled_${ym}`,
      kind: 'goal',
      level: 1,
      title: `${unfinishedGoals.length}个存钱目标进度停滞`,
      detail: '近3个月无结余，控制支出后才能继续攒钱'
    });
  }

  // 5) 存钱挑战每期存钱：开启「每期提醒」的挑战目标，本期计划未存够时提醒
  //    key 带期数，随挑战节奏（每天/每周）自然刷新为新提醒；存够或完成后不再提醒
  for (const g of input.savingGoals) {
    if (!g.challengeType || !g.challengeStart || !g.remindChallenge) {
      continue;
    }
    if (g.saved >= g.target) {
      continue;
    }
    const tpl: ChallengeTemplate | null = getChallengeTemplate(g.challengeType);
    if (tpl === null) {
      continue;
    }
    const period = getChallengeCurrentPeriod(tpl, g.challengeStart);
    const planned = getChallengePlannedTotal(tpl, period);
    if (g.saved >= planned) {
      continue;
    }
    const periodAmount = getChallengePeriodAmount(tpl, period);
    result.push({
      key: `challenge_${g.id}_${period}`,
      kind: 'goal',
      level: 1,
      title: `${tpl.name}：第 ${period} 期待存`,
      detail: `本期应存 ¥${periodAmount.toFixed(0)}，还差 ¥${(planned - g.saved).toFixed(0)} 追上计划`
    });
  }

  // 过滤已删除（未过忽略期）的提醒，并按已读记录标记
  const nowMs = input.now.getTime();
  const visible = result.filter((r: ReminderItem): boolean => {
    const expireAt = input.dismissedKeys[r.key];
    return expireAt === undefined || expireAt <= nowMs;
  });
  for (const r of visible) {
    r.read = input.readKeys[r.key] !== undefined;
  }
  visible.sort((a: ReminderItem, b: ReminderItem): number => b.level - a.level);
  return visible;
}
