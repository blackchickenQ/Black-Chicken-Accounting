import { common } from '@kit.AbilityKit';
import dataPreferences from '@ohos.data.preferences';
import { hapticTick } from '../common/Haptics';
import { HandIcon } from '../common/HandIcon';
import { MotionCurves } from '../common/Motion';
import { AnimationConfig, BillItem, DEFAULT_LEDGER_ID } from './Index';
import { BrandSignals, DeviceSignals } from '../common/V2Signals';
import {
  EarningSettings,
  EarningSession,
  EarningRecord,
  defaultEarningSettings,
  loadEarningSettings,
  saveEarningSettings,
  loadEarningSession,
  saveEarningSession,
  clearEarningSession,
  loadEarningRecords,
  appendEarningRecord,
  deleteEarningRecord,
  updateEarningRecordBill,
  computeEarnedAmount,
  formatDurationHMS,
  formatDurationShort,
  formatRecordTime
} from '../common/EarningTimer';

// 解析正数输入，无效返回 0
function parsePositiveInput(text: string): number {
  const v = parseFloat(text);
  if (isNaN(v) || v <= 0) {
    return 0;
  }
  return v;
}

// ========== 赚钱计时页：设置（时薪/总价）→ 计时（实时金额）→ 结算（一键入账）+ 历史 ==========
@ComponentV2
struct EarningTimerPage {
  // 所在导航栈：由 NavDestination.onReady 注入
  pathStack: NavPathStack = new NavPathStack();
  // V2 全局信号（AppStorageV2 桥接层）
  @Local brandSignals: BrandSignals = BrandSignals.connect();
  @Computed get brandMain(): string { return this.brandSignals.main; }
  @Computed get brandTint(): string { return this.brandSignals.tint; }
  @Local deviceSignals: DeviceSignals = DeviceSignals.connect();
  @Computed get isWideScreen(): boolean { return this.deviceSignals.isWideScreen; }
  @Computed get statusBarVp(): number { return this.deviceSignals.statusBarVp; }
  @Computed get navBarVp(): number { return this.deviceSignals.navBarVp; }

  // 页面状态：setup 设置 → running 计时 → result 结算
  @Local pageState: string = 'setup';
  // 设置表单
  @Local inputMode: string = 'hourly';
  @Local rateInput: string = '30';
  @Local totalInput: string = '200';
  @Local hoursInput: string = '4';
  @Local noteInput: string = '';
  @Local overtimeStop: boolean = false;
  @Local endAction: string = 'manual';
  // 计时态显示（tick 每 200ms 刷新）
  @Local elapsedMs: number = 0;
  @Local earnedDisplay: number = 0;
  @Local paused: boolean = false;
  // 结算态
  @Local lastRecord: EarningRecord | null = null;
  @Local resultBillId: number = 0;
  // 历史
  @Local historyRecords: EarningRecord[] = [];
  // 按压中的按钮 key（Q弹缩放反馈）
  @Local pressedChipKey: string = '';

  private quickRates: number[] = [15, 20, 30, 50, 100];
  private runningSession: EarningSession | null = null;
  private tickTimer: number = -1;
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;

  async aboutToAppear(): Promise<void> {
    // 上次的设置作为本次默认值
    const settings = await loadEarningSettings(this.context);
    this.inputMode = settings.mode;
    this.rateInput = settings.hourlyRate.toString();
    this.totalInput = settings.fixedTotal.toString();
    this.hoursInput = settings.fixedHours.toString();
    this.noteInput = settings.defaultNote;
    this.overtimeStop = settings.overtimePolicy === 'stop';
    this.endAction = settings.endAction;
    this.historyRecords = await loadEarningRecords(this.context);
    // 闪退/重启恢复：存在进行中的会话则直接回到计时态
    const sess = await loadEarningSession(this.context);
    if (sess !== null) {
      this.runningSession = sess;
      this.pageState = 'running';
      this.paused = sess.segmentStartTs === 0;
      this.refreshTick();
      this.startTicking();
    }
  }

  aboutToDisappear(): void {
    this.stopTicking();
  }

  // ---------- 计时引擎：时间戳累积法，setInterval 仅负责刷新显示 ----------

  private startTicking(): void {
    this.stopTicking();
    this.tickTimer = setInterval(() => {
      this.refreshTick();
    }, 200);
  }

  private stopTicking(): void {
    if (this.tickTimer >= 0) {
      clearInterval(this.tickTimer);
      this.tickTimer = -1;
    }
  }

  private refreshTick(): void {
    const s = this.runningSession;
    if (s === null) {
      return;
    }
    const now = Date.now();
    const elapsed = s.accumMs + (s.segmentStartTs > 0 ? now - s.segmentStartTs : 0);
    this.elapsedMs = elapsed;
    this.earnedDisplay = computeEarnedAmount(s, elapsed);
  }

  // ---------- 动作 ----------

  private async startSession(): Promise<void> {
    let rate = 0;
    let totalAmount = 0;
    let fixedMinutes = 0;
    if (this.inputMode === 'hourly') {
      rate = parsePositiveInput(this.rateInput);
      if (rate <= 0) {
        this.getUIContext().getPromptAction().showToast({ message: '请输入有效的时薪', duration: 1800 });
        return;
      }
    } else {
      totalAmount = parsePositiveInput(this.totalInput);
      if (totalAmount <= 0) {
        this.getUIContext().getPromptAction().showToast({ message: '请输入有效的总价', duration: 1800 });
        return;
      }
      fixedMinutes = Math.round(parsePositiveInput(this.hoursInput) * 60);
      if (fixedMinutes <= 0) {
        this.getUIContext().getPromptAction().showToast({ message: '请输入有效的预计时长', duration: 1800 });
        return;
      }
    }
    const now = Date.now();
    const session: EarningSession = {
      mode: this.inputMode,
      hourlyRate: rate,
      fixedTotal: totalAmount,
      fixedMinutes: fixedMinutes,
      overtimePolicy: this.overtimeStop ? 'stop' : 'continue',
      endAction: this.endAction,
      note: this.noteInput.trim(),
      startTs: now,
      accumMs: 0,
      segmentStartTs: now
    };
    this.runningSession = session;
    await saveEarningSession(this.context, session);
    // 当前输入保存为下次默认值
    const settings: EarningSettings = {
      mode: this.inputMode,
      hourlyRate: rate > 0 ? rate : parsePositiveInput(this.rateInput),
      fixedTotal: totalAmount > 0 ? totalAmount : parsePositiveInput(this.totalInput),
      fixedHours: parsePositiveInput(this.hoursInput) > 0 ? parsePositiveInput(this.hoursInput) : 4,
      overtimePolicy: this.overtimeStop ? 'stop' : 'continue',
      endAction: this.endAction,
      defaultNote: this.noteInput.trim()
    };
    await saveEarningSettings(this.context, settings);
    this.elapsedMs = 0;
    this.earnedDisplay = 0;
    this.paused = false;
    this.pageState = 'running';
    hapticTick();
    this.refreshTick();
    this.startTicking();
  }

  private async pauseResume(): Promise<void> {
    const s = this.runningSession;
    if (s === null) {
      return;
    }
    const now = Date.now();
    if (this.paused) {
      s.segmentStartTs = now;
      this.paused = false;
    } else {
      if (s.segmentStartTs > 0) {
        s.accumMs += now - s.segmentStartTs;
      }
      s.segmentStartTs = 0;
      this.paused = true;
    }
    hapticTick();
    await saveEarningSession(this.context, s);
    this.refreshTick();
  }

  private async endSession(): Promise<void> {
    const s = this.runningSession;
    if (s === null) {
      return;
    }
    const now = Date.now();
    let elapsed = s.accumMs;
    if (s.segmentStartTs > 0) {
      elapsed += now - s.segmentStartTs;
    }
    const amount = Math.round(computeEarnedAmount(s, elapsed) * 100) / 100;
    const record: EarningRecord = {
      id: Date.now(),
      startTime: s.startTs,
      endTime: now,
      durationMs: elapsed,
      amount: amount,
      mode: s.mode,
      hourlyRate: s.hourlyRate,
      fixedTotal: s.fixedTotal,
      fixedMinutes: s.fixedMinutes,
      note: s.note,
      billId: 0
    };
    let billId = 0;
    if (s.endAction === 'auto') {
      billId = await this.writeEarningBill(record);
      record.billId = billId;
    }
    await appendEarningRecord(this.context, record);
    await clearEarningSession(this.context);
    this.stopTicking();
    this.runningSession = null;
    this.historyRecords = [record, ...this.historyRecords];
    this.lastRecord = record;
    this.resultBillId = billId;
    this.paused = false;
    this.pageState = 'result';
    hapticTick();
  }

  // 把本次赚钱结果写成一笔「收入」账单（直接落库 + 信号通知首页刷新）
  private async writeEarningBill(record: EarningRecord): Promise<number> {
    try {
      const prefs = await dataPreferences.getPreferences(this.context, 'bill_data');
      const billsData = await prefs.get('bills_key', '[]') as string;
      const bills = JSON.parse(billsData) as BillItem[];
      const ledgerIdStr = await prefs.get('current_ledger_id', '') as string;
      const ledgerId = ledgerIdStr.length > 0 ? parseInt(ledgerIdStr, 10) : DEFAULT_LEDGER_ID;
      const note = record.note.length > 0 ? record.note : '计时收入';
      const bill: BillItem = {
        id: Date.now(),
        name: `赚钱·${note}`,
        amount: record.amount,
        type: '收入',
        date: record.endTime,
        category: '其他',
        source: '现金',
        tags: [],
        ledgerId: isNaN(ledgerId) ? DEFAULT_LEDGER_ID : ledgerId,
        photoUris: []
      };
      bills.unshift(bill);
      await prefs.put('bills_key', JSON.stringify(bills));
      await prefs.flush();
      // 与存钱目标存入记账同一信号模式：通知首页重新加载账单列表
      AppStorage.setOrCreate('shouldRefreshBills', Date.now());
      return bill.id;
    } catch (e) {
      console.error('赚钱计时入账失败', e);
      return 0;
    }
  }

  // 结算页手动「记一笔收入」
  private async recordBillFromResult(): Promise<void> {
    const r = this.lastRecord;
    if (r === null || this.resultBillId > 0) {
      return;
    }
    const billId = await this.writeEarningBill(r);
    if (billId > 0) {
      r.billId = billId;
      this.resultBillId = billId;
      await updateEarningRecordBill(this.context, r.id, billId);
      hapticTick();
      this.getUIContext().getPromptAction().showToast({ message: '已记入当前账本', duration: 1800 });
    } else {
      this.getUIContext().getPromptAction().showToast({ message: '入账失败，请重试', duration: 1800 });
    }
  }

  private async removeRecord(id: number): Promise<void> {
    this.getUIContext().getPromptAction().showDialog({
      title: '确认删除',
      message: '删除这条赚钱记录？',
      buttons: [
        { text: '取消', color: $r('app.color.text_secondary') },
        { text: '删除', color: $r('app.color.expense_red') }
      ]
    }).then((result) => {
      if (result.index === 1) {
        deleteEarningRecord(this.context, id).then(() => {
          this.historyRecords = this.historyRecords.filter((r: EarningRecord): boolean => r.id !== id);
        });
      }
    });
  }

  // 计时进行中返回：确认后再离开（计时数据已实时落盘）
  private showLeaveDialog(): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '计时进行中',
      message: '离开后计时将继续进行，随时回来查看已赚金额',
      buttons: [
        { text: '暂停并离开', color: $r('app.color.text_secondary') },
        { text: '继续计时', color: this.brandMain }
      ]
    }).then((result) => {
      if (result.index === 0) {
        this.pauseResume();
        this.pathStack.pop();
      }
    });
  }

  // ---------- 显示辅助 ----------

  @Computed get historyTotalAmount(): number {
    let sum = 0;
    for (const r of this.historyRecords) {
      sum += r.amount;
    }
    return Math.round(sum * 100) / 100;
  }

  @Computed get historyTotalMs(): number {
    let sum = 0;
    for (const r of this.historyRecords) {
      sum += r.durationMs;
    }
    return sum;
  }

  @Computed get resultAmount(): number {
    return this.lastRecord !== null ? this.lastRecord.amount : 0;
  }

  @Computed get resultDurationMs(): number {
    return this.lastRecord !== null ? this.lastRecord.durationMs : 0;
  }

  @Computed get resultNote(): string {
    return this.lastRecord !== null && this.lastRecord.note.length > 0 ? this.lastRecord.note : '计时收入';
  }

  @Computed get resultPerMinute(): number {
    if (this.lastRecord === null || this.lastRecord.durationMs <= 0) {
      return 0;
    }
    return Math.round(this.lastRecord.amount / (this.lastRecord.durationMs / 60000) * 100) / 100;
  }

  @Computed get resultModeText(): string {
    if (this.lastRecord === null) {
      return '';
    }
    return this.lastRecord.mode === 'fixed'
      ? `总价 ¥${this.lastRecord.fixedTotal} · 预计${formatDurationShort(this.lastRecord.fixedMinutes * 60000)}`
      : `时薪 ¥${this.lastRecord.hourlyRate}/小时`;
  }

  private plannedMs(): number {
    const s = this.runningSession;
    if (s === null || s.mode !== 'fixed') {
      return 0;
    }
    return s.fixedMinutes * 60 * 1000;
  }

  private fixedPercent(): number {
    const planned = this.plannedMs();
    if (planned <= 0) {
      return 0;
    }
    return Math.min(100, this.elapsedMs / planned * 100);
  }

  private fixedStatusText(): string {
    const s = this.runningSession;
    const planned = this.plannedMs();
    if (s === null || planned <= 0) {
      return '';
    }
    if (this.elapsedMs < planned) {
      return `预计还剩 ${formatDurationHMS(planned - this.elapsedMs)}`;
    }
    if (s.overtimePolicy === 'stop') {
      return '已到约定时长，金额停在总价';
    }
    return `已超时 ${formatDurationHMS(this.elapsedMs - planned)}，继续进账中`;
  }

  private perMinuteText(): string {
    const s = this.runningSession;
    if (s === null) {
      return '';
    }
    if (s.mode === 'fixed') {
      if (s.fixedMinutes <= 0) {
        return '';
      }
      const v = Math.round(s.fixedTotal / s.fixedMinutes * 100) / 100;
      return `每分钟约 ¥${v.toFixed(2)}`;
    }
    const v = Math.round(s.hourlyRate / 60 * 100) / 100;
    return `每分钟约 ¥${v.toFixed(2)}`;
  }

  private modeTextOf(s: EarningSession): string {
    return s.mode === 'fixed'
      ? `总价 ¥${s.fixedTotal} · 预计${formatDurationShort(s.fixedMinutes * 60000)}`
      : `时薪 ¥${s.hourlyRate}/小时`;
  }

  // ---------- UI ----------

  @Builder
  SetupBody() {
    Column() {
      // ===== 模式选择 =====
      Row() {
        Column() {
          HandIcon({ name: 'bolt', iconSize: 24 })
          Text('时薪模式')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.inputMode === 'hourly' ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
            .margin({ top: 6 })
          Text('按小时算钱')
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 2 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
        .padding({ top: 14, bottom: 14 })
        .borderRadius(16)
        .backgroundColor(this.inputMode === 'hourly' ? this.brandTint : $r('app.color.card_bg'))
        .border({
          width: this.inputMode === 'hourly' ? 2 : 1,
          color: this.inputMode === 'hourly' ? this.brandMain : $r('app.color.border_color')
        })
        .scale({
          x: this.pressedChipKey === 'mode_hourly' ? 0.96 : 1,
          y: this.pressedChipKey === 'mode_hourly' ? 0.96 : 1
        })
        .animation({ curve: MotionCurves.PRESS })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.pressedChipKey = 'mode_hourly';
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.pressedChipKey = '';
          }
        })
        .onClick(() => {
          hapticTick();
          this.inputMode = 'hourly';
        })

        Column()
          .width(10)

        Column() {
          HandIcon({ name: 'target', iconSize: 24 })
          Text('总价模式')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.inputMode === 'fixed' ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
            .margin({ top: 6 })
          Text('按项目算钱')
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 2 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
        .padding({ top: 14, bottom: 14 })
        .borderRadius(16)
        .backgroundColor(this.inputMode === 'fixed' ? this.brandTint : $r('app.color.card_bg'))
        .border({
          width: this.inputMode === 'fixed' ? 2 : 1,
          color: this.inputMode === 'fixed' ? this.brandMain : $r('app.color.border_color')
        })
        .scale({
          x: this.pressedChipKey === 'mode_fixed' ? 0.96 : 1,
          y: this.pressedChipKey === 'mode_fixed' ? 0.96 : 1
        })
        .animation({ curve: MotionCurves.PRESS })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.pressedChipKey = 'mode_fixed';
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.pressedChipKey = '';
          }
        })
        .onClick(() => {
          hapticTick();
          this.inputMode = 'fixed';
        })
      }
      .width('100%')
      .margin({ bottom: 12 })

      // ===== 参数卡 =====
      Column() {
        if (this.inputMode === 'hourly') {
          Text('时薪（元/小时）')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .alignSelf(ItemAlign.Start)
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.quickRates, (opt: number) => {
              Text(`¥${opt}`)
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(parsePositiveInput(this.rateInput) === opt ? $r('app.color.text_white') : $r('app.color.text_primary'))
                .padding({ left: 14, right: 14, top: 6, bottom: 6 })
                .backgroundColor(parsePositiveInput(this.rateInput) === opt ? this.brandMain : $r('app.color.category_btn_bg'))
                .borderRadius(15)
                .margin({ right: 8, top: 8 })
                .onClick(() => {
                  hapticTick();
                  this.rateInput = opt.toString();
                })
            }, (opt: number) => opt.toString() + (parsePositiveInput(this.rateInput) === opt ? '_1' : '_0'))
          }
          .width('100%')
          .margin({ top: 8 })

          TextInput({ placeholder: '或输入自定义时薪', text: this.rateInput })
            .width('100%')
            .height(44)
            .fontSize(16)
            .borderRadius(12)
            .backgroundColor($r('app.color.card_bg'))
            .borderColor($r('app.color.border_color'))
            .borderWidth(1)
            .padding({ left: 16, right: 16 })
            .type(InputType.NUMBER_DECIMAL)
            .margin({ top: 10 })
            .onChange((val: string) => {
              this.rateInput = val;
            })
        } else {
          Row() {
            Column() {
              Text('约定总价（元）')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              TextInput({ placeholder: '如 200', text: this.totalInput })
                .width('100%')
                .height(44)
                .fontSize(16)
                .borderRadius(12)
                .backgroundColor($r('app.color.card_bg'))
                .borderColor($r('app.color.border_color'))
                .borderWidth(1)
                .padding({ left: 16, right: 16 })
                .type(InputType.NUMBER_DECIMAL)
                .margin({ top: 8 })
                .onChange((val: string) => {
                  this.totalInput = val;
                })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Column()
              .width(12)

            Column() {
              Text('预计时长（小时）')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              TextInput({ placeholder: '如 4', text: this.hoursInput })
                .width('100%')
                .height(44)
                .fontSize(16)
                .borderRadius(12)
                .backgroundColor($r('app.color.card_bg'))
                .borderColor($r('app.color.border_color'))
                .borderWidth(1)
                .padding({ left: 16, right: 16 })
                .type(InputType.NUMBER_DECIMAL)
                .margin({ top: 8 })
                .onChange((val: string) => {
                  this.hoursInput = val;
                })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)

          Text('超出预计时长后')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .alignSelf(ItemAlign.Start)
            .margin({ top: 14 })

          Row() {
            Text('继续按比例加钱')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(!this.overtimeStop ? $r('app.color.text_white') : $r('app.color.text_primary'))
              .padding({ left: 14, right: 14, top: 7, bottom: 7 })
              .backgroundColor(!this.overtimeStop ? this.brandMain : $r('app.color.category_btn_bg'))
              .borderRadius(15)
              .margin({ right: 8, top: 8 })
              .onClick(() => {
                hapticTick();
                this.overtimeStop = false;
              })
            Text('停在总价')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.overtimeStop ? $r('app.color.text_white') : $r('app.color.text_primary'))
              .padding({ left: 14, right: 14, top: 7, bottom: 7 })
              .backgroundColor(this.overtimeStop ? this.brandMain : $r('app.color.category_btn_bg'))
              .borderRadius(15)
              .margin({ top: 8 })
              .onClick(() => {
                hapticTick();
                this.overtimeStop = true;
              })
          }
          .width('100%')
        }

        Text('备注（如：周末兼职）')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .alignSelf(ItemAlign.Start)
          .margin({ top: 14 })

        TextInput({ placeholder: '给这次赚钱取个名字（可选）', text: this.noteInput })
          .width('100%')
          .height(44)
          .fontSize(16)
          .borderRadius(12)
          .backgroundColor($r('app.color.card_bg'))
          .borderColor($r('app.color.border_color'))
          .borderWidth(1)
          .padding({ left: 16, right: 16 })
          .maxLength(20)
          .margin({ top: 8 })
          .onChange((val: string) => {
            this.noteInput = val;
          })

        Text('结束后')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .alignSelf(ItemAlign.Start)
          .margin({ top: 14 })

        Row() {
          Text('手动确认记账')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.endAction === 'manual' ? $r('app.color.text_white') : $r('app.color.text_primary'))
            .padding({ left: 12, right: 12, top: 7, bottom: 7 })
            .backgroundColor(this.endAction === 'manual' ? this.brandMain : $r('app.color.category_btn_bg'))
            .borderRadius(15)
            .margin({ right: 8, top: 8 })
            .onClick(() => {
              hapticTick();
              this.endAction = 'manual';
            })
          Text('自动记一笔')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.endAction === 'auto' ? $r('app.color.text_white') : $r('app.color.text_primary'))
            .padding({ left: 12, right: 12, top: 7, bottom: 7 })
            .backgroundColor(this.endAction === 'auto' ? this.brandMain : $r('app.color.category_btn_bg'))
            .borderRadius(15)
            .margin({ right: 8, top: 8 })
            .onClick(() => {
              hapticTick();
              this.endAction = 'auto';
            })
          Text('仅计时不记账')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.endAction === 'none' ? $r('app.color.text_white') : $r('app.color.text_primary'))
            .padding({ left: 12, right: 12, top: 7, bottom: 7 })
            .backgroundColor(this.endAction === 'none' ? this.brandMain : $r('app.color.category_btn_bg'))
            .borderRadius(15)
            .margin({ top: 8 })
            .onClick(() => {
              hapticTick();
              this.endAction = 'none';
            })
        }
        .width('100%')
      }
      .width('100%')
      .padding(16)
      .backgroundColor($r('app.color.card_bg'))
      .borderRadius(18)
      .border({ width: 1, color: $r('app.color.border_color') })
      .margin({ bottom: 14 })

      // ===== 开始按钮 =====
      Text('开始赚钱')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_white'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 15, bottom: 15 })
        .backgroundColor(this.brandMain)
        .borderRadius(16)
        .scale({
          x: this.pressedChipKey === 'start' ? 0.97 : 1,
          y: this.pressedChipKey === 'start' ? 0.97 : 1
        })
        .animation({ curve: MotionCurves.PRESS })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.pressedChipKey = 'start';
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.pressedChipKey = '';
          }
        })
        .onClick(() => {
          this.startSession();
        })
        .margin({ bottom: 20 })
    }
    .width('100%')
  }

  @Builder
  RunningBody() {
    Column() {
      // ===== 实时金额卡 =====
      Column() {
        Text(this.paused ? '已暂停' : '计时中，钱正在进账')
          .fontSize(13)
          .fontColor(this.paused ? $r('app.color.text_secondary') : $r('app.color.income_gold'))
          .margin({ top: 4 })

        Text('¥' + this.earnedDisplay.toFixed(2))
          .fontSize(48)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.income_gold'))
          .margin({ top: 6 })

        Text(formatDurationHMS(this.elapsedMs))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .margin({ top: 6 })

        if (this.plannedMs() > 0) {
          Progress({
            value: this.fixedPercent(),
            total: 100,
            type: ProgressType.Linear
          })
            .width('100%')
            .height(8)
            .color($r('app.color.income_gold'))
            .margin({ top: 14 })

          Text(this.fixedStatusText())
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 8 })
        }

        Divider()
          .color($r('app.color.border_color'))
          .margin({ top: 14, bottom: 10 })

        Row() {
          Text(this.perMinuteText())
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .layoutWeight(1)
          if (this.runningSession !== null) {
            Text(this.modeTextOf(this.runningSession))
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
          }
        }
        .width('100%')
      }
      .width('100%')
      .padding(16)
      .backgroundColor($r('app.color.card_bg'))
      .borderRadius(18)
      .border({ width: 1, color: $r('app.color.border_color') })
      .margin({ bottom: 14 })

      // ===== 操作行 =====
      Row() {
        Text(this.paused ? '继续' : '暂停')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .padding({ top: 14, bottom: 14 })
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius(16)
          .border({ width: 1, color: $r('app.color.border_color') })
          .scale({
            x: this.pressedChipKey === 'pause' ? 0.97 : 1,
            y: this.pressedChipKey === 'pause' ? 0.97 : 1
          })
          .animation({ curve: MotionCurves.PRESS })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              this.pressedChipKey = 'pause';
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.pressedChipKey = '';
            }
          })
          .onClick(() => {
            this.pauseResume();
          })

        Column()
          .width(12)

        Text('结束赚钱')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_white'))
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .padding({ top: 14, bottom: 14 })
          .backgroundColor($r('app.color.expense_red'))
          .borderRadius(16)
          .scale({
            x: this.pressedChipKey === 'end' ? 0.97 : 1,
            y: this.pressedChipKey === 'end' ? 0.97 : 1
          })
          .animation({ curve: MotionCurves.PRESS })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              this.pressedChipKey = 'end';
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.pressedChipKey = '';
            }
          })
          .onClick(() => {
            this.endSession();
          })
      }
      .width('100%')
      .margin({ bottom: 10 })

      Text('切到后台或锁屏都不会中断计时')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .margin({ bottom: 20 })
    }
    .width('100%')
  }

  @Builder
  ResultBody() {
    Column() {
      // ===== 结算卡 =====
      Column() {
        HandIcon({ name: 'moneybag', iconSize: 34 })
          .margin({ top: 4 })

        Text('本次共赚')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 8 })

        Text('¥' + this.resultAmount.toFixed(2))
          .fontSize(44)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.income_gold'))
          .margin({ top: 4 })

        Text(this.resultNote)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .margin({ top: 6 })

        Divider()
          .color($r('app.color.border_color'))
          .margin({ top: 14, bottom: 10 })

        Row() {
          Column() {
            Text('工作时长')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
            Text(formatDurationShort(this.resultDurationMs))
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Column() {
            Text('每分钟进账')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
            Text('¥' + this.resultPerMinute.toFixed(2))
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Column() {
            Text('计费方式')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
            Text(this.resultModeText)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .margin({ top: 4 })
          }
          .alignItems(HorizontalAlign.End)
          .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
      }
      .width('100%')
      .padding(16)
      .backgroundColor($r('app.color.card_bg'))
      .borderRadius(18)
      .border({ width: 1, color: $r('app.color.border_color') })
      .margin({ bottom: 14 })

      // ===== 入账区 =====
      if (this.resultBillId > 0) {
        Row() {
          HandIcon({ name: 'check', iconSize: 16 })
          Text('已记入当前账本')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.income_gold'))
            .margin({ left: 6 })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ top: 14, bottom: 14 })
        .backgroundColor($r('app.color.category_btn_bg'))
        .borderRadius(16)
        .margin({ bottom: 14 })
      } else if (this.endAction === 'none') {
        Text('本次仅计时，未记入账本')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .margin({ bottom: 14 })
      } else {
        Text('记一笔收入')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_white'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 14, bottom: 14 })
          .backgroundColor($r('app.color.income_gold'))
          .borderRadius(16)
          .scale({
            x: this.pressedChipKey === 'record_bill' ? 0.97 : 1,
            y: this.pressedChipKey === 'record_bill' ? 0.97 : 1
          })
          .animation({ curve: MotionCurves.PRESS })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              this.pressedChipKey = 'record_bill';
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.pressedChipKey = '';
            }
          })
          .onClick(() => {
            this.recordBillFromResult();
          })
          .margin({ bottom: 14 })
      }

      // ===== 操作行 =====
      Row() {
        Text('再来一次')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .padding({ top: 14, bottom: 14 })
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius(16)
          .border({ width: 1, color: $r('app.color.border_color') })
          .scale({
            x: this.pressedChipKey === 'again' ? 0.97 : 1,
            y: this.pressedChipKey === 'again' ? 0.97 : 1
          })
          .animation({ curve: MotionCurves.PRESS })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              this.pressedChipKey = 'again';
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.pressedChipKey = '';
            }
          })
          .onClick(() => {
            hapticTick();
            this.pageState = 'setup';
          })

        Column()
          .width(12)

        Text('完成')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_white'))
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .padding({ top: 14, bottom: 14 })
          .backgroundColor(this.brandMain)
          .borderRadius(16)
          .scale({
            x: this.pressedChipKey === 'done' ? 0.97 : 1,
            y: this.pressedChipKey === 'done' ? 0.97 : 1
          })
          .animation({ curve: MotionCurves.PRESS })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              this.pressedChipKey = 'done';
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.pressedChipKey = '';
            }
          })
          .onClick(() => {
            this.pathStack.pop();
          })
      }
      .width('100%')
      .margin({ bottom: 20 })
    }
    .width('100%')
  }

  @Builder
  HistorySection() {
    Column() {
      Row() {
        HandIcon({ name: 'hourglass', iconSize: 16 })
        Text('赚钱记录')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 5 })
      }
      .width('100%')
      .margin({ bottom: 10 })

      // 统计行
      Row() {
        Column() {
          Text('累计已赚')
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
          Text('¥' + this.historyTotalAmount.toFixed(2))
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.income_gold'))
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Column() {
          Text('累计时长')
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
          Text(formatDurationShort(this.historyTotalMs))
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Column() {
          Text('计时次数')
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
          Text(this.historyRecords.length.toString())
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.End)
        .layoutWeight(1)
      }
      .width('100%')
      .padding(14)
      .backgroundColor($r('app.color.card_bg'))
      .borderRadius(16)
      .border({ width: 1, color: $r('app.color.border_color') })
      .margin({ bottom: 10 })

      if (this.historyRecords.length === 0) {
        Column() {
          Text('还没有赚钱记录')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
          Text('设定时薪，开始第一段赚钱计时吧')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 4 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ top: 26, bottom: 26 })
        .backgroundColor($r('app.color.card_bg'))
        .borderRadius(18)
        .border({ width: 1, color: $r('app.color.border_color') })
      } else {
        ForEach(this.historyRecords, (item: EarningRecord) => {
          Row() {
            Column() {
              Text(item.note.length > 0 ? item.note : '计时收入')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Text(`${formatRecordTime(item.startTime)} · ${formatDurationShort(item.durationMs)}` +
                (item.billId > 0 ? ' · 已入账' : ''))
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .margin({ top: 3 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Text('¥' + item.amount.toFixed(2))
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.income_gold'))

            SymbolGlyph($r('sys.symbol.trash'))
              .fontSize(16)
              .fontColor([$r('app.color.text_secondary')])
              .margin({ left: 12 })
              .onClick(() => {
                this.removeRecord(item.id);
              })
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 12, bottom: 12 })
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius(14)
          .border({ width: 1, color: $r('app.color.border_color') })
          .margin({ bottom: 8 })
        }, (item: EarningRecord) =>
        item.id.toString() + '_' + item.amount.toFixed(2) + '_' + item.billId.toString())
      }
    }
    .width('100%')
  }

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
              .scale({
                x: this.pressedChipKey === 'back' ? 0.8 : 1,
                y: this.pressedChipKey === 'back' ? 0.8 : 1
              })
              .animation({ curve: MotionCurves.PRESS })
              .onTouch((event: TouchEvent) => {
                if (event.type === TouchType.Down) {
                  this.pressedChipKey = 'back';
                } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                  this.pressedChipKey = '';
                }
              })
              .onClick(() => {
                if (this.pageState === 'running' && !this.paused) {
                  this.showLeaveDialog();
                } else {
                  this.pathStack.pop();
                }
              })
              .margin({ right: 8 })

            Text('赚钱计时')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)

            if (this.pageState === 'running') {
              Text('进行中')
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.income_gold'))
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .backgroundColor($r('app.color.category_btn_bg'))
                .borderRadius(10)
            }
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: this.statusBarVp + 20, bottom: 16 })

          Divider()
            .color($r('app.color.border_color'))
            .height(1)

          Scroll() {
            Column() {
              if (this.pageState === 'setup') {
                this.SetupBody()
              } else if (this.pageState === 'running') {
                this.RunningBody()
              } else {
                this.ResultBody()
              }

              this.HistorySection()

              // 底部手势条避让
              Column()
                .width('100%')
                .height(this.navBarVp + 44)
            }
            .width('100%')
            .padding({ left: 20, right: 20 })
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
        }
        .width('100%')
        .layoutWeight(1)
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
    .onBackPressed(() => {
      if (this.pageState === 'running' && !this.paused) {
        this.showLeaveDialog();
        return true;
      }
      return false;
    })
  }
}

// 系统路由表（router_map.json）构建入口：导航栈按 name 路由到此页
@Builder
export function EarningTimerPageBuilder(name: string, param: object) {
  if (name === 'EarningTimerPage') {
    EarningTimerPage()
  }
}
