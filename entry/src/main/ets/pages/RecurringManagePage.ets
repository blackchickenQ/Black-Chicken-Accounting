// pages/RecurringManagePage.ets
import dataPreferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import {
  RecurringBill,
  LedgerItem,
  DEFAULT_LEDGER_ID,
  CATEGORIES,
  AnimationConfig
} from './Index';
import { MotionCurves } from '../common/Motion';

const WEEK_LABELS: string[] = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
const FREQ_LABELS: string[] = ['每周', '每月', '每年'];
const DAY_NUMBERS: number[] = [];
for (let i = 1; i <= 31; i++) {
  DAY_NUMBERS.push(i);
}
const MONTH_NUMBERS: number[] = [];
for (let i = 1; i <= 12; i++) {
  MONTH_NUMBERS.push(i);
}

function formatDay(ts: number): string {
  const d = new Date(ts);
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  return `${d.getFullYear()}-${mm}-${dd}`;
}

function freqText(rule: RecurringBill): string {
  if (rule.freqType === 'weekly') {
    return `每${WEEK_LABELS[rule.dayOfWeek - 1]}`;
  }
  if (rule.freqType === 'monthly') {
    return `每月${rule.dayOfMonth}号`;
  }
  return `每年${rule.monthOfYear}月${rule.dayOfMonth}号`;
}

// ========== 周期账单编辑弹窗（新建/编辑共用） ==========
@CustomDialog
struct RecurringEditDialog {
  @StorageProp('brand_main') brandMain: string = '#4E6EF2';
  controller: CustomDialogController = new CustomDialogController({
    builder: () => {}
  });
  title: string = '新建周期账单';
  paramRule: RecurringBill | null = null;
  paramLedgers: LedgerItem[] = [];
  @State name: string = '';
  @State amountText: string = '';
  @State billType: '收入' | '支出' = '支出';
  @State freqType: 'weekly' | 'monthly' | 'yearly' = 'monthly';
  @State dayOfWeek: number = 1;
  @State dayOfMonth: number = 1;
  @State monthOfYear: number = 1;
  @State category: string = CATEGORIES[0];
  @State source: string = '';
  @State ledgerId: number = DEFAULT_LEDGER_ID;
  @State startDate: number = 0;
  editingId: number = 0;
  editingCreatedAt: number = 0;
  paramEnabled: boolean = true;
  onConfirm: (rule: RecurringBill) => void = () => {};

  aboutToAppear() {
    const now = new Date();
    this.dayOfWeek = now.getDay() === 0 ? 7 : now.getDay();
    this.dayOfMonth = now.getDate();
    this.monthOfYear = now.getMonth() + 1;
    this.startDate = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
    if (this.paramRule !== null) {
      const rule = this.paramRule;
      this.name = rule.name;
      this.amountText = rule.amount.toString();
      this.billType = rule.type;
      this.freqType = rule.freqType;
      this.dayOfWeek = rule.dayOfWeek;
      this.dayOfMonth = rule.dayOfMonth;
      this.monthOfYear = rule.monthOfYear;
      this.category = rule.category;
      this.source = rule.source;
      this.ledgerId = rule.ledgerId;
      this.startDate = rule.startDate;
      this.editingId = rule.id;
      this.editingCreatedAt = rule.createdAt;
      this.paramEnabled = rule.enabled;
    }
  }

  pickStartDate() {
    this.getUIContext().showDatePickerDialog({
      start: new Date(2000, 0, 1),
      end: new Date(2100, 11, 31),
      selected: new Date(this.startDate),
      onDateAccept: (value: Date) => {
        this.startDate = new Date(value.getFullYear(), value.getMonth(), value.getDate()).getTime();
      }
    });
  }

  @Builder
  ChipLabel(label: string) {
    Text(label)
      .fontSize(14)
      .fontColor($r('app.color.text_secondary'))
      .width('100%')
      .margin({ bottom: 8 })
  }

  // 无参 @Builder：直接读 this.dayOfMonth，状态变化可正常刷新（带参按值传递不会刷新）
  @Builder
  DayChips() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
      ForEach(DAY_NUMBERS, (day: number) => {
        Text(day.toString() + '号')
          .fontSize(13)
          .fontColor(this.dayOfMonth === day ? this.brandMain : $r('app.color.text_secondary'))
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(8)
          .backgroundColor(this.dayOfMonth === day ? $r('app.color.category_btn_bg') : Color.Transparent)
          .margin({ right: 6, bottom: 6 })
          .onClick(() => {
            animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
              this.dayOfMonth = day;
            });
          })
      }, (day: number) => day.toString() + this.dayOfMonth.toString())
    }
    .width('100%')
  }

  build() {
    Column() {
      Text(this.title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .alignSelf(ItemAlign.Start)
        .margin({ bottom: 16 })

      Scroll() {
        Column() {
          // 名称
          TextInput({ placeholder: '名称（如：房租、工资）', text: this.name })
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(12)
            .border({ width: 1, color: $r('app.color.border_color') })
            .padding({ left: 16, right: 16 })
            .height(44)
            .fontSize(15)
            .width('100%')
            .onChange((val: string) => { this.name = val; })
            .margin({ bottom: 14 })

          // 金额
          TextInput({ placeholder: '金额', text: this.amountText })
            .type(InputType.NUMBER_DECIMAL)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(12)
            .border({ width: 1, color: $r('app.color.border_color') })
            .padding({ left: 16, right: 16 })
            .height(44)
            .fontSize(15)
            .width('100%')
            .onChange((val: string) => { this.amountText = val; })
            .margin({ bottom: 14 })

          // 类型
          this.ChipLabel('类型')
          Row() {
            ForEach(['支出', '收入'] as ('收入' | '支出')[], (t: '收入' | '支出') => {
              Text(t)
                .fontSize(13)
                .fontColor(this.billType === t ? this.brandMain : $r('app.color.text_secondary'))
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .borderRadius(8)
                .backgroundColor(this.billType === t ? $r('app.color.category_btn_bg') : Color.Transparent)
                .margin({ right: 8 })
                .onClick(() => {
                  animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
                    this.billType = t;
                  });
                })
            }, (t: string) => t + this.billType)
          }
          .margin({ bottom: 14 })

          // 周期类型
          this.ChipLabel('重复频率')
          Row() {
            ForEach(['weekly', 'monthly', 'yearly'] as ('weekly' | 'monthly' | 'yearly')[], (f: 'weekly' | 'monthly' | 'yearly', idx: number) => {
              Text(FREQ_LABELS[idx])
                .fontSize(13)
                .fontColor(this.freqType === f ? this.brandMain : $r('app.color.text_secondary'))
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .borderRadius(8)
                .backgroundColor(this.freqType === f ? $r('app.color.category_btn_bg') : Color.Transparent)
                .margin({ right: 8 })
                .onClick(() => {
                  animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
                    this.freqType = f;
                  });
                })
            }, (f: string) => f + this.freqType)
          }
          .margin({ bottom: 14 })

          // 重复日
          if (this.freqType === 'weekly') {
            this.ChipLabel('重复日')
            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
              ForEach(WEEK_LABELS, (label: string, idx: number) => {
                Text(label)
                  .fontSize(13)
                  .fontColor(this.dayOfWeek === idx + 1 ? this.brandMain : $r('app.color.text_secondary'))
                  .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                  .borderRadius(8)
                  .backgroundColor(this.dayOfWeek === idx + 1 ? $r('app.color.category_btn_bg') : Color.Transparent)
                  .margin({ right: 6, bottom: 6 })
                  .onClick(() => {
                    animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
                      this.dayOfWeek = idx + 1;
                    });
                  })
              }, (label: string) => label + this.dayOfWeek.toString())
            }
            .width('100%')
            .margin({ bottom: 14 })
          } else if (this.freqType === 'monthly') {
            this.ChipLabel('每月几号')
            Row() {
              this.DayChips()
            }
            .margin({ bottom: 14 })
          } else {
            this.ChipLabel('每年几月')
            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
              ForEach(MONTH_NUMBERS, (m: number) => {
                Text(m.toString() + '月')
                  .fontSize(13)
                  .fontColor(this.monthOfYear === m ? this.brandMain : $r('app.color.text_secondary'))
                  .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                  .borderRadius(8)
                  .backgroundColor(this.monthOfYear === m ? $r('app.color.category_btn_bg') : Color.Transparent)
                  .margin({ right: 6, bottom: 6 })
                  .onClick(() => {
                    animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
                      this.monthOfYear = m;
                    });
                  })
              }, (m: number) => m.toString() + this.monthOfYear.toString())
            }
            .width('100%')
            .margin({ bottom: 14 })

            this.ChipLabel('几号')
            Row() {
              this.DayChips()
            }
            .margin({ bottom: 14 })
          }

          // 分类
          this.ChipLabel('分类')
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
            ForEach(CATEGORIES, (c: string) => {
              Text(c)
                .fontSize(13)
                .fontColor(this.category === c ? this.brandMain : $r('app.color.text_secondary'))
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .borderRadius(8)
                .backgroundColor(this.category === c ? $r('app.color.category_btn_bg') : Color.Transparent)
                .margin({ right: 8, bottom: 6 })
                .onClick(() => {
                  animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
                    this.category = c;
                  });
                })
            }, (c: string) => c + this.category)
          }
          .width('100%')
          .margin({ bottom: 14 })

          // 来源
          TextInput({ placeholder: '来源（选填，如：支付宝）', text: this.source })
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(12)
            .border({ width: 1, color: $r('app.color.border_color') })
            .padding({ left: 16, right: 16 })
            .height(44)
            .fontSize(15)
            .width('100%')
            .onChange((val: string) => { this.source = val; })
            .margin({ bottom: 14 })

          // 账本
          this.ChipLabel('账本')
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
            ForEach(this.paramLedgers, (ledger: LedgerItem) => {
              Text(ledger.name)
                .fontSize(13)
                .fontColor(this.ledgerId === ledger.id ? this.brandMain : $r('app.color.text_secondary'))
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .borderRadius(8)
                .backgroundColor(this.ledgerId === ledger.id ? $r('app.color.category_btn_bg') : Color.Transparent)
                .margin({ right: 8, bottom: 6 })
                .onClick(() => {
                  animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
                    this.ledgerId = ledger.id;
                  });
                })
            }, (ledger: LedgerItem) => ledger.id.toString() + this.ledgerId.toString())
          }
          .width('100%')
          .margin({ bottom: 14 })

          // 开始日期
          this.ChipLabel('开始日期')
          Row() {
            Text(formatDay(this.startDate))
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
            Blank()
            SymbolGlyph($r('sys.symbol.calendar'))
              .fontSize(18)
              .fontColor([this.brandMain])
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .borderRadius(12)
          .border({ width: 1, color: $r('app.color.border_color') })
          .onClick(() => { this.pickStartDate(); })
          .margin({ bottom: 18 })
        }
        .width('100%')
      }
      .constraintSize({ maxHeight: 520 })
      .width('100%')
      .margin({ bottom: 4 })

      // 按钮
      Row() {
        Button('取消')
          .backgroundColor('transparent')
          .fontColor($r('app.color.text_secondary'))
          .borderRadius(20)
          .height(40)
          .layoutWeight(1)
          .fontSize(15)
          .margin({ right: 8 })
          .onClick(() => { this.controller.close(); })

        Button('确定')
          .backgroundColor(this.brandMain)
          .fontColor($r('app.color.text_white'))
          .borderRadius(22)
          .height(44)
          .layoutWeight(1)
          .fontSize(15)
          .margin({ left: 8 })
          .onClick(() => {
            const trimmed = this.name.trim();
            const amount = Number(this.amountText);
            if (trimmed.length === 0) {
              this.getUIContext().getPromptAction().showToast({ message: '请输入名称', duration: 1500 });
              return;
            }
            if (!isFinite(amount) || amount <= 0) {
              this.getUIContext().getPromptAction().showToast({ message: '请输入正确的金额', duration: 1500 });
              return;
            }
            const source = this.source.trim();
            const rule: RecurringBill = {
              id: this.editingId !== 0 ? this.editingId : Date.now(),
              name: trimmed,
              amount: amount,
              type: this.billType,
              category: this.category,
              source: source.length > 0 ? source : '周期账单',
              freqType: this.freqType,
              dayOfWeek: this.dayOfWeek,
              dayOfMonth: this.dayOfMonth,
              monthOfYear: this.monthOfYear,
              startDate: this.startDate,
              endDate: 0,
              enabled: this.paramEnabled,
              ledgerId: this.ledgerId,
              createdAt: this.editingCreatedAt !== 0 ? this.editingCreatedAt : Date.now()
            };
            this.controller.close();
            this.onConfirm(rule);
          })
      }
      .width('100%')
    }
    .width('85%')
    .padding(20)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(24)
  }
}

@Component
struct RecurringManagePage {
  // 所在导航栈：由 NavDestination.onReady 注入
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('brand_main') brandMain: string = '#4E6EF2';
  @State rules: RecurringBill[] = [];
  @State ledgers: LedgerItem[] = [];
  @State pressedChipKey: string = '';
  private editDialogController: CustomDialogController | null = null;

  async aboutToAppear() {
    await this.loadData();
  }

  // ---------- 数据加载 ----------
  async loadData(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');

      const rulesData = await prefs.get('recurring_bills', '[]') as string;
      this.rules = JSON.parse(rulesData) as RecurringBill[];

      const ledgersData = await prefs.get('ledgers_key', '[]') as string;
      const parsed = JSON.parse(ledgersData) as LedgerItem[];
      if (parsed.length > 0) {
        this.ledgers = parsed;
      } else {
        this.ledgers = [{
          id: DEFAULT_LEDGER_ID,
          name: '默认账本',
          icon: 'book',
          color: '#45B7D1',
          categories: [...CATEGORIES],
          createdAt: 0,
          isDefault: true
        }];
      }
    } catch (e) {
      console.error('加载周期账单数据失败: ' + JSON.stringify(e));
    }
  }

  getLedgerName(id: number): string {
    const found = this.ledgers.find((item: LedgerItem) => item.id === id);
    return found !== undefined ? found.name : '默认账本';
  }

  // ---------- 保存规则列表 ----------
  async saveRules(rules: RecurringBill[]): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');
      await prefs.put('recurring_bills', JSON.stringify(rules));
      await prefs.flush();
      this.rules = rules;
      // 通知 Index 页面重新生成
      AppStorage.setOrCreate('shouldRefreshRecurring', Date.now());
    } catch (e) {
      console.error('保存周期账单规则失败: ' + JSON.stringify(e));
      this.getUIContext().getPromptAction().showToast({ message: '保存失败', duration: 1500 });
    }
  }

  // ---------- 新建 ----------
  openCreateDialog() {
    this.editDialogController = new CustomDialogController({
      builder: RecurringEditDialog({
        title: '新建周期账单',
        paramRule: null,
        paramLedgers: this.ledgers,
        onConfirm: (rule: RecurringBill) => {
          this.createRule(rule);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true,
      maskColor: 'rgba(0, 0, 0, 0.4)'
    });
    if (this.editDialogController) {
      this.editDialogController.open();
    }
  }

  async createRule(rule: RecurringBill): Promise<void> {
    await this.saveRules([...this.rules, rule]);
    this.getUIContext().getPromptAction().showToast({ message: '周期账单已创建', duration: 1200 });
  }

  // ---------- 编辑 ----------
  openEditDialog(rule: RecurringBill) {
    this.editDialogController = new CustomDialogController({
      builder: RecurringEditDialog({
        title: '编辑周期账单',
        paramRule: rule,
        paramLedgers: this.ledgers,
        onConfirm: (updated: RecurringBill) => {
          this.updateRule(updated);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true,
      maskColor: 'rgba(0, 0, 0, 0.4)'
    });
    if (this.editDialogController) {
      this.editDialogController.open();
    }
  }

  async updateRule(updated: RecurringBill): Promise<void> {
    const list = this.rules.map((item: RecurringBill) => {
      return item.id === updated.id ? updated : item;
    });
    await this.saveRules(list);
    this.getUIContext().getPromptAction().showToast({ message: '周期账单已更新', duration: 1200 });
  }

  // ---------- 开关 ----------
  async toggleRule(rule: RecurringBill, isOn: boolean): Promise<void> {
    const copy: RecurringBill = {
      id: rule.id,
      name: rule.name,
      amount: rule.amount,
      type: rule.type,
      category: rule.category,
      source: rule.source,
      freqType: rule.freqType,
      dayOfWeek: rule.dayOfWeek,
      dayOfMonth: rule.dayOfMonth,
      monthOfYear: rule.monthOfYear,
      startDate: rule.startDate,
      endDate: rule.endDate,
      enabled: isOn,
      ledgerId: rule.ledgerId,
      createdAt: rule.createdAt
    };
    await this.saveRules(this.rules.map((item: RecurringBill) => {
      return item.id === rule.id ? copy : item;
    }));
  }

  // ---------- 删除 ----------
  async deleteRule(rule: RecurringBill): Promise<void> {
    const result = await this.getUIContext().getPromptAction().showDialog({
      title: '确认删除',
      message: `删除「${rule.name}」后不再自动生成，已生成的账单会保留，确定吗？`,
      buttons: [
        { text: '取消', color: $r('app.color.text_secondary') },
        { text: '删除', color: $r('app.color.expense_red') }
      ]
    });
    if (result.index !== 1) {
      return;
    }
    await this.saveRules(this.rules.filter((item: RecurringBill) => item.id !== rule.id));
    this.getUIContext().getPromptAction().showToast({ message: '周期账单已删除', duration: 1200 });
  }

  // 宽屏断点（全局）：平板/折叠屏下内容限宽居中
  @StorageProp('isWideScreen') isWideScreen: boolean = false;

  // 全屏沉浸式布局：状态栏/手势条避让高度由 EntryAbility 发布到 AppStorage，页面据此留白避让
  @StorageProp('statusBarVp') statusBarVp: number = 46;
  @StorageProp('navBarVp') navBarVp: number = 28;

  build() {
    NavDestination() {
    Row() {
    Column() {
      // 标题栏
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_backward'))
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor([$r('app.color.text_primary')])
          .scale({ x: this.pressedChipKey === 'back' ? 0.8 : 1, y: this.pressedChipKey === 'back' ? 0.8 : 1 })
          .animation({ curve: MotionCurves.PRESS })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              this.pressedChipKey = 'back';
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.pressedChipKey = '';
            }
          })
          .onClick(() => {
            this.pathStack.pop();
          })
          .margin({ right: 8 })

        Text('周期账单')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(24)
          .fontColor([this.brandMain])
          .scale({ x: this.pressedChipKey === 'add' ? 0.8 : 1, y: this.pressedChipKey === 'add' ? 0.8 : 1 })
          .animation({ curve: MotionCurves.PRESS })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              this.pressedChipKey = 'add';
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.pressedChipKey = '';
            }
          })
          .onClick(() => { this.openCreateDialog(); })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: this.statusBarVp + 20, bottom: 16 })

      Divider()
        .color($r('app.color.border_color'))
        .height(1)

      // 规则列表
      if (this.rules.length === 0) {
        Column() {
          SymbolGlyph($r('sys.symbol.calendar_badge_clock'))
            .fontSize(40)
            .fontColor([$r('app.color.text_secondary')])
            .margin({ bottom: 12 })
          Text('暂无周期账单')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary'))
            .margin({ bottom: 6 })
          Text('添加后将在到期日自动生成账单')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.rules, (item: RecurringBill, index: number) => {
            ListItem() {
              Column() {
                Row() {
                  Column() {
                    SymbolGlyph($r('sys.symbol.calendar_badge_clock'))
                      .fontSize(24)
                      .fontColor([this.brandMain])
                  }
                  .width(44)
                  .height(44)
                  .borderRadius(22)
                  .backgroundColor('#4E6EF21A')
                  .justifyContent(FlexAlign.Center)
                  .alignItems(HorizontalAlign.Center)

                  Column() {
                    Row() {
                      Text(item.name)
                        .fontSize(17)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.text_primary'))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .layoutWeight(1)

                      Text((item.type === '收入' ? '+' : '-') + '¥' + item.amount.toFixed(2))
                        .fontSize(15)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(item.type === '收入' ? $r('app.color.income_gold') : $r('app.color.expense_red'))
                    }
                    .width('100%')

                    Text(`${freqText(item)} · ${item.category} · ${this.getLedgerName(item.ledgerId)} · 从 ${formatDay(item.startDate)} 起`)
                      .fontSize(13)
                      .fontColor($r('app.color.text_secondary'))
                      .margin({ top: 3 })
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  .margin({ left: 12 })

                  Toggle({ type: ToggleType.Switch, isOn: item.enabled })
                    .margin({ left: 8, right: 8 })
                    .onChange((isOn: boolean) => {
                      this.toggleRule(item, isOn);
                    })

                  Image($r('sys.media.ohos_ic_public_edit'))
                    .width(20)
                    .height(20)
                    .fillColor(this.brandMain)
                    .margin({ right: 12 })
                    .onClick(() => { this.openEditDialog(item); })

                  Image($r('sys.media.ohos_ic_public_remove'))
                    .width(20)
                    .height(20)
                    .fillColor($r('app.color.expense_red'))
                    .onClick(() => { this.deleteRule(item); })
                }
                .width('100%')
              }
              .width('100%')
              .padding(16)
              .backgroundColor($r('app.color.card_bg'))
              .borderRadius(16)
              .margin({ bottom: 12 })
              .transition(TransitionEffect.OPACITY
                .combine(TransitionEffect.scale({ x: 0.9, y: 0.9 }))
                .animation({ curve: AnimationConfig.SPRING }))
              .scale({ x: this.pressedChipKey === 'item_' + index ? 0.96 : 1, y: this.pressedChipKey === 'item_' + index ? 0.96 : 1 })
              .animation({ curve: MotionCurves.PRESS })
              .onTouch((event: TouchEvent) => {
                if (event.type === TouchType.Down) {
                  this.pressedChipKey = 'item_' + index;
                } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                  this.pressedChipKey = '';
                }
              })
            }
          }, (item: RecurringBill) => item.id.toString() + item.name + (item.enabled ? '1' : '0'))
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, top: 14 })
        .scrollBar(BarState.Off)
      }

      // 新建按钮
      Button('新建周期账单')
        .backgroundColor(this.brandMain)
        .fontColor($r('app.color.text_white'))
        .borderRadius(24)
        .height(48)
        .width('90%')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .margin({ bottom: this.navBarVp + 20 })
        .scale({ x: this.pressedChipKey === 'create' ? 0.94 : 1, y: this.pressedChipKey === 'create' ? 0.94 : 1 })
        .animation({ curve: MotionCurves.PRESS })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.pressedChipKey = 'create';
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.pressedChipKey = '';
          }
        })
        .onClick(() => { this.openCreateDialog(); })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_main'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .constraintSize({ maxWidth: this.isWideScreen ? 640 : '100%' })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.bg_main'))
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.bg_main'))
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
    })
  }

}

// 系统路由表（router_map.json）构建入口：导航栈按 name 路由到此页
@Builder
export function RecurringManagePageBuilder(name: string, param: object) {
  if (name === 'RecurringManagePage') {
    RecurringManagePage()
  }
}
