// pages/WeeklyReportPage.ets 每周报告：本周总览 + 每日支出 + 分类排行 + 周环比变化 + 消费洞察

import dataPreferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import { getCategoryColor, AnimationConfig } from './Index';
import { MotionCurves } from '../common/Motion';

interface ReportBill {
  id: number;
  name: string;
  amount: number;
  type: string;
  date: number;
  category: string;
  ledgerId?: number;
}

interface CategoryStat {
  name: string;
  amount: number;
  percent: number;
  count: number;
}

interface CategoryDelta {
  name: string;
  current: number;
  previous: number;
  delta: number;
}

const DEFAULT_LEDGER_ID: number = 1;
const DAY_MS: number = 24 * 60 * 60 * 1000;
const DAY_LABELS: string[] = ['一', '二', '三', '四', '五', '六', '日'];

@Entry
@Component
struct WeeklyReportPage {
  @StorageProp('brand_main') brandMain: string = '#4E6EF2';
  @StorageProp('brand_light') brandLight: string = '#7B93FF';
  @StorageProp('brand_deep') brandDeep: string = '#3A55E0';
  @State weekOffset: number = 0;  // 0 = 本周，-1 = 上周，依次往前
  @State hasData: boolean = false;
  @State expenseTotal: number = 0;
  @State incomeTotal: number = 0;
  @State prevExpenseTotal: number = 0;
  @State billCount: number = 0;
  @State recordDays: number = 0;
  @State maxExpenseName: string = '';
  @State maxExpenseAmount: number = 0;
  @State categoryStats: CategoryStat[] = [];
  @State topIncreases: CategoryDelta[] = [];
  @State topDecreases: CategoryDelta[] = [];
  @State insights: string[] = [];
  @State dailyExpense: number[] = [0, 0, 0, 0, 0, 0, 0];
  @State maxDailyExpense: number = 0;
  @State maxDailyIndex: number = -1;
  @State todayIndex: number = -1;  // 本周时今天对应的下标（周一=0），其余周为 -1
  // 周切换动画状态：内容横向偏移与透明度
  @State contentShiftX: number = 40;
  @State contentAlpha: number = 0;
  // 按压回弹：当前按下目标的 key
  @State pressedChipKey: string = '';
  private weekSwitching: boolean = false;
  // 宽屏断点（全局）：平板/折叠屏下内容限宽居中
  @StorageProp('isWideScreen') isWideScreen: boolean = false;

  aboutToAppear() {
    this.loadReport();
    // 页面入场：内容随转场从右侧轻微滑入并淡入
    setTimeout(() => {
      this.getUIContext().animateTo({ duration: 320, curve: AnimationConfig.SPRING_SOFT }, () => {
        this.contentShiftX = 0;
        this.contentAlpha = 1;
      });
    }, 120);
  }

  // 以周一为一周开始，计算第 offset 周的周一 0 点
  getWeekStart(offset: number): Date {
    const now = new Date();
    const day = now.getDay();
    const diffToMonday = day === 0 ? -6 : 1 - day;
    return new Date(now.getFullYear(), now.getMonth(), now.getDate() + diffToMonday + offset * 7);
  }

  getWeekLabel(): string {
    const s = this.getWeekStart(this.weekOffset);
    const e = new Date(s.getFullYear(), s.getMonth(), s.getDate() + 6);
    const range = `${s.getMonth() + 1}月${s.getDate()}日 - ${e.getMonth() + 1}月${e.getDate()}日`;
    if (this.weekOffset === 0) {
      return `本周 ${range}`;
    }
    if (this.weekOffset === -1) {
      return `上周 ${range}`;
    }
    return range;
  }

  waitMs(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(resolve, ms);
    });
  }

  // 周切换：旧内容沿切换方向滑出，新内容从另一侧滑入
  async switchWeek(dir: number): Promise<void> {
    if (this.weekSwitching) {
      return;
    }
    this.weekSwitching = true;
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseIn }, () => {
      this.contentShiftX = -dir * 48;
      this.contentAlpha = 0;
    });
    await this.waitMs(190);
    this.weekOffset += dir;
    await this.loadReport();
    this.getUIContext().animateTo({ duration: 0 }, () => {
      this.contentShiftX = dir * 48;
    });
    await this.waitMs(30);
    this.getUIContext().animateTo({ duration: 320, curve: AnimationConfig.SPRING_SOFT }, () => {
      this.contentShiftX = 0;
      this.contentAlpha = 1;
    });
    this.weekSwitching = false;
  }

  goPrevWeek() {
    this.switchWeek(-1);
  }

  goNextWeek() {
    if (this.weekOffset === 0) {
      return;
    }
    this.switchWeek(1);
  }

  filterByWeek(bills: ReportBill[], ledgerId: number, startMs: number, endMs: number): ReportBill[] {
    return bills.filter((bill: ReportBill) => {
      const billLedger = bill.ledgerId !== undefined ? bill.ledgerId : DEFAULT_LEDGER_ID;
      if (billLedger !== ledgerId) {
        return false;
      }
      return bill.date >= startMs && bill.date < endMs;
    });
  }

  async loadReport(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');
      const raw = await prefs.get('bills_key', '[]') as string;
      const bills = JSON.parse(raw) as ReportBill[];

      let ledgerId = DEFAULT_LEDGER_ID;
      const curId = await prefs.get('current_ledger_id', '') as string;
      if (curId.length > 0) {
        const parsedId = parseInt(curId);
        if (!isNaN(parsedId) && parsedId > 0) {
          ledgerId = parsedId;
        }
      }

      const start = this.getWeekStart(this.weekOffset);
      const startMs = new Date(start.getFullYear(), start.getMonth(), start.getDate()).getTime();
      const endMs = startMs + 7 * DAY_MS;
      const curBills = this.filterByWeek(bills, ledgerId, startMs, endMs);
      const prevBills = this.filterByWeek(bills, ledgerId, startMs - 7 * DAY_MS, startMs);

      let curExpense = 0;
      let curIncome = 0;
      let prevExpense = 0;
      let maxExpense = 0;
      let maxExpenseName = '';
      const catAmount: Record<string, number> = {};
      const catCount: Record<string, number> = {};
      const daySet = new Set<number>();
      const daily: number[] = [0, 0, 0, 0, 0, 0, 0];
      curBills.forEach((bill: ReportBill) => {
        const d = new Date(bill.date);
        const dayIndex = Math.floor(
          (new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime() - startMs) / DAY_MS);
        daySet.add(dayIndex);
        if (bill.type === '支出') {
          curExpense += bill.amount;
          catAmount[bill.category] = (catAmount[bill.category] || 0) + bill.amount;
          catCount[bill.category] = (catCount[bill.category] || 0) + 1;
          if (dayIndex >= 0 && dayIndex < 7) {
            daily[dayIndex] += bill.amount;
          }
          if (bill.amount > maxExpense) {
            maxExpense = bill.amount;
            maxExpenseName = bill.name;
          }
        } else if (bill.type === '收入') {
          curIncome += bill.amount;
        }
      });
      const prevCatAmount: Record<string, number> = {};
      prevBills.forEach((bill: ReportBill) => {
        if (bill.type === '支出') {
          prevExpense += bill.amount;
          prevCatAmount[bill.category] = (prevCatAmount[bill.category] || 0) + bill.amount;
        }
      });

      this.expenseTotal = curExpense;
      this.incomeTotal = curIncome;
      this.prevExpenseTotal = prevExpense;
      this.billCount = curBills.length;
      this.recordDays = daySet.size;
      this.maxExpenseAmount = maxExpense;
      this.maxExpenseName = maxExpenseName;
      this.hasData = curBills.length > 0;
      this.dailyExpense = daily;
      let maxDaily = 0;
      let maxIdx = -1;
      for (let i = 0; i < 7; i++) {
        if (daily[i] > maxDaily) {
          maxDaily = daily[i];
          maxIdx = i;
        }
      }
      this.maxDailyExpense = maxDaily;
      this.maxDailyIndex = maxIdx;
      if (this.weekOffset === 0) {
        const now = new Date();
        this.todayIndex = (now.getDay() + 6) % 7;
      } else {
        this.todayIndex = -1;
      }

      const stats: CategoryStat[] = [];
      const catNames: string[] = Object.keys(catAmount);
      catNames.sort((a: string, b: string) => catAmount[b] - catAmount[a]);
      catNames.forEach((name: string) => {
        const amount = catAmount[name];
        const percent = curExpense > 0 ? Math.round((amount / curExpense) * 1000) / 10 : 0;
        stats.push({ name: name, amount: amount, percent: percent, count: catCount[name] || 0 });
      });
      this.categoryStats = stats;

      const allNames: string[] = [];
      const curNames: string[] = Object.keys(catAmount);
      const prevNames: string[] = Object.keys(prevCatAmount);
      curNames.forEach((n: string) => {
        if (!allNames.includes(n)) {
          allNames.push(n);
        }
      });
      prevNames.forEach((n: string) => {
        if (!allNames.includes(n)) {
          allNames.push(n);
        }
      });
      const deltas: CategoryDelta[] = [];
      allNames.forEach((n: string) => {
        const c = catAmount[n] || 0;
        const p = prevCatAmount[n] || 0;
        const delta = c - p;
        if (Math.abs(delta) > 0.005) {
          deltas.push({ name: n, current: c, previous: p, delta: delta });
        }
      });
      this.topIncreases = deltas.filter((d: CategoryDelta) => d.delta > 0)
        .sort((a: CategoryDelta, b: CategoryDelta) => b.delta - a.delta).slice(0, 3);
      this.topDecreases = deltas.filter((d: CategoryDelta) => d.delta < 0)
        .sort((a: CategoryDelta, b: CategoryDelta) => a.delta - b.delta).slice(0, 3);

      const tips: string[] = [];
      if (this.hasData && stats.length > 0) {
        const top = stats[0];
        tips.push(`「${top.name}」占本周支出的 ${top.percent.toFixed(1)}%，是最大开销`);
      }
      if (this.hasData) {
        if (this.prevExpenseTotal > 0) {
          const changePct = Math.abs((curExpense - prevExpense) / prevExpense * 100).toFixed(1);
          if (curExpense >= prevExpense) {
            tips.push(`支出较上周上涨 ${changePct}%`);
          } else {
            tips.push(`支出较上周下降 ${changePct}%`);
          }
        } else {
          tips.push('上周无支出记录，暂无环比参考');
        }
        if (this.maxDailyIndex >= 0) {
          tips.push(`周${DAY_LABELS[this.maxDailyIndex]}花得最多：¥${this.maxDailyExpense.toFixed(2)}`);
        }
        if (this.maxExpenseAmount > 0) {
          tips.push(`最大单笔支出：${this.maxExpenseName}（¥${this.maxExpenseAmount.toFixed(2)}）`);
        }
        tips.push(`本周记账 ${this.billCount} 笔，覆盖 ${this.recordDays} 天`);
      }
      this.insights = tips;
    } catch (e) {
      console.error('加载每周报告失败: ' + JSON.stringify(e));
    }
  }

  // 每日柱状图高度：按本周最大单日支出等比缩放，无支出显示为矮灰条
  dailyBarHeight(index: number): number {
    const val = this.dailyExpense[index];
    if (this.maxDailyExpense <= 0 || val <= 0) {
      return 4;
    }
    return Math.max(4, Math.round(val / this.maxDailyExpense * 72));
  }

  @Builder
  StatCell(label: string, value: string) {
    Column() {
      Text(label)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .margin({ bottom: 4 })
      Text(value)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
  }

  @Builder
  HeroStatCell(label: string, value: string) {
    Column() {
      Text(label)
        .fontSize(12)
        .fontColor('#CCFFFFFF')
        .margin({ bottom: 4 })
      Text(value)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_white'))
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
  }

  @Builder
  DailyBar(index: number) {
    Column() {
      Column()
        .width(18)
        .height(this.dailyBarHeight(index))
        .borderRadius(4)
        .backgroundColor(this.dailyExpense[index] > 0 ? this.brandMain : $r('app.color.border_color'))
      Text(DAY_LABELS[index])
        .fontSize(11)
        .fontColor(index === this.todayIndex ? this.brandMain : $r('app.color.text_secondary'))
        .fontWeight(index === this.todayIndex ? FontWeight.Medium : FontWeight.Normal)
        .margin({ top: 6 })
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.End)
    .alignItems(HorizontalAlign.Center)
  }

  // 全屏沉浸式布局：状态栏/手势条避让高度由 EntryAbility 发布到 AppStorage，页面据此留白避让
  @StorageProp('statusBarVp') statusBarVp: number = 46;
  @StorageProp('navBarVp') navBarVp: number = 28;

  build() {
    Row() {
    Column() {
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
            this.getUIContext().getRouter().back();
          })
          .margin({ right: 8 })

        Text('每周报告')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        Blank()
          .width(40)
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: this.statusBarVp + 20, bottom: 12 })

      Row() {
        SymbolGlyph($r('sys.symbol.chevron_backward'))
          .fontSize(20)
          .fontColor([this.brandMain])
          .scale({ x: this.pressedChipKey === 'prev' ? 0.8 : 1, y: this.pressedChipKey === 'prev' ? 0.8 : 1 })
          .animation({ curve: MotionCurves.PRESS })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              this.pressedChipKey = 'prev';
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.pressedChipKey = '';
            }
          })
          .onClick(() => {
            this.goPrevWeek();
          })
          .padding(8)

        Text(this.getWeekLabel())
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 8, right: 8 })

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(20)
          .fontColor(this.weekOffset === 0 ? [$r('app.color.border_color')] : [this.brandMain])
          .scale({ x: this.pressedChipKey === 'next' ? 0.8 : 1, y: this.pressedChipKey === 'next' ? 0.8 : 1 })
          .animation({ curve: MotionCurves.PRESS })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              this.pressedChipKey = 'next';
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.pressedChipKey = '';
            }
          })
          .onClick(() => {
            this.goNextWeek();
          })
          .padding(8)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .margin({ bottom: 8 })
      .translate({ x: this.contentShiftX })
      .opacity(this.contentAlpha)

      if (!this.hasData) {
        Column() {
          SymbolGlyph($r('sys.symbol.doc_plaintext'))
            .fontSize(48)
            .fontColor([$r('app.color.text_secondary')])
            .margin({ bottom: 16 })
          Text(`${this.getWeekLabel()}暂无账单记录`)
            .fontSize(16)
            .fontColor($r('app.color.text_secondary'))
          Text('记账后即可生成当周消费报告')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .width('100%')
        .translate({ x: this.contentShiftX })
        .opacity(this.contentAlpha)
      } else {
        Scroll() {
          Column() {
            Column() {
              Text('本周支出')
                .fontSize(13)
                .fontColor('#CCFFFFFF')
                .alignSelf(ItemAlign.Start)

              Text('¥' + this.expenseTotal.toFixed(2))
                .fontSize(34)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_white'))
                .alignSelf(ItemAlign.Start)
                .margin({ top: 4 })

              if (this.prevExpenseTotal > 0) {
                Text(this.expenseTotal >= this.prevExpenseTotal ?
                  `较上周 ¥${this.prevExpenseTotal.toFixed(2)} 上涨 ${Math.abs((this.expenseTotal - this.prevExpenseTotal) / this.prevExpenseTotal * 100).toFixed(1)}%` :
                  `较上周 ¥${this.prevExpenseTotal.toFixed(2)} 下降 ${Math.abs((this.expenseTotal - this.prevExpenseTotal) / this.prevExpenseTotal * 100).toFixed(1)}%`)
                  .fontSize(12)
                  .fontColor($r('app.color.text_white'))
                  .alignSelf(ItemAlign.Start)
                  .margin({ top: 4 })
              } else {
                Text('上周无支出，暂无环比')
                  .fontSize(12)
                  .fontColor('#CCFFFFFF')
                  .alignSelf(ItemAlign.Start)
                  .margin({ top: 4 })
              }

              Divider()
                .color($r('app.color.border_color'))
                .margin({ top: 14, bottom: 14 })

              Row() {
                this.HeroStatCell('本周收入', '¥' + this.incomeTotal.toFixed(2))
                this.HeroStatCell('本周结余', (this.incomeTotal - this.expenseTotal >= 0 ? '+' : '') + (this.incomeTotal - this.expenseTotal).toFixed(2))
                this.HeroStatCell('日均支出', '¥' + (this.recordDays > 0 ? (this.expenseTotal / this.recordDays).toFixed(2) : '0.00'))
              }
              .width('100%')
            }
            .width('100%')
            .padding(16)
            .backgroundColor($r('app.color.card_bg'))
            .linearGradient({
              angle: 135,
              colors: [[this.brandLight, 0], [this.brandMain, 0.55], [this.brandDeep, 1]]
            })
            .borderRadius(20)
            .margin({ bottom: 12 })

            Column() {
              Text('每日支出')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .alignSelf(ItemAlign.Start)
                .margin({ bottom: 12 })

              Row() {
                this.DailyBar(0)
                this.DailyBar(1)
                this.DailyBar(2)
                this.DailyBar(3)
                this.DailyBar(4)
                this.DailyBar(5)
                this.DailyBar(6)
              }
              .width('100%')
              .height(96)
              .alignItems(VerticalAlign.Bottom)
            }
            .width('100%')
            .padding(16)
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(16)
            .shadow({ radius: 12, color: $r('app.color.shadow_color'), offsetX: 0, offsetY: 4 })
            .margin({ bottom: 12 })

            Column() {
              Text('记账概况')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .alignSelf(ItemAlign.Start)
                .margin({ bottom: 10 })

              Row() {
                this.StatCell('记账笔数', `${this.billCount}`)
                this.StatCell('记账天数', `${this.recordDays}`)
                this.StatCell('最大单笔', this.maxExpenseAmount > 0 ? '¥' + this.maxExpenseAmount.toFixed(2) : '—')
              }
              .width('100%')

              if (this.maxExpenseAmount > 0) {
                Text(`最大单笔来自「${this.maxExpenseName}」`)
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .alignSelf(ItemAlign.Start)
                  .margin({ top: 8 })
              }
            }
            .width('100%')
            .padding(16)
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(16)
            .margin({ bottom: 12 })

            if (this.categoryStats.length > 0) {
              Column() {
                Text('分类排行')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                  .alignSelf(ItemAlign.Start)
                  .margin({ bottom: 12 })

                ForEach(this.categoryStats, (stat: CategoryStat, index: number) => {
                  Column() {
                    Row() {
                      Text(stat.name)
                        .fontSize(13)
                        .fontColor($r('app.color.text_primary'))
                        .width(72)

                      Column() {
                        Row() {
                        }
                        .height(8)
                        .width(`${Math.max(stat.percent, 2)}%`)
                        .backgroundColor(getCategoryColor(stat.name))
                        .borderRadius(4)
                      }
                      .layoutWeight(1)
                      .margin({ left: 8, right: 8 })

                      Text(`¥${stat.amount.toFixed(2)}`)
                        .fontSize(13)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.text_primary'))

                      Text(`${stat.percent.toFixed(1)}%`)
                        .fontSize(12)
                        .fontColor($r('app.color.text_secondary'))
                        .width(48)
                        .textAlign(TextAlign.End)
                    }
                    .width('100%')

                    if (index < this.categoryStats.length - 1) {
                      Divider()
                        .color($r('app.color.border_color'))
                        .margin({ top: 10, bottom: 10 })
                    }
                  }
                  .width('100%')
                }, (stat: CategoryStat) => stat.name + '_' + stat.amount.toString())
              }
              .width('100%')
              .padding(16)
              .backgroundColor($r('app.color.card_bg'))
              .borderRadius(16)
              .shadow({ radius: 12, color: $r('app.color.shadow_color'), offsetX: 0, offsetY: 4 })
              .margin({ bottom: 12 })
            }

            if (this.topIncreases.length > 0 || this.topDecreases.length > 0) {
              Column() {
                Text('较上周变化')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                  .alignSelf(ItemAlign.Start)
                  .margin({ bottom: 12 })

                if (this.topIncreases.length > 0) {
                  Text('支出增加')
                    .fontSize(12)
                    .fontColor($r('app.color.expense_red'))
                    .alignSelf(ItemAlign.Start)
                    .margin({ bottom: 6 })

                  ForEach(this.topIncreases, (item: CategoryDelta) => {
                    Row() {
                      Text(item.name)
                        .fontSize(13)
                        .fontColor($r('app.color.text_primary'))
                        .layoutWeight(1)
                      Text(`+¥${item.delta.toFixed(2)}`)
                        .fontSize(13)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.expense_red'))
                    }
                    .width('100%')
                    .padding({ top: 4, bottom: 4 })
                  }, (item: CategoryDelta) => 'up_' + item.name)

                  if (this.topDecreases.length > 0) {
                    Divider()
                      .color($r('app.color.border_color'))
                      .margin({ top: 8, bottom: 8 })
                  }
                }

                if (this.topDecreases.length > 0) {
                  Text('支出减少')
                    .fontSize(12)
                    .fontColor($r('app.color.success_green'))
                    .alignSelf(ItemAlign.Start)
                    .margin({ bottom: 6 })

                  ForEach(this.topDecreases, (item: CategoryDelta) => {
                    Row() {
                      Text(item.name)
                        .fontSize(13)
                        .fontColor($r('app.color.text_primary'))
                        .layoutWeight(1)
                      Text(`-¥${(-item.delta).toFixed(2)}`)
                        .fontSize(13)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.success_green'))
                    }
                    .width('100%')
                    .padding({ top: 4, bottom: 4 })
                  }, (item: CategoryDelta) => 'down_' + item.name)
                }
              }
              .width('100%')
              .padding(16)
              .backgroundColor($r('app.color.card_bg'))
              .borderRadius(16)
              .shadow({ radius: 12, color: $r('app.color.shadow_color'), offsetX: 0, offsetY: 4 })
              .margin({ bottom: 12 })
            }

            Column() {
              Text('消费洞察')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .alignSelf(ItemAlign.Start)
                .margin({ bottom: 10 })

              ForEach(this.insights, (tip: string) => {
                Row() {
                  Text('•')
                    .fontSize(13)
                    .fontColor(this.brandMain)
                    .margin({ right: 8 })
                  Text(tip)
                    .fontSize(13)
                    .fontColor($r('app.color.text_primary'))
                    .layoutWeight(1)
                }
                .width('100%')
                .alignItems(VerticalAlign.Top)
                .padding({ top: 3, bottom: 3 })
              }, (tip: string) => tip)
            }
            .width('100%')
            .padding(16)
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(16)
            .shadow({ radius: 12, color: $r('app.color.shadow_color'), offsetX: 0, offsetY: 4 })
            .margin({ bottom: 40 })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 4, bottom: this.navBarVp })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .align(Alignment.Center)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
        .translate({ x: this.contentShiftX })
        .opacity(this.contentAlpha)
      }
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

}
