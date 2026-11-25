// pages/MonthlyReportPage.ets
import dataPreferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { fileUri } from '@kit.CoreFileKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { getCategoryColor, AnimationConfig } from './Index';
import { MotionCurves } from '../common/Motion';
import { BrandSignals, DeviceSignals } from '../common/V2Signals';
import { NetAssetSnapshot, NetAssetBill, loadNetAssetSnapshot, estimateNetAssetAt, monthEndTime } from '../common/NetAsset';

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

@ComponentV2
struct MonthlyReportPage {
  // 所在导航栈：由 NavDestination.onReady 注入
  pathStack: NavPathStack = new NavPathStack();
  // V2 全局信号（AppStorageV2 桥接层，替代原 @StorageProp）
  @Local brandSignals: BrandSignals = BrandSignals.connect();
  @Computed get brandMain(): string { return this.brandSignals.main; }
  @Computed get brandLight(): string { return this.brandSignals.light; }
  @Computed get brandDeep(): string { return this.brandSignals.deep; }
  @Local devSignals: DeviceSignals = DeviceSignals.connect();
  @Computed get isWideScreen(): boolean { return this.devSignals.isWideScreen; }
  @Computed get statusBarVp(): number { return this.devSignals.statusBarVp; }
  @Computed get navBarVp(): number { return this.devSignals.navBarVp; }
  @Local year: number = new Date().getFullYear();
  @Local month: number = new Date().getMonth() + 1;
  @Local hasData: boolean = false;
  @Local expenseTotal: number = 0;
  @Local incomeTotal: number = 0;
  @Local prevExpenseTotal: number = 0;
  @Local billCount: number = 0;
  @Local recordDays: number = 0;
  @Local maxExpenseName: string = '';
  @Local maxExpenseAmount: number = 0;
  @Local categoryStats: CategoryStat[] = [];
  @Local topIncreases: CategoryDelta[] = [];
  @Local topDecreases: CategoryDelta[] = [];
  @Local hasBudget: boolean = false;
  @Local budgetAmount: number = 0;
  @Local insights: string[] = [];
  // 月末净资产（估算）：以当前净资产为基准按收支回推，UI 标注“估算”
  @Local netAssetEnd: number = 0;
  @Local netAssetPrevEnd: number = 0;
  // 月份切换动画状态：内容横向偏移与透明度（入场从右侧淡入，切月时方向性滑动）
  @Local contentShiftX: number = 40;
  @Local contentAlpha: number = 0;
  // 按压回弹：当前按下目标的 key
  @Local pressedChipKey: string = '';
  // 分享海报生成中（防重复点击）
  @Local posterGenerating: boolean = false;
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

      // 月末/上月末净资产估算：以当前净资产为基准，按全部账单收支回推（假设收支均经资产账户）
      const snapshot: NetAssetSnapshot = await loadNetAssetSnapshot(context);
      const netBills: NetAssetBill[] = bills.map((b: ReportBill): NetAssetBill => {
        return { amount: b.amount, type: b.type, date: b.date, ledgerId: b.ledgerId };
      });
      const monthEnd: number = monthEndTime(this.year, this.month);
      const prevMonthEnd: number = this.month === 1 ?
        monthEndTime(this.year - 1, 12) : monthEndTime(this.year, this.month - 1);
      this.netAssetEnd = estimateNetAssetAt(snapshot.net, netBills, monthEnd);
      this.netAssetPrevEnd = estimateNetAssetAt(snapshot.net, netBills, prevMonthEnd);

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

  // 海报副标题：支出环比文案
  buildPosterSubline(): string {
    if (this.prevExpenseTotal > 0) {
      const pct = Math.abs((this.expenseTotal - this.prevExpenseTotal) / this.prevExpenseTotal * 100).toFixed(1);
      return this.expenseTotal >= this.prevExpenseTotal ? `支出较上月上涨 ${pct}%` : `支出较上月下降 ${pct}%`;
    }
    return '本月总支出';
  }

  // 生成月报分享海报：离屏 Canvas 绘制品牌渐变卡片 → PNG → 系统分享面板
  async generateSharePoster(): Promise<void> {
    if (this.posterGenerating) {
      return;
    }
    if (!this.hasData) {
      this.getUIContext().getPromptAction().showToast({ message: '本月暂无账单，记账后再来生成海报', duration: 2000 });
      return;
    }
    this.posterGenerating = true;
    this.getUIContext().getPromptAction().showToast({ message: '正在生成海报…', duration: 1500 });
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      // 画布尺寸与布局参数（大字号紧凑排版：减少留白、提高信息密度）
      const canvasWidth = 750;
      const padding = 40;
      const heroHeight = 470;
      const statsCardHeight = 160;
      const cardGap = 28;
      const maxBars = 5;
      const bars: CategoryStat[] = this.categoryStats.slice(0, maxBars);
      const barsCardHeight = 208 + (bars.length - 1) * 96;
      const footerHeight = 120;
      const canvasHeight = heroHeight + cardGap + statsCardHeight + cardGap + barsCardHeight + footerHeight;

      const settings: RenderingContextSettings = new RenderingContextSettings(true);
      const ctx: OffscreenCanvasRenderingContext2D = new OffscreenCanvasRenderingContext2D(canvasWidth, canvasHeight, settings);
      ctx.textBaseline = 'top';

      // 1. 页面背景
      ctx.fillStyle = '#F4F6FB';
      ctx.fillRect(0, 0, canvasWidth, canvasHeight);

      // 2. 顶部品牌渐变区
      const heroGradient = ctx.createLinearGradient(0, 0, canvasWidth, heroHeight);
      heroGradient.addColorStop(0, this.brandLight);
      heroGradient.addColorStop(0.55, this.brandMain);
      heroGradient.addColorStop(1, this.brandDeep);
      ctx.fillStyle = heroGradient;
      ctx.fillRect(0, 0, canvasWidth, heroHeight);

      ctx.textAlign = 'left';
      ctx.fillStyle = 'rgba(255, 255, 255, 0.88)';
      ctx.font = '34px sans-serif';
      ctx.fillText(`${this.year}年${this.month}月 · 账单总结`, padding, 56);

      ctx.fillStyle = 'rgba(255, 255, 255, 0.82)';
      ctx.font = '30px sans-serif';
      ctx.fillText('本月支出', padding, 112);

      ctx.fillStyle = '#FFFFFF';
      ctx.font = 'bold 112px sans-serif';
      ctx.fillText('¥' + this.expenseTotal.toFixed(2), padding, 156);

      ctx.fillStyle = 'rgba(255, 255, 255, 0.94)';
      ctx.font = '32px sans-serif';
      ctx.fillText(this.buildPosterSubline(), padding, 300);
      ctx.fillText(`记账 ${this.billCount} 笔 · ${this.recordDays} 天`, padding, 352);

      // 海报月末净资产行（36px 加粗，估算值）
      ctx.fillStyle = '#FFFFFF';
      ctx.font = 'bold 36px sans-serif';
      ctx.fillText(`月末净资产 ¥${this.netAssetEnd.toFixed(2)}（估算）`, padding, 400);

      // 3. 收入 / 结余 / 日均 数据卡
      const statsY = heroHeight + cardGap;
      ctx.fillStyle = '#FFFFFF';
      ctx.beginPath();
      ctx.roundRect(padding, statsY, canvasWidth - padding * 2, statsCardHeight, 28);
      ctx.fill();

      const balance = this.incomeTotal - this.expenseTotal;
      const dailyAvg = this.recordDays > 0 ? this.expenseTotal / this.recordDays : 0;
      const statLabels: string[] = ['本月收入', '本月结余', '日均支出'];
      const statValues: string[] = [
        '¥' + this.incomeTotal.toFixed(2),
        (balance >= 0 ? '+' : '') + '¥' + balance.toFixed(2),
        '¥' + dailyAvg.toFixed(2)
      ];
      const colWidth = (canvasWidth - padding * 2) / 3;
      for (let i = 0; i < 3; i++) {
        ctx.textAlign = 'left';
        ctx.fillStyle = '#8A9099';
        ctx.font = '26px sans-serif';
        ctx.fillText(statLabels[i], padding + colWidth * i + 30, statsY + 32);
        ctx.fillStyle = '#1F2329';
        ctx.font = 'bold 36px sans-serif';
        ctx.fillText(statValues[i], padding + colWidth * i + 30, statsY + 84);
      }

      // 4. 分类排行条形图卡
      const barsY = statsY + statsCardHeight + cardGap;
      ctx.fillStyle = '#FFFFFF';
      ctx.beginPath();
      ctx.roundRect(padding, barsY, canvasWidth - padding * 2, barsCardHeight, 28);
      ctx.fill();

      ctx.fillStyle = '#1F2329';
      ctx.font = 'bold 36px sans-serif';
      ctx.fillText('分类排行', padding + 32, barsY + 34);

      const barLeft = padding + 32;
      const barRight = canvasWidth - padding - 32;
      let barY = barsY + 104;
      for (let i = 0; i < bars.length; i++) {
        const stat = bars[i];
        ctx.textAlign = 'left';
        ctx.fillStyle = '#1F2329';
        ctx.font = 'bold 32px sans-serif';
        ctx.fillText(stat.name, barLeft, barY);
        // 右侧金额 + 占比
        const amountStr = `¥${stat.amount.toFixed(2)} · ${stat.percent.toFixed(1)}%`;
        ctx.font = '32px sans-serif';
        ctx.fillStyle = '#1F2329';
        ctx.fillText(amountStr, barRight - ctx.measureText(amountStr).width, barY);
        // 轨道 + 进度条
        const trackY = barY + 50;
        const trackWidth = barRight - barLeft;
        ctx.fillStyle = '#EEF0F4';
        ctx.beginPath();
        ctx.roundRect(barLeft, trackY, trackWidth, 20, 10);
        ctx.fill();
        const fillWidth = Math.max(trackWidth * stat.percent / 100, 20);
        ctx.fillStyle = getCategoryColor(stat.name);
        ctx.beginPath();
        ctx.roundRect(barLeft, trackY, fillWidth, 20, 10);
        ctx.fill();
        barY += 96;
      }

      // 5. 落款
      const now = new Date();
      const dateStr = now.getFullYear() + '-' +
        String(now.getMonth() + 1).padStart(2, '0') + '-' +
        String(now.getDate()).padStart(2, '0');
      ctx.fillStyle = '#B3B9C0';
      ctx.font = '26px sans-serif';
      ctx.textAlign = 'center';
      ctx.fillText(`由乌鸡记账生成 · ${dateStr}`, canvasWidth / 2, canvasHeight - 60);

      // 导出 PNG：toDataURL → base64 解码 → 写入缓存目录
      const dataUrl: string = ctx.toDataURL('image/png');
      const base64: string = dataUrl.substring(dataUrl.indexOf(',') + 1);
      const bytes: Uint8Array = new util.Base64Helper().decodeSync(base64);
      const buffer: ArrayBuffer = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
      const fileName: string = `月报海报_${this.year}${String(this.month).padStart(2, '0')}_${Date.now()}.png`;
      const filePath: string = context.cacheDir + '/' + fileName;
      const file = fs.openSync(filePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, buffer);
      fs.closeSync(file);

      // 拉起系统分享面板
      const uri = fileUri.getUriFromPath(filePath);
      const shareData: systemShare.SharedData = new systemShare.SharedData({
        utd: utd.getUniformDataTypeByFilenameExtension('.png'),
        uri: uri,
        title: fileName,
        description: '月度报告海报'
      });
      const shareController: systemShare.ShareController = new systemShare.ShareController(shareData);
      await shareController.show(context, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DEFAULT
      });
    } catch (e) {
      console.error('生成月报海报失败: ' + JSON.stringify(e));
      this.getUIContext().getPromptAction().showToast({ message: '海报生成失败，请重试', duration: 2000 });
    }
    this.posterGenerating = false;
  }

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

        Text('月度报告')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        // 生成分享海报：离屏 Canvas 绘制品牌渐变月报卡片，拉起系统分享
        SymbolGlyph($r('sys.symbol.share'))
          .fontSize(22)
          .fontColor([$r('app.color.text_primary')])
          .scale({ x: this.pressedChipKey === 'share' ? 0.8 : 1, y: this.pressedChipKey === 'share' ? 0.8 : 1 })
          .animation({ curve: MotionCurves.PRESS })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              this.pressedChipKey = 'share';
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.pressedChipKey = '';
            }
          })
          .onClick(() => {
            this.generateSharePoster();
          })
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

              // 月末净资产（估算）+ 环比：以当前净资产为基准按收支回推
              Divider()
                .color($r('app.color.border_color'))
                .margin({ top: 12, bottom: 12 })

              Row() {
                Column() {
                  Text('月末净资产（估算）')
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ bottom: 4 })
                  Text((this.netAssetEnd >= 0 ? '¥' : '-¥') + Math.abs(this.netAssetEnd).toFixed(2))
                    .fontSize(18)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.netAssetEnd >= 0 ? $r('app.color.income_gold') : $r('app.color.expense_red'))
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Column() {
                  Text('较上月')
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ bottom: 4 })
                  Text((this.netAssetEnd - this.netAssetPrevEnd >= 0 ? '+' : '') +
                    (this.netAssetEnd - this.netAssetPrevEnd).toFixed(2))
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.netAssetEnd - this.netAssetPrevEnd >= 0 ?
                      $r('app.color.income_gold') : $r('app.color.expense_red'))
                }
                .alignItems(HorizontalAlign.End)
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
export function MonthlyReportPageBuilder(name: string, param: object) {
  if (name === 'MonthlyReportPage') {
    MonthlyReportPage()
  }
}
