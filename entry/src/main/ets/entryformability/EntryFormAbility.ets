import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { common } from '@kit.AbilityKit';
import dataPreferences from '@ohos.data.preferences';

const FORM_IDS_KEY: string = 'widget_form_ids';
const DEFAULT_LEDGER_ID: number = 1;

interface WidgetBill {
  amount: number;
  type: string;
  date: number;
  ledgerId?: number;
}

// 汇总卡片展示数据：今日支出 / 本月支出 / 预算进度（口径与主应用一致：当前账本）
export function buildCardData(context: common.Context): Record<string, string | number | boolean> {
  const data: Record<string, string | number | boolean> = {
    'todayExpense': '0.00',
    'monthExpense': '0.00',
    'hasBudget': false,
    'budgetUsedPercent': 0,
    'budgetLeftText': '',
    'budgetAmountText': '',
    'budgetPercentText': '0%',
    'budgetLevel': 0
  };
  try {
    const prefs = dataPreferences.getPreferencesSync(context, { name: 'bill_data' });
    const raw = prefs.getSync('bills_key', '[]') as string;
    const bills = JSON.parse(raw) as WidgetBill[];

    let ledgerId = DEFAULT_LEDGER_ID;
    const curId = prefs.getSync('current_ledger_id', '') as string;
    if (curId.length > 0) {
      const parsedId = parseInt(curId);
      if (!isNaN(parsedId) && parsedId > 0) {
        ledgerId = parsedId;
      }
    }

    const now = new Date();
    const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
    const monthStart = new Date(now.getFullYear(), now.getMonth(), 1).getTime();
    let todayTotal = 0;
    let monthTotal = 0;
    bills.forEach((bill: WidgetBill) => {
      if (bill.type !== '支出') {
        return;
      }
      const billLedger = bill.ledgerId !== undefined ? bill.ledgerId : DEFAULT_LEDGER_ID;
      if (billLedger !== ledgerId) {
        return;
      }
      if (bill.date >= todayStart) {
        todayTotal += bill.amount;
      }
      if (bill.date >= monthStart) {
        monthTotal += bill.amount;
      }
    });
    data['todayExpense'] = todayTotal.toFixed(2);
    data['monthExpense'] = monthTotal.toFixed(2);

    const ym = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
    const budgetRaw = prefs.getSync('budget', '') as string;
    if (budgetRaw.length > 0) {
      const parsedBudget = JSON.parse(budgetRaw) as Record<string, number>;
      let value: number | undefined = parsedBudget[`${ledgerId}:${ym}`];
      if (value === undefined && ledgerId === DEFAULT_LEDGER_ID) {
        value = parsedBudget[ym];
      }
      if (value !== undefined && value > 0) {
        data['hasBudget'] = true;
        const percentRaw = Math.floor((monthTotal / value) * 100);
        let percent = percentRaw;
        if (percent > 100) {
          percent = 100;
        }
        if (percent < 0) {
          percent = 0;
        }
        data['budgetUsedPercent'] = percent;
        data['budgetPercentText'] = `${percentRaw}%`;
        data['budgetAmountText'] = `¥${value.toFixed(0)}`;
        data['budgetLevel'] = monthTotal > value ? 2 : (percentRaw >= 80 ? 1 : 0);
        const left = value - monthTotal;
        data['budgetLeftText'] = left >= 0 ? `预算剩余 ¥${left.toFixed(2)}` : `已超支 ¥${(-left).toFixed(2)}`;
      }
    }
  } catch (e) {
    console.error('构建卡片数据失败: ' + JSON.stringify(e));
  }
  return data;
}

// 主应用数据变更后调用：刷新所有已添加的桌面卡片
export async function updateAllWidgetCards(context: common.Context): Promise<void> {
  try {
    const prefs = dataPreferences.getPreferencesSync(context, { name: 'bill_data' });
    const raw = prefs.getSync(FORM_IDS_KEY, '[]') as string;
    const ids = JSON.parse(raw) as string[];
    if (ids.length === 0) {
      return;
    }
    const data = buildCardData(context);
    for (let i = 0; i < ids.length; i++) {
      try {
        await formProvider.updateForm(ids[i], formBindingData.createFormBindingData(data));
      } catch (e) {
        console.error('更新单个卡片失败: ' + JSON.stringify(e));
      }
    }
  } catch (e) {
    console.error('更新桌面卡片失败: ' + JSON.stringify(e));
  }
}

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const formId: string = (want.parameters?.[formInfo.FormParam.IDENTITY_KEY] ?? '') as string;
    if (formId.length > 0) {
      this.saveFormId(formId);
    }
    return formBindingData.createFormBindingData(buildCardData(this.context));
  }

  onRemoveForm(formId: string): void {
    if (formId.length > 0) {
      this.removeFormId(formId);
    }
  }

  onUpdateForm(formId: string): void {
    const data = buildCardData(this.context);
    formProvider.updateForm(formId, formBindingData.createFormBindingData(data)).catch(() => {});
  }

  saveFormId(formId: string): void {
    try {
      const prefs = dataPreferences.getPreferencesSync(this.context, { name: 'bill_data' });
      const raw = prefs.getSync(FORM_IDS_KEY, '[]') as string;
      const ids = JSON.parse(raw) as string[];
      if (!ids.includes(formId)) {
        ids.push(formId);
        prefs.putSync(FORM_IDS_KEY, JSON.stringify(ids));
        prefs.flushSync();
      }
    } catch (e) {
      console.error('保存卡片ID失败: ' + JSON.stringify(e));
    }
  }

  removeFormId(formId: string): void {
    try {
      const prefs = dataPreferences.getPreferencesSync(this.context, { name: 'bill_data' });
      const raw = prefs.getSync(FORM_IDS_KEY, '[]') as string;
      const ids = JSON.parse(raw) as string[];
      const rest = ids.filter((id: string) => id !== formId);
      if (rest.length !== ids.length) {
        prefs.putSync(FORM_IDS_KEY, JSON.stringify(rest));
        prefs.flushSync();
      }
    } catch (e) {
      console.error('移除卡片ID失败: ' + JSON.stringify(e));
    }
  }
}
