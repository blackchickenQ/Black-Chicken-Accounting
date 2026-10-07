// pages/MonthlyReportPage.ets
import { router } from '@kit.ArkUI';
import dataPreferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import { getCategoryColor, AnimationConfig } from './Index';

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

@Entry
@Component
struct MonthlyReportPage {
  @StorageProp('brand_main') brandMain: string = '#4E6EF2';
  @StorageProp('brand_light') brandLight: string = '#7B93FF';
  @StorageProp('brand_deep') brandDeep: string = '#3A55E0';
  @State year: number = new Date().getFullYear();
  @State month: number = new Date().getMonth() + 1;
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
  @State hasBudget: boolean = false;
  @State budgetAmount: number = 0;
  @State insights: string[] = [];
  // 月份切换动画状态：内容横向偏移与透明度（入场从右侧淡入，切月时方向性滑动）
  @State contentShiftX: number = 40;
  @State contentAlpha: number = 0;
  private monthSwitching: boolean = false;

  aboutToAppear() {
    this.loadReport();
    // 页面入场：内容随转场从右侧轻微滑入并淡入
    setTimeout(() => {
      animateTo({ duration: 320, curve: AnimationConfig.SPRING_SOFT }, () => {
        this.contentShiftX = 0;
        this.contentAlpha = 1;
      });
    }, 120);
  }

  isCurrentMonth(): boolean {
    const now = new Date();
    return this.year === now.getFullYear() && this.month === now.getMonth() + 1;
  }

  waitMs(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(resolve, ms);
    });
  }

  applyMonthDelta(delta: number) {
    if (delta < 0) {
      if (this.month === 1) {
        this.month = 12;
        this.year -= 1;
      } else {
        this.month -= 1;
      }
    } else {
      if (this.month === 12) {
        this.month = 1;
        this.year += 1;
      } else {
        this.month += 1;
      }
    }
  }

  // 月份切换：旧内容沿切换方向滑出，新内容从另一侧滑入
  async switchMonth(dir: number): Promise<void> {
    if (this.monthSwitching) {
      return;
    }
    this.monthSwitching = true;
    animateTo({ duration: 180, curve: Curve.EaseIn }, () => {
      this.contentShiftX = -dir * 48;
      this.contentAlpha = 0;
    });
    await this.waitMs(190);
    this.applyMonthDelta(dir);
    await this.loadReport();
    animateTo({ duration: 0 }, () => {
      this.contentShiftX = dir * 48;
    });
    await this.waitMs(30);
    animateTo({ duration: 320, curve: AnimationConfig.SPRING_SOFT }, () => {
      this.contentShiftX = 0;
      this.contentAlpha = 1;
    });
    this.monthSwitching = false;
  }

  goPrevMonth() {
    this.switchMonth(-1);
  }

  goNextMonth() {
    if (this.isCurrentMonth()) {
      return;
    }
    this.switchMonth(1);
  }

  filterByMonth(bills: ReportBill[], ledgerId: number, year: number, month: number): ReportBill[] {
    return bills.filter((bill: ReportBill) => {
      const billLedger = bill.ledgerId !== undefined ? bill.ledgerId : DEFAULT_LEDGER_ID;
      if (billLedger !== ledgerId) {
        return false;
      }
      const d = new Date(bill.date);
      return d.getFullYear() === year && (d.getMonth() + 1) === month;
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

      const curBills = this.filterByMonth(bills, ledgerId, this.year, this.month);
      const prevY = this.month === 1 ? this.year - 1 : this.year;
      const prevM = this.month === 1 ? 12 : this.month - 1;
      const prevBills = this.filterByMonth(bills, ledgerId, prevY, prevM);

      let curExpense = 0;
      let curIncome = 0;
      let prevExpense = 0;
      let maxExpense = 0;
      let maxExpenseName = '';
      const catAmount: Record<string, number> = {};
      const catCount: Record<string, number> = {};
      const daySet = new Set<number>();
      curBills.forEach((bill: ReportBill) => {
        daySet.add(new Date(bill.date).getDate());
        if (bill.type === '支出') {
          curExpense += bill.amount;
          catAmount[bill.category] = (catAmount[bill.category] || 0) + bill.amount;
          catCount[bill.category] = (catCount[bill.category] || 0) + 1;
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
        const d = c - p;
        if (Math.abs(d) > 0.005) {
          deltas.push({ name: n, current: c, previous: p, delta: d });
        }
      });
      this.topIncreases = deltas.filter((d: CategoryDelta) => d.delta > 0)
        .sort((a: CategoryDelta, b: CategoryDelta) => b.delta - a.delta).slice(0, 3);
      this.topDecreases = deltas.filter((d: CategoryDelta) => d.delta < 0)
        .sort((a: CategoryDelta, b: CategoryDelta) => a.delta - b.delta).slice(0, 3);

      this.hasBudget = false;
      this.budgetAmount = 0;
      const ym = `${this.year}-${String(this.month).padStart(2, '0')}`;
      const budgetRaw = await prefs.get('budget', '') as string;
      if (budgetRaw.length > 0) {
        const budgetMap = JSON.parse(budgetRaw) as Record<string, number>;
        let value: number | undefined = budgetMap[`${ledgerId}:${ym}`];
        if (value === undefined && ledgerId === DEFAULT_LEDGER_ID) {
          value = budgetMap[ym];
        }
        if (value !== undefined && value > 0) {
          this.hasBudget = true;
          this.budgetAmount = value;
        }
      }

      const tips: string[] = [];
      if (this.hasData && stats.length > 0) {
        const top = stats[0];
        tips.push(`「${top.name}」占本月支出的 ${top.percent.toFixed(1)}%，是最大开销`);
      }
      if (this.hasData) {
        if (this.prevExpenseTotal > 0) {
          const changePct = Math.abs((curExpense - prevExpense) / prevExpense * 100).toFixed(1);
          if (curExpense >= prevExpense) {
            tips.push(`支出较上月上涨 ${changePct}%`);
          } else {
            tips.push(`支出较上月下降 ${changePct}%`);
          }
        } else {
          tips.push('上月无支出记录，暂无环比参考');
        }
        if (this.hasBudget) {
          const left = this.budgetAmount - curExpense;
          if (left >= 0) {
            tips.push(`预算内消费，还剩 ¥${left.toFixed(2)} 可用`);
          } else {
            tips.push(`本月已超支 ¥${(-left).toFixed(2)}，注意控制开销`);
          }
        }
        if (this.maxExpenseAmount > 0) {
          tips.push(`最大单笔支出：${this.maxExpenseName}（¥${this.maxExpenseAmount.toFixed(2)}）`);
        }
        tips.push(`本月记账 ${this.billCount} 笔，覆盖 ${this.recordDays} 天`);
      }
      this.insights = tips;
    } catch (e) {
      console.error('加载月度报告失败: ' + JSON.stringify(e));
    }
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

  // 宽屏断点（全局）：平板/折叠屏下内容限宽居中
  @StorageProp('isWideScreen') isWideScreen: boolean = false;

  build() {
    Row() {
    Column() {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_backward'))
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor([$r('app.color.text_primary')])
          .onClick(() => {
            router.back();
          })
          .margin({ right: 8 })

        Text('月度报告')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        Blank()
          .width(40)
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 20, bottom: 12 })

      Row() {
        SymbolGlyph($r('sys.symbol.chevron_backward'))
          .fontSize(20)
          .fontColor([this.brandMain])
          .onClick(() => {
            this.goPrevMonth();
          })
          .padding(8)

        Text(`${this.year}年${this.month}月`)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 8, right: 8 })

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(20)
          .fontColor(this.isCurrentMonth() ? [$r('app.color.border_color')] : [this.brandMain])
          .onClick(() => {
            this.goNextMonth();
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
          Text(`${this.year}年${this.month}月暂无账单记录`)
            .fontSize(16)
            .fontColor($r('app.color.text_secondary'))
          Text('记账后即可生成当月消费报告')
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
              Text('本月支出')
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
                  `较上月 ¥${this.prevExpenseTotal.toFixed(2)} 上涨 ${Math.abs((this.expenseTotal - this.prevExpenseTotal) / this.prevExpenseTotal * 100).toFixed(1)}%` :
                  `较上月 ¥${this.prevExpenseTotal.toFixed(2)} 下降 ${Math.abs((this.expenseTotal - this.prevExpenseTotal) / this.prevExpenseTotal * 100).toFixed(1)}%`)
                  .fontSize(12)
                  .fontColor($r('app.color.text_white'))
                  .alignSelf(ItemAlign.Start)
                  .margin({ top: 4 })
              } else {
                Text('上月无支出，暂无环比')
                  .fontSize(12)
                  .fontColor('#CCFFFFFF')
                  .alignSelf(ItemAlign.Start)
                  .margin({ top: 4 })
              }

              Divider()
                .color($r('app.color.border_color'))
                .margin({ top: 14, bottom: 14 })

              Row() {
                this.HeroStatCell('本月收入', '¥' + this.incomeTotal.toFixed(2))
                this.HeroStatCell('本月结余', (this.incomeTotal - this.expenseTotal >= 0 ? '+' : '') + (this.incomeTotal - this.expenseTotal).toFixed(2))
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

            if (this.hasBudget) {
              Column() {
                Text('预算使用')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                  .alignSelf(ItemAlign.Start)
                  .margin({ bottom: 10 })

                Progress({
                  value: Math.min(Math.floor(this.expenseTotal / this.budgetAmount * 100), 100),
                  total: 100,
                  type: ProgressType.Linear
                })
                  .width('100%')
                  .height(8)
                  .color(this.expenseTotal > this.budgetAmount ? $r('app.color.expense_red') : this.brandMain)

                Text(this.expenseTotal > this.budgetAmount ?
                  `已超支 ¥${(this.expenseTotal - this.budgetAmount).toFixed(2)}（预算 ¥${this.budgetAmount.toFixed(2)}）` :
                  `剩余 ¥${(this.budgetAmount - this.expenseTotal).toFixed(2)}（预算 ¥${this.budgetAmount.toFixed(2)}）`)
                  .fontSize(12)
                  .fontColor(this.expenseTotal > this.budgetAmount ? $r('app.color.expense_red') : $r('app.color.text_secondary'))
                  .alignSelf(ItemAlign.Start)
                  .margin({ top: 8 })
              }
              .width('100%')
              .padding(16)
              .backgroundColor($r('app.color.card_bg'))
              .borderRadius(16)
              .shadow({ radius: 12, color: $r('app.color.shadow_color'), offsetX: 0, offsetY: 4 })
              .margin({ bottom: 12 })
            }

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
                Text('分类环比变化')
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
          .padding({ left: 16, right: 16, top: 4 })
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

  // 页面转场：从统计页进入时自右侧滑入，返回时向右滑出
  pageTransition() {
    PageTransitionEnter({ type: RouteType.Push, duration: 360, curve: AnimationConfig.CURVE })
      .slide(SlideEffect.Right)
    PageTransitionExit({ type: RouteType.Push, duration: 300, curve: AnimationConfig.CURVE })
      .opacity(0)
    PageTransitionExit({ type: RouteType.Pop, duration: 360, curve: AnimationConfig.CURVE })
      .slide(SlideEffect.Right)
  }
}
