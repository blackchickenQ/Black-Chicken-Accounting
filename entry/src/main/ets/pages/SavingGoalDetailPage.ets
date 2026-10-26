import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import dataPreferences from '@ohos.data.preferences';
import { hapticTick } from '../common/Haptics';
import { HandIcon } from '../common/HandIcon';
import { AnimationConfig, BillItem, DEFAULT_LEDGER_ID } from './Index';
import { SavingGoal, GoalRecord, GoalDetailParams, SavingGoalDialog } from './WealthTab';
import { MotionCurves } from '../common/Motion';
import {
  markDailyTask,
  getChallengeTemplate,
  getChallengeCurrentPeriod,
  getChallengePeriodAmount,
  getChallengePlannedTotal,
  ChallengeTemplate
} from '../common/Gameplay';

// ========== 快捷金额 chip（独立组件：@Prop 选中态才随父组件刷新） ==========
@Component
struct AmountChip {
  @StorageProp('brand_main') brandMain: string = '#4E6EF2';
  @Prop selected: boolean = false;
  label: string = '';
  onTap: () => void = () => {};

  build() {
    Text(this.label)
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.selected ? $r('app.color.text_white') : $r('app.color.text_primary'))
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .backgroundColor(this.selected ? this.brandMain : $r('app.color.category_btn_bg'))
      .borderRadius(18)
      .margin({ right: 8, bottom: 8 })
      .onClick(() => { this.onTap(); })
  }
}

// ========== 存入弹窗：快捷金额 + 自定义金额 + 备注 ==========
@CustomDialog
struct GoalDepositDialog {
  @StorageProp('brand_main') brandMain: string = '#4E6EF2';
  controller: CustomDialogController = new CustomDialogController({
    builder: () => {}
  });
  @State quickAmount: number = 0;   // 选中的快捷金额，0 = 未选
  @State customAmount: string = '';
  @State note: string = '';
  quickOptions: number[] = [10, 50, 100, 500, 1000];
  onConfirm: (amount: number, note: string) => void = () => {};
  onCancel?: () => void;

  build() {
    Column() {
      Text('存入一笔')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .alignSelf(ItemAlign.Start)
        .margin({ bottom: 6 })

      Text('选择快捷金额或输入自定义金额')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .alignSelf(ItemAlign.Start)
        .margin({ bottom: 14 })

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.quickOptions, (opt: number) => {
          AmountChip({
            label: '+' + opt.toString(),
            selected: this.quickAmount === opt,
            onTap: () => {
              animateTo({ duration: 150, curve: AnimationConfig.SPRING_SOFT }, () => {
                this.quickAmount = opt;
              });
              this.customAmount = '';
            }
          })
        }, (opt: number) => opt.toString() + (this.quickAmount === opt ? '_1' : '_0'))
      }
      .width('100%')
      .margin({ bottom: 8 })

      TextInput({ placeholder: '自定义金额（元）', text: this.customAmount })
        .width('100%')
        .height(44)
        .fontSize(16)
        .borderRadius(12)
        .backgroundColor($r('app.color.card_bg'))
        .borderColor($r('app.color.border_color'))
        .borderWidth(1)
        .padding({ left: 16, right: 16 })
        .type(InputType.NUMBER_DECIMAL)
        .onChange((val: string) => {
          this.customAmount = val;
          if (val.length > 0) {
            this.quickAmount = 0;
          }
        })
        .margin({ bottom: 12 })

      // 存入时可顺手写日记，与金额合成一条旅程记录
      Text('写点日记（可选）')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .alignSelf(ItemAlign.Start)
        .margin({ bottom: 6 })

      TextArea({ placeholder: '记录这笔钱背后的故事、坚持的理由…', text: this.note })
        .width('100%')
        .height(80)
        .fontSize(15)
        .borderRadius(12)
        .backgroundColor($r('app.color.card_bg'))
        .borderColor($r('app.color.border_color'))
        .borderWidth(1)
        .maxLength(300)
        .onChange((val: string) => { this.note = val; })
        .margin({ bottom: 20 })

      Row() {
        Button('取消')
          .backgroundColor('transparent')
          .fontColor($r('app.color.text_secondary'))
          .borderRadius(20)
          .height(40)
          .layoutWeight(1)
          .onClick(() => { this.onCancel?.(); })

        Blank().width(16)

        Button('存入')
          .backgroundColor(this.brandMain)
          .fontColor($r('app.color.text_white'))
          .borderRadius(22)
          .height(44)
          .layoutWeight(1)
          .onClick(() => {
            let amount = 0;
            if (this.quickAmount > 0) {
              amount = this.quickAmount;
            } else {
              const raw = parseFloat(this.customAmount);
              if (isNaN(raw) || raw <= 0) {
                promptAction.showToast({ message: '请选择或输入有效金额', duration: 1500 });
                return;
              }
              amount = Math.round(raw * 100) / 100;
            }
            this.onConfirm(amount, this.note.trim());
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

// ========== 日记弹窗：心得感悟 ==========
@CustomDialog
struct GoalDiaryDialog {
  @StorageProp('brand_main') brandMain: string = '#4E6EF2';
  controller: CustomDialogController = new CustomDialogController({
    builder: () => {}
  });
  @State text: string = '';
  onConfirm: (note: string) => void = () => {};
  onCancel?: () => void;

  build() {
    Column() {
      Text('写日记')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .alignSelf(ItemAlign.Start)
        .margin({ bottom: 14 })

      TextArea({ placeholder: '记录此刻的想法、坚持的理由、离目标又近了一步的喜悦…', text: this.text })
        .width('100%')
        .height(120)
        .fontSize(15)
        .borderRadius(12)
        .backgroundColor($r('app.color.card_bg'))
        .borderColor($r('app.color.border_color'))
        .borderWidth(1)
        .maxLength(300)
        .onChange((val: string) => { this.text = val; })
        .margin({ bottom: 20 })

      Row() {
        Button('取消')
          .backgroundColor('transparent')
          .fontColor($r('app.color.text_secondary'))
          .borderRadius(20)
          .height(40)
          .layoutWeight(1)
          .onClick(() => { this.onCancel?.(); })

        Blank().width(16)

        Button('保存')
          .backgroundColor(this.brandMain)
          .fontColor($r('app.color.text_white'))
          .borderRadius(22)
          .height(44)
          .layoutWeight(1)
          .onClick(() => {
            const note = this.text.trim();
            if (note.length === 0) {
              promptAction.showToast({ message: '写点什么再保存吧', duration: 1500 });
              return;
            }
            this.onConfirm(note);
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

// ========== 存钱目标详情页：进度总览 + 一键存入 + 日记心得 + 攒钱旅程 ==========
@Entry
@Component
struct SavingGoalDetailPage {
  @StorageProp('brand_main') brandMain: string = '#4E6EF2';
  @StorageProp('brand_tint') brandTint: string = '#EEF1FE';
  // 宽屏断点（全局）：平板/折叠屏下内容限宽居中
  @StorageProp('isWideScreen') isWideScreen: boolean = false;
  @State goalId: number = 0;
  @State goalName: string = '';
  @State goalTarget: number = 0;
  @State goalSaved: number = 0;
  @State goalDeadline: number = 0;
  @State goalChallengeType: string = '';
  @State goalChallengeStart: number = 0;
  @State goalBillOnDeposit: boolean = false;  // 每笔存入同步记一笔支出账单
  @State goalRemindChallenge: boolean = false; // 每期（每天/每周）在提醒中心提醒应存金额
  @State records: GoalRecord[] = [];
  // 动画状态：环形进度插值 / 金额滚动 / 金额弹跳 / 达成庆祝 / 旅程揭示
  @State ringValue: number = 0;
  @State savedDisplay: number = 0;
  @State savedPopScale: number = 1;
  @State celebrating: boolean = false;
  @State timelineReady: boolean = false;
  @State pressedChipKey: string = '';  // 按压中的胶囊按钮 key（Q弹缩放反馈）
  private countTimer: number = -1;
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;
  private depositDialog: CustomDialogController | null = null;
  private diaryDialog: CustomDialogController | null = null;

  async aboutToAppear(): Promise<void> {
    const params = router.getParams() as GoalDetailParams;
    if (params && params.id) {
      this.goalId = params.id;
    }
    await this.loadGoal();
  }

  aboutToDisappear(): void {
    if (this.countTimer >= 0) {
      clearInterval(this.countTimer);
      this.countTimer = -1;
    }
  }

  // 从本地读取目标；目标已被删除时退回财富页
  async loadGoal(): Promise<void> {
    try {
      const prefs = await dataPreferences.getPreferences(this.context, 'bill_data');
      const data = await prefs.get('saving_goals', '[]') as string;
      const parsed = JSON.parse(data) as SavingGoal[];
      const found = parsed.find((g: SavingGoal): boolean => g.id === this.goalId);
      if (found === undefined) {
        promptAction.showToast({ message: '目标不存在或已删除', duration: 1500 });
        router.back();
        return;
      }
      this.goalName = found.name;
      this.goalTarget = found.target;
      this.goalSaved = found.saved;
      this.goalDeadline = found.deadline ? found.deadline : 0;
      this.goalChallengeType = found.challengeType ? found.challengeType : '';
      this.goalChallengeStart = found.challengeStart ? found.challengeStart : 0;
      this.goalBillOnDeposit = found.billOnDeposit ? found.billOnDeposit : false;
      this.goalRemindChallenge = found.remindChallenge ? found.remindChallenge : false;
      const list = found.records ? found.records : [];
      this.records = list.slice().sort((a: GoalRecord, b: GoalRecord): number => b.time - a.time);
      this.playSavedAnimation();
      // 旅程列表数据就绪后再挂载，触发逐条交错入场
      setTimeout(() => {
        animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
          this.timelineReady = true;
        });
      }, 80);
    } catch (e) {
      console.error('加载存钱目标详情失败', e);
    }
  }

  // 把当前页面状态写回偏好存储，并通知财富页刷新
  async persistGoal(): Promise<void> {
    try {
      const prefs = await dataPreferences.getPreferences(this.context, 'bill_data');
      const data = await prefs.get('saving_goals', '[]') as string;
      const parsed = JSON.parse(data) as SavingGoal[];
      const list: SavingGoal[] = parsed.map((g: SavingGoal): SavingGoal => {
        if (g.id !== this.goalId) {
          return g;
        }
        return {
          id: g.id,
          name: this.goalName,
          target: this.goalTarget,
          saved: this.goalSaved,
          deadline: this.goalDeadline,
          records: this.records,
          challengeType: this.goalChallengeType.length > 0 ? this.goalChallengeType : undefined,
          challengeStart: this.goalChallengeStart > 0 ? this.goalChallengeStart : undefined,
          billOnDeposit: this.goalBillOnDeposit ? true : undefined,
          remindChallenge: this.goalRemindChallenge ? true : undefined
        };
      });
      await prefs.put('saving_goals', JSON.stringify(list));
      await prefs.flush();
    } catch (e) {
      console.error('保存存钱目标详情失败', e);
    }
    // 置位刷新信号：财富页回到前台时重载目标列表并刷新提醒角标
    const flag = (AppStorage.get<number>('shouldRefreshWealth') || 0) + 1;
    AppStorage.setOrCreate('shouldRefreshWealth', flag);
  }

  // ---------- 展示辅助 ----------
  percent(): number {
    if (this.goalTarget <= 0) {
      return 0;
    }
    const p = Math.floor(this.goalSaved / this.goalTarget * 100);
    if (p < 0) {
      return 0;
    }
    if (p > 100) {
      return 100;
    }
    return p;
  }

  isDone(): boolean {
    return this.goalSaved >= this.goalTarget;
  }

  remaining(): number {
    return Math.max(0, Math.round((this.goalTarget - this.goalSaved) * 100) / 100);
  }

  deadlineText(): string {
    if (this.goalDeadline <= 0) {
      return '未设截止日期，慢慢攒也可以';
    }
    const days = Math.ceil((this.goalDeadline - Date.now()) / 86400000);
    const d = new Date(this.goalDeadline);
    const dateStr = `${d.getMonth() + 1}月${d.getDate()}日`;
    if (days < 0) {
      return `已于 ${dateStr} 过截止日`;
    }
    if (days === 0) {
      return '今天截止';
    }
    return `距 ${dateStr} 截止还有 ${days} 天`;
  }

  deadlineColor(): ResourceColor {
    if (this.goalDeadline <= 0) {
      return $r('app.color.text_secondary');
    }
    const days = Math.ceil((this.goalDeadline - Date.now()) / 86400000);
    if (days < 0) {
      return $r('app.color.expense_red');
    }
    if (days <= 7) {
      return $r('app.color.budget_orange');
    }
    return $r('app.color.text_secondary');
  }

  formatTime(ts: number): string {
    const d = new Date(ts);
    const hh = d.getHours().toString().padStart(2, '0');
    const mm = d.getMinutes().toString().padStart(2, '0');
    return `${d.getFullYear()}年${d.getMonth() + 1}月${d.getDate()}日 ${hh}:${mm}`;
  }

  // ---------- 挑战进度 ----------
  challengeTemplate(): ChallengeTemplate | null {
    if (this.goalChallengeType.length === 0 || this.goalChallengeStart <= 0) {
      return null;
    }
    return getChallengeTemplate(this.goalChallengeType);
  }

  // 本期期数（1 起）
  challengePeriod(): number {
    const tpl = this.challengeTemplate();
    if (tpl === null) {
      return 0;
    }
    return getChallengeCurrentPeriod(tpl, this.goalChallengeStart);
  }

  // ---------- 动画 ----------
  // 环形进度扫入 + 已存金额滚动 + 金额弹跳，一次存入/删除/编辑后都复用
  playSavedAnimation(): void {
    animateTo({ duration: 700, curve: Curve.EaseOut }, () => {
      this.ringValue = this.percent();
    });
    const target = this.goalSaved;
    const from = this.savedDisplay;
    if (this.countTimer >= 0) {
      clearInterval(this.countTimer);
      this.countTimer = -1;
    }
    const start = Date.now();
    this.countTimer = setInterval(() => {
      const t = Math.min(1, (Date.now() - start) / 700);
      const eased = 1 - Math.pow(1 - t, 3);
      this.savedDisplay = Math.round((from + (target - from) * eased) * 100) / 100;
      if (t >= 1) {
        clearInterval(this.countTimer);
        this.countTimer = -1;
      }
    }, 34);
    animateTo({ duration: 180, curve: AnimationConfig.SPRING }, () => {
      this.savedPopScale = 1.18;
    });
    setTimeout(() => {
      animateTo({ duration: 300, curve: AnimationConfig.SPRING }, () => {
        this.savedPopScale = 1;
      });
    }, 160);
  }

  // 达成庆祝：彩带 + 提示
  celebrate(): void {
    hapticTick();
    this.celebrating = true;
    promptAction.showToast({ message: '目标达成！这段攒钱旅程圆满了', duration: 2500 });
    setTimeout(() => {
      this.celebrating = false;
    }, 3200);
  }

  // ---------- 操作 ----------
  openDepositDialog(): void {
    this.depositDialog = new CustomDialogController({
      builder: GoalDepositDialog({
        onConfirm: (amount: number, note: string) => {
          this.addDeposit(amount, note);
          this.depositDialog?.close();
        },
        onCancel: () => { this.depositDialog?.close(); }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true,
      maskColor: 'rgba(0, 0, 0, 0.4)'
    });
    this.depositDialog.open();
  }

  openDiaryDialog(): void {
    this.diaryDialog = new CustomDialogController({
      builder: GoalDiaryDialog({
        onConfirm: (note: string) => {
          this.addDiary(note);
          this.diaryDialog?.close();
        },
        onCancel: () => { this.diaryDialog?.close(); }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true,
      maskColor: 'rgba(0, 0, 0, 0.4)'
    });
    this.diaryDialog.open();
  }

  // 一键存入：累计已存金额 + 旅程插入一条记录；首次达成时庆祝
  async addDeposit(amount: number, note: string): Promise<void> {
    const before = this.percent();
    const record: GoalRecord = { id: Date.now(), amount: amount, note: note, time: Date.now() };
    hapticTick();
    animateTo({ curve: AnimationConfig.SPRING }, () => {
      this.records = [record, ...this.records];
      this.goalSaved = Math.round((this.goalSaved + amount) * 100) / 100;
    });
    this.playSavedAnimation();
    if (before < 100 && this.percent() >= 100) {
      setTimeout(() => { this.celebrate(); }, 700);
    }
    await this.persistGoal();
    // 存钱 = 完成今日任务（幂等）
    await markDailyTask(this.context, 'deposit');
    // 开启「计入收支」的挑战：每笔存入同步记一笔支出账单
    if (this.goalBillOnDeposit) {
      await this.recordDepositBill(amount);
    }
  }

  // 把存入金额写成一笔「存钱」支出账单（直接落库 + 信号通知首页刷新账单列表）
  private async recordDepositBill(amount: number): Promise<void> {
    try {
      const prefs = await dataPreferences.getPreferences(this.context, 'bill_data');
      const billsData = await prefs.get('bills_key', '[]') as string;
      const bills = JSON.parse(billsData) as BillItem[];
      const ledgerIdStr = await prefs.get('current_ledger_id', '') as string;
      const ledgerId = ledgerIdStr.length > 0 ? parseInt(ledgerIdStr, 10) : DEFAULT_LEDGER_ID;
      const bill: BillItem = {
        id: Date.now(),
        name: `存入·${this.goalName}`,
        amount: amount,
        type: '支出',
        date: Date.now(),
        category: '存钱',
        source: '现金',
        tags: [],
        ledgerId: isNaN(ledgerId) ? DEFAULT_LEDGER_ID : ledgerId,
        photoUris: []
      };
      bills.unshift(bill);
      await prefs.put('bills_key', JSON.stringify(bills));
      await prefs.flush();
      // 通知首页重新加载账单（与回收站恢复账单同一信号模式）
      AppStorage.setOrCreate('shouldRefreshBills', Date.now());
    } catch (e) {
      console.error('存入记账失败', e);
    }
  }

  // 写日记：纯心得记录，不影响金额
  async addDiary(note: string): Promise<void> {
    const record: GoalRecord = { id: Date.now(), amount: 0, note: note, time: Date.now() };
    hapticTick();
    animateTo({ curve: AnimationConfig.SPRING }, () => {
      this.records = [record, ...this.records];
    });
    await this.persistGoal();
  }

  // 删除旅程记录：存入记录同步扣减已存金额
  async deleteRecord(record: GoalRecord): Promise<void> {
    const rest = this.records.filter((r: GoalRecord): boolean => r.id !== record.id);
    animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
      this.records = rest;
      if (record.amount > 0) {
        this.goalSaved = Math.max(0, Math.round((this.goalSaved - record.amount) * 100) / 100);
      }
    });
    hapticTick();
    this.playSavedAnimation();
    await this.persistGoal();
  }

  // 编辑目标：复用财富页的存钱目标编辑弹窗
  openEditDialog(): void {
    const useWan = this.goalTarget >= 10000;
    const controller = new CustomDialogController({
      builder: SavingGoalDialog({
        title: '编辑存钱目标',
        confirmText: '保存',
        inputName: this.goalName,
        inputTarget: useWan ? (this.goalTarget / 10000).toString() : this.goalTarget.toString(),
        inputSaved: useWan ? (this.goalSaved / 10000).toString() : this.goalSaved.toString(),
        deadline: this.goalDeadline,
        unitWan: useWan,
        onConfirm: (name: string, target: number, saved: number, deadline: number) => {
          this.goalName = name;
          this.goalTarget = target;
          this.goalSaved = saved;
          this.goalDeadline = deadline;
          this.playSavedAnimation();
          this.persistGoal();
          controller.close();
        },
        onCancel: () => { controller.close(); }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true,
      maskColor: 'rgba(0, 0, 0, 0.4)'
    });
    controller.open();
  }

  // 全屏沉浸式布局：状态栏/手势条避让高度由 EntryAbility 发布到 AppStorage，页面据此留白避让
  @StorageProp('statusBarVp') statusBarVp: number = 46;
  @StorageProp('navBarVp') navBarVp: number = 28;

  build() {
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
            router.back();
          })
          .margin({ right: 8 })

        Text(this.goalName)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        Image($r('sys.media.ohos_ic_public_edit'))
          .width(20)
          .height(20)
          .fillColor(this.brandMain)
          .scale({ x: this.pressedChipKey === 'edit' ? 0.8 : 1, y: this.pressedChipKey === 'edit' ? 0.8 : 1 })
          .animation({ curve: MotionCurves.PRESS })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              this.pressedChipKey = 'edit';
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.pressedChipKey = '';
            }
          })
          .onClick(() => { this.openEditDialog(); })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: this.statusBarVp + 20, bottom: 16 })

      Divider()
        .color($r('app.color.border_color'))
        .height(1)

      Scroll() {
        Column() {
          // ===== 进度总览卡 =====
          Stack({ alignContent: Alignment.Center }) {
            Column() {
              Row() {
                // 环形进度 + 达成庆祝彩带
                Stack({ alignContent: Alignment.Center }) {
                  Progress({ value: this.ringValue, total: 100, type: ProgressType.Ring })
                    .width(110)
                    .height(110)
                    .color(this.isDone() ? $r('app.color.income_gold') : this.brandMain)
                    .style({ strokeWidth: 10 })
                  Column() {
                    Text(this.percent().toString() + '%')
                      .fontSize(22)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.text_primary'))
                    Text(this.isDone() ? '已达成' : '完成度')
                      .fontSize(11)
                      .fontColor($r('app.color.text_secondary'))
                      .margin({ top: 2 })
                  }
                }

                Column() {
                  Text('已存入')
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                  Text('¥' + this.savedDisplay.toFixed(2))
                    .fontSize(26)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.income_gold'))
                    .scale({ x: this.savedPopScale, y: this.savedPopScale })
                    .margin({ top: 2 })
                  Text('目标 ¥' + this.goalTarget.toFixed(2))
                    .fontSize(13)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ top: 4 })
                  if (this.isDone()) {
                    Row() {
                      HandIcon({ name: 'party', iconSize: 14 })
                      Text('目标已达成，太棒了！')
                        .fontSize(13)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.income_gold'))
                        .margin({ left: 3 })
                    }
                    .alignItems(VerticalAlign.Center)
                    .margin({ top: 6 })
                  } else {
                    Text(`还差 ¥${this.remaining().toFixed(2)}`)
                      .fontSize(13)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.brandMain)
                      .margin({ top: 6 })
                  }
                  Text(this.deadlineText())
                    .fontSize(12)
                    .fontColor(this.deadlineColor())
                    .margin({ top: 2 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                .margin({ left: 18 })
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
            }
            .width('100%')

            // 达成庆祝彩带
            if (this.celebrating) {
              HandIcon({ name: 'party', iconSize: 26 })
                .offset({ x: -120, y: -58 })
              HandIcon({ name: 'sparkle', iconSize: 22 })
                .offset({ x: 116, y: -52 })
              HandIcon({ name: 'confetti', iconSize: 24 })
                .offset({ x: -108, y: 62 })
              HandIcon({ name: 'moneybag', iconSize: 20 })
                .offset({ x: 122, y: 58 })
            }
          }
          .width('100%')
          .padding(16)
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius({ topLeft: 22, topRight: 19, bottomLeft: 21, bottomRight: 23 })
          .shadow({ radius: 0, color: $r('app.color.ink_shadow'), offsetX: 3, offsetY: 3 }).border({ width: 1, color: $r('app.color.ink_line') })
          .margin({ top: 16 })

          // ===== 挑战进度卡（52周/30天挑战目标专属） =====
          if (this.challengeTemplate() !== null) {
            Column() {
              Row() {
                HandIcon({ name: this.challengeTemplate()?.emoji ?? 'target', iconSize: 18 })
                Text(this.challengeTemplate()?.name ?? '存钱挑战')
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary'))
                  .margin({ left: 6 })
                Blank()
                Text(`第 ${this.challengePeriod()} / ${this.challengeTemplate()?.periods} 期`)
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.income_gold'))
              }
              .width('100%')

              Row() {
                Column() {
                  Text('本期应存')
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                  Text('¥' + getChallengePeriodAmount(
                    this.challengeTemplate() as ChallengeTemplate, this.challengePeriod()).toFixed(0))
                    .fontSize(18)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.text_primary'))
                    .margin({ top: 2 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Column() {
                  Text('计划累计')
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                  Text('¥' + getChallengePlannedTotal(
                    this.challengeTemplate() as ChallengeTemplate, this.challengePeriod()).toFixed(0))
                    .fontSize(18)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.text_primary'))
                    .margin({ top: 2 })
                }
                .alignItems(HorizontalAlign.End)
              }
              .width('100%')
              .margin({ top: 12 })

              if (this.goalSaved >= getChallengePlannedTotal(
                this.challengeTemplate() as ChallengeTemplate, this.challengePeriod())) {
                Text('✓ 进度超前，太稳了！')
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.success_green'))
                  .margin({ top: 10 })
                  .alignSelf(ItemAlign.Start)
              } else {
                Row() {
                  HandIcon({ name: 'hourglass', iconSize: 13 })
                  Text(`落后计划 ¥${(getChallengePlannedTotal(
                    this.challengeTemplate() as ChallengeTemplate, this.challengePeriod()) -
                    this.goalSaved).toFixed(0)}，慢慢追上来`)
                    .fontSize(12)
                    .fontColor($r('app.color.budget_orange'))
                    .margin({ left: 4 })
                }
                .alignItems(VerticalAlign.Center)
                .margin({ top: 10 })
                .alignSelf(ItemAlign.Start)
              }

              if (this.goalBillOnDeposit) {
                Row() {
                  HandIcon({ name: 'receipt', iconSize: 12 })
                  Text('已开启：每笔存入将同步记一笔「存钱」支出账单')
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ left: 4 })
                }
                .alignItems(VerticalAlign.Center)
                .margin({ top: 8 })
                .alignSelf(ItemAlign.Start)
              }

              if (this.goalRemindChallenge) {
                Text('已开启每期提醒：本期应存金额会在提醒中心提醒')
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
                  .margin({ top: 6 })
                  .alignSelf(ItemAlign.Start)
              }
            }
            .width('100%')
            .padding(16)
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius({ topLeft: 22, topRight: 19, bottomLeft: 21, bottomRight: 23 })
            .shadow({ radius: 0, color: $r('app.color.ink_shadow'), offsetX: 3, offsetY: 3 }).border({ width: 1, color: $r('app.color.ink_line') })
            .margin({ top: 12 })
          }

          // ===== 操作行：一键存入 / 写日记 =====
          Row() {
            Row() {
              Text('＋ 存入一笔')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_white'))
            }
            .layoutWeight(1)
            .height(46)
            .justifyContent(FlexAlign.Center)
            .backgroundColor(this.brandMain)
            .borderRadius(23)
            .scale({ x: this.pressedChipKey === 'deposit' ? 0.92 : 1, y: this.pressedChipKey === 'deposit' ? 0.92 : 1 })
            .animation({ curve: MotionCurves.PRESS })
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) {
                this.pressedChipKey = 'deposit';
              } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                this.pressedChipKey = '';
              }
            })
            .onClick(() => { this.openDepositDialog(); })

            Blank().width(12)

            Row() {
              HandIcon({ name: 'note', iconSize: 15 })
              Text('写日记')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.brandMain)
                .margin({ left: 4 })
            }
            .alignItems(VerticalAlign.Center)
            .layoutWeight(1)
            .height(46)
            .justifyContent(FlexAlign.Center)
            .backgroundColor(this.brandTint)
            .borderRadius(23)
            .scale({ x: this.pressedChipKey === 'diary' ? 0.92 : 1, y: this.pressedChipKey === 'diary' ? 0.92 : 1 })
            .animation({ curve: MotionCurves.PRESS })
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) {
                this.pressedChipKey = 'diary';
              } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                this.pressedChipKey = '';
              }
            })
            .onClick(() => { this.openDiaryDialog(); })
          }
          .width('100%')
          .margin({ top: 14 })

          // 非挑战目标也可提示：开启计入后每笔存入会自动记账（挑战目标在进度卡内已有说明）
          if (this.goalBillOnDeposit && this.challengeTemplate() === null) {
            Row() {
              HandIcon({ name: 'receipt', iconSize: 12 })
              Text('已开启：每笔存入将同步记一笔「存钱」支出账单')
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
                .margin({ left: 4 })
            }
            .alignItems(VerticalAlign.Center)
            .margin({ top: 8 })
          }

          // ===== 攒钱旅程 =====
          Row() {
            Text('攒钱旅程')
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Blank()
            Text(`共 ${this.records.length} 条记录`)
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .margin({ top: 14, bottom: 8 })

          if (this.timelineReady) {
            if (this.records.length === 0) {
              Column() {
                HandIcon({ name: 'coin', iconSize: 30 })
                  .margin({ bottom: 6 })
                Text('旅程还没开始')
                  .fontSize(14)
                  .fontColor($r('app.color.text_secondary'))
                Text('存入第一笔钱，或写篇日记为攒钱加油')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .margin({ top: 4 })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Center)
              .padding({ top: 26, bottom: 26 })
              .backgroundColor($r('app.color.card_bg'))
              .borderRadius({ topLeft: 18, topRight: 15, bottomLeft: 17, bottomRight: 19 })
              .shadow({ radius: 0, color: $r('app.color.ink_shadow'), offsetX: 3, offsetY: 3 }).border({ width: 1, color: $r('app.color.ink_line') })
            } else {
              // 时间轴：存入金色节点，日记灰色节点；存入附带的日记与金额同卡展示
              Column() {
                ForEach(this.records, (r: GoalRecord, index: number) => {
                  Row() {
                    // 时间轴节点 + 连接线
                    Column() {
                      Circle({ width: 10, height: 10 })
                        .fill(r.amount > 0 ? $r('app.color.income_gold') : $r('app.color.text_secondary'))
                      if (index < this.records.length - 1) {
                        Column()
                          .width(2)
                          .layoutWeight(1)
                          .backgroundColor($r('app.color.border_color'))
                      }
                    }
                    .width(20)
                    .alignItems(HorizontalAlign.Center)
                    .alignSelf(ItemAlign.Stretch)
                    .margin({ right: 10 })

                    Column() {
                      // 金额/类型与时间同行展示，压缩单条记录高度
                      Row() {
                        if (r.amount > 0) {
                          Text('存入 ¥' + r.amount.toFixed(2))
                            .fontSize(15)
                            .fontWeight(FontWeight.Bold)
                            .fontColor($r('app.color.income_gold'))
                        } else {
                          Text('心得')
                            .fontSize(13)
                            .fontWeight(FontWeight.Medium)
                            .fontColor($r('app.color.text_secondary'))
                        }
                        Blank()
                        Text(this.formatTime(r.time))
                          .fontSize(10)
                          .fontColor($r('app.color.text_secondary'))
                      }
                      .width('100%')

                      if (r.note.length > 0) {
                        // 日记内容：引用块样式，存入/纯日记通用
                        Text(r.note)
                          .fontSize(13)
                          .fontColor($r('app.color.text_secondary'))
                          .backgroundColor($r('app.color.category_btn_bg'))
                          .borderRadius(10)
                          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                          .margin({ top: 3 })
                      }
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)

                    SymbolGlyph($r('sys.symbol.xmark'))
                      .fontSize(13)
                      .fontColor([$r('app.color.text_secondary')])
                      .padding(8)
                      .margin({ right: -8 })
                      .onClick(() => { this.deleteRecord(r); })
                  }
                  .width('100%')
                  .padding({ top: 3, bottom: 3 })
                  .alignItems(VerticalAlign.Top)
                  .transition(TransitionEffect.OPACITY
                    .combine(TransitionEffect.translate({ x: -24 }))
                    .animation({ delay: index * 40, curve: AnimationConfig.SPRING_SOFT }))
                }, (r: GoalRecord) =>
                r.id.toString() + '_' + r.amount.toFixed(2) + '_' + r.time.toString() + '_' + r.note)
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: 10, bottom: 10 })
              .backgroundColor($r('app.color.card_bg'))
              .borderRadius({ topLeft: 18, topRight: 15, bottomLeft: 17, bottomRight: 19 })
              .shadow({ radius: 0, color: $r('app.color.ink_shadow'), offsetX: 3, offsetY: 3 }).border({ width: 1, color: $r('app.color.ink_line') })
            }
          }

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
