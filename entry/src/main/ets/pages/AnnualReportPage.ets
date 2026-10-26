// pages/AnnualReportPage.ets 年度报告：年度总览 + 月度支出趋势 + 分类排行 + 消费洞察 + 分享
import dataPreferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { fileUri } from '@kit.CoreFileKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
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

const DEFAULT_LEDGER_ID: number = 1;
const MONTH_LABELS: string[] = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12'];

@Component
struct AnnualReportPage {
  // 所在导航栈：由 NavDestination.onReady 注入
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('brand_main') brandMain: string = '#4E6EF2';
  @StorageProp('brand_light') brandLight: string = '#7B93FF';
  @StorageProp('brand_deep') brandDeep: string = '#3A55E0';
  @State year: number = new Date().getFullYear();
  @State hasData: boolean = false;
  @State expenseTotal: number = 0;
  @State incomeTotal: number = 0;
  @State prevYearExpense: number = 0;
  @State billCount: number = 0;
  @State recordDays: number = 0;
  @State maxExpenseName: string = '';
  @State maxExpenseAmount: number = 0;
  @State monthExpenses: number[] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
  @State peakMonthIdx: number = -1;
  @State lowMonthIdx: number = -1;
  @State categoryStats: CategoryStat[] = [];
  @State insights: string[] = [];
  // 年份切换动画状态：内容横向偏移与透明度
  @State contentShiftX: number = 40;
  @State contentAlpha: number = 0;
  // 按压回弹：当前按下目标的 key
  @State pressedChipKey: string = '';
  private yearSwitching: boolean = false;

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

  isCurrentYear(): boolean {
    return this.year >= new Date().getFullYear();
  }

  waitMs(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(resolve, ms);
    });
  }

  // 年份切换：旧内容沿切换方向滑出，新内容从另一侧滑入
  async switchYear(dir: number): Promise<void> {
    if (this.yearSwitching) {
      return;
    }
    this.yearSwitching = true;
    animateTo({ duration: 180, curve: Curve.EaseIn }, () => {
      this.contentShiftX = -dir * 48;
      this.contentAlpha = 0;
    });
    await this.waitMs(190);
    this.year += dir;
    await this.loadReport();
    animateTo({ duration: 0 }, () => {
      this.contentShiftX = dir * 48;
    });
    await this.waitMs(30);
    animateTo({ duration: 320, curve: AnimationConfig.SPRING_SOFT }, () => {
      this.contentShiftX = 0;
      this.contentAlpha = 1;
    });
    this.yearSwitching = false;
  }

  goPrevYear() {
    this.switchYear(-1);
  }

  goNextYear() {
    if (this.isCurrentYear()) {
      return;
    }
    this.switchYear(1);
  }

  filterByYear(bills: ReportBill[], ledgerId: number, year: number): ReportBill[] {
    return bills.filter((bill: ReportBill) => {
      const billLedger = bill.ledgerId !== undefined ? bill.ledgerId : DEFAULT_LEDGER_ID;
      if (billLedger !== ledgerId) {
        return false;
      }
      return new Date(bill.date).getFullYear() === year;
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

      const curBills = this.filterByYear(bills, ledgerId, this.year);
      const prevBills = this.filterByYear(bills, ledgerId, this.year - 1);

      let curExpense = 0;
      let curIncome = 0;
      let prevExpense = 0;
      let maxExpense = 0;
      let maxExpenseName = '';
      const catAmount: Record<string, number> = {};
      const catCount: Record<string, number> = {};
      const monthExp: number[] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
      const daySet = new Set<number>();
      curBills.forEach((bill: ReportBill) => {
        const d = new Date(bill.date);
        daySet.add(d.getDate() + d.getMonth() * 31);
        if (bill.type === '支出') {
          curExpense += bill.amount;
          catAmount[bill.category] = (catAmount[bill.category] || 0) + bill.amount;
          catCount[bill.category] = (catCount[bill.category] || 0) + 1;
          monthExp[d.getMonth()] += bill.amount;
          if (bill.amount > maxExpense) {
            maxExpense = bill.amount;
            maxExpenseName = bill.name;
          }
        } else if (bill.type === '收入') {
          curIncome += bill.amount;
        }
      });
      prevBills.forEach((bill: ReportBill) => {
        if (bill.type === '支出') {
          prevExpense += bill.amount;
        }
      });

      this.expenseTotal = curExpense;
      this.incomeTotal = curIncome;
      this.prevYearExpense = prevExpense;
      this.billCount = curBills.length;
      this.recordDays = daySet.size;
      this.maxExpenseAmount = maxExpense;
      this.maxExpenseName = maxExpenseName;
      this.hasData = curBills.length > 0;
      this.monthExpenses = monthExp;

      // 支出峰值月 / 最低月（仅统计有支出的月份）
      let peakIdx = -1;
      let lowIdx = -1;
      for (let i = 0; i < 12; i++) {
        if (monthExp[i] > 0) {
          if (peakIdx === -1 || monthExp[i] > monthExp[peakIdx]) {
            peakIdx = i;
          }
          if (lowIdx === -1 || monthExp[i] < monthExp[lowIdx]) {
            lowIdx = i;
          }
        }
      }
      this.peakMonthIdx = peakIdx;
      this.lowMonthIdx = lowIdx;

      const stats: CategoryStat[] = [];
      const catNames: string[] = Object.keys(catAmount);
      catNames.sort((a: string, b: string) => catAmount[b] - catAmount[a]);
      catNames.forEach((name: string) => {
        const amount = catAmount[name];
        const percent = curExpense > 0 ? Math.round((amount / curExpense) * 1000) / 10 : 0;
        stats.push({ name: name, amount: amount, percent: percent, count: catCount[name] || 0 });
      });
      this.categoryStats = stats;

      // 消费洞察
      const tips: string[] = [];
      if (this.hasData) {
        if (stats.length > 0) {
          const top = stats[0];
          tips.push(`「${top.name}」占全年支出的 ${top.percent.toFixed(1)}%，是最大开销`);
        }
        if (this.prevYearExpense > 0) {
          const changePct = Math.abs((curExpense - prevExpense) / prevExpense * 100).toFixed(1);
          if (curExpense >= prevExpense) {
            tips.push(`支出较上一年上涨 ${changePct}%`);
          } else {
            tips.push(`支出较上一年下降 ${changePct}%`);
          }
        } else {
          tips.push('上一年无支出记录，暂无同比参考');
        }
        if (peakIdx !== -1 && lowIdx !== -1 && peakIdx !== lowIdx) {
          tips.push(`支出最高月是 ${peakIdx + 1} 月（¥${monthExp[peakIdx].toFixed(2)}），最低月是 ${lowIdx + 1} 月（¥${monthExp[lowIdx].toFixed(2)}）`);
        }
        if (this.maxExpenseAmount > 0) {
          tips.push(`最大单笔支出：${this.maxExpenseName}（¥${this.maxExpenseAmount.toFixed(2)}）`);
        }
        tips.push(`月均支出 ¥${(curExpense / 12).toFixed(2)}，全年记账 ${this.billCount} 笔，覆盖 ${this.recordDays} 天`);
      }
      this.insights = tips;
    } catch (e) {
      console.error('加载年度报告失败: ' + JSON.stringify(e));
    }
  }

  // 分享年度账单文本摘要（写入缓存文件后走系统分享）
  async shareSummary(): Promise<void> {
    try {
      if (!this.hasData) {
        return;
      }
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const balance: number = this.incomeTotal - this.expenseTotal;
      const lines: string[] = [];
      lines.push(`【${this.year}年乌鸡记账年度账单】`);
      lines.push(`全年支出 ¥${this.expenseTotal.toFixed(2)}｜收入 ¥${this.incomeTotal.toFixed(2)}｜结余 ¥${balance.toFixed(2)}`);
      if (this.categoryStats.length > 0) {
        lines.push(`最大开销「${this.categoryStats[0].name}」占 ${this.categoryStats[0].percent.toFixed(1)}%`);
      }
      if (this.peakMonthIdx !== -1) {
        lines.push(`支出最高月：${this.peakMonthIdx + 1}月（¥${this.monthExpenses[this.peakMonthIdx].toFixed(2)}）`);
      }
      lines.push(`记账 ${this.billCount} 笔，覆盖 ${this.recordDays} 天，月均支出 ¥${(this.expenseTotal / 12).toFixed(2)}`);
      lines.push('—— 来自乌鸡记账');
      const content: string = lines.join('\n');

      const fileName: string = `乌鸡记账_年度账单_${this.year}.txt`;
      const filePath: string = `${context.cacheDir}/${fileName}`;
      const file = fs.openSync(filePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, content);
      fs.closeSync(file);

      const uri = fileUri.getUriFromPath(filePath);
      const txtUtd = utd.getUniformDataTypeByFilenameExtension('.txt');
      const shareData: systemShare.SharedData = new systemShare.SharedData({
        utd: txtUtd,
        uri: uri,
        title: fileName,
        description: '年度账单'
      });
      const shareController: systemShare.ShareController = new systemShare.ShareController(shareData);
      await shareController.show(context, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DEFAULT
      });
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      console.error('分享年度报告失败: code=' + err.code + ', message=' + err.message);
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

  @Builder
  MonthBar(label: string, idx: number) {
    Column() {
      Column() {
        Column()
          .width('70%')
          .height(this.monthExpenses[idx] > 0 && this.peakMonthIdx >= 0 ?
            Math.max(6, this.monthExpenses[idx] / this.monthExpenses[this.peakMonthIdx] * 88) : 4)
          .backgroundColor(idx === this.peakMonthIdx ? $r('app.color.expense_red') : this.brandLight)
          .borderRadius(3)
      }
      .width('100%')
      .height(92)
      .justifyContent(FlexAlign.End)
      .alignItems(HorizontalAlign.Center)

      Text(label)
        .fontSize(10)
        .fontColor(idx === this.peakMonthIdx ? $r('app.color.expense_red') : $r('app.color.text_secondary'))
        .margin({ top: 6 })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
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

        Text('年度报告')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        if (this.hasData) {
          Row() {
            SymbolGlyph($r('sys.symbol.share'))
              .fontSize(16)
              .fontColor([this.brandMain])
            Text('分享')
              .fontSize(13)
              .fontColor(this.brandMain)
              .margin({ left: 4 })
          }
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor($r('app.color.category_btn_bg'))
          .borderRadius(16)
          .scale({ x: this.pressedChipKey === 'share' ? 0.85 : 1, y: this.pressedChipKey === 'share' ? 0.85 : 1 })
          .animation({ curve: MotionCurves.PRESS })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              this.pressedChipKey = 'share';
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.pressedChipKey = '';
            }
          })
          .onClick(() => {
            this.shareSummary();
          })
        }
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
            this.goPrevYear();
          })
          .padding(8)

        Text(`${this.year}年`)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 8, right: 8 })

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(20)
          .fontColor(this.isCurrentYear() ? [$r('app.color.border_color')] : [this.brandMain])
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
            this.goNextYear();
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
          Text(`${this.year}年暂无账单记录`)
            .fontSize(16)
            .fontColor($r('app.color.text_secondary'))
          Text('记账后即可生成年度消费报告')
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
              Text('全年支出')
                .fontSize(13)
                .fontColor('#CCFFFFFF')
                .alignSelf(ItemAlign.Start)

              Text('¥' + this.expenseTotal.toFixed(2))
                .fontSize(34)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_white'))
                .alignSelf(ItemAlign.Start)
                .margin({ top: 4 })

              if (this.prevYearExpense > 0) {
                Text(this.expenseTotal >= this.prevYearExpense ?
                  `较上一年 ¥${this.prevYearExpense.toFixed(2)} 上涨 ${Math.abs((this.expenseTotal - this.prevYearExpense) / this.prevYearExpense * 100).toFixed(1)}%` :
                  `较上一年 ¥${this.prevYearExpense.toFixed(2)} 下降 ${Math.abs((this.expenseTotal - this.prevYearExpense) / this.prevYearExpense * 100).toFixed(1)}%`)
                  .fontSize(12)
                  .fontColor($r('app.color.text_white'))
                  .alignSelf(ItemAlign.Start)
                  .margin({ top: 4 })
              } else {
                Text('上一年无支出，暂无同比')
                  .fontSize(12)
                  .fontColor('#CCFFFFFF')
                  .alignSelf(ItemAlign.Start)
                  .margin({ top: 4 })
              }

              Divider()
                .color($r('app.color.border_color'))
                .margin({ top: 14, bottom: 14 })

              Row() {
                this.HeroStatCell('全年收入', '¥' + this.incomeTotal.toFixed(2))
                this.HeroStatCell('全年结余', (this.incomeTotal - this.expenseTotal >= 0 ? '+' : '') + (this.incomeTotal - this.expenseTotal).toFixed(2))
                this.HeroStatCell('月均支出', '¥' + (this.expenseTotal / 12).toFixed(2))
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
              Text('月度支出趋势')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .alignSelf(ItemAlign.Start)
                .margin({ bottom: 14 })

              Row({ space: 4 }) {
                ForEach(MONTH_LABELS, (label: string, idx: number) => {
                  this.MonthBar(label, idx)
                }, (label: string) => label)
              }
              .width('100%')

              if (this.peakMonthIdx !== -1) {
                Text(`支出峰值：${this.peakMonthIdx + 1}月 ¥${this.monthExpenses[this.peakMonthIdx].toFixed(2)}` +
                  (this.lowMonthIdx !== -1 && this.lowMonthIdx !== this.peakMonthIdx ?
                    `｜最低：${this.lowMonthIdx + 1}月 ¥${this.monthExpenses[this.lowMonthIdx].toFixed(2)}` : ''))
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .alignSelf(ItemAlign.Start)
                  .margin({ top: 12 })
              }
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
    .hideTitleBar(true)
    .backgroundColor($r('app.color.bg_main'))
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
    })
  }

}

// 系统路由表（router_map.json）构建入口：导航栈按 name 路由到此页
@Builder
export function AnnualReportPageBuilder(name: string, param: object) {
  if (name === 'AnnualReportPage') {
    AnnualReportPage()
  }
}
