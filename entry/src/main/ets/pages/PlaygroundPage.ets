import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import dataPreferences from '@ohos.data.preferences';
import { loadEggCoins } from '../common/Gameplay';
import { LedgerItem, DEFAULT_LEDGER_ID, AnimationConfig } from './Index';
import { HandIcon } from '../common/HandIcon';
import { MotionCurves } from '../common/Motion';
import {
  CheckInData,
  loadCheckIn,
  claimCheckInReward,
  checkFullMonthBonus,
  checkInRewardOf,
  MoneyTreeData,
  loadTree,
  plantTree,
  accrueTree,
  harvestTree,
  TREE_PLANT_COST,
  TREE_STAGE_DAYS,
  TREE_COINS_CAP,
  BlindBoxTier,
  BLIND_BOX_TIERS,
  BlindBoxStateData,
  loadBlindBoxState,
  getBlindBoxCost,
  drawBlindBox,
  GuardianData,
  loadGuardian,
  claimGuardianReward,
  GUARDIAN_REWARD,
  NoSpendData,
  loadNoSpend,
  settleNoSpend,
  setNoSpendLimit,
  claimNoSpendReward,
  loadPlaygroundLedgerId,
  savePlaygroundLedgerId
} from '../common/GameplayPlus';

// ========== 玩法乐园：签到日历 / 摇钱树 / 记账盲盒机 / 预算守护战 / 无消费日挑战 ==========
@Entry
@Component
struct PlaygroundPage {
  @StorageProp('brand_main') brandMain: string = '#4E6EF2';
  @StorageProp('brand_tint') brandTint: string = '#EEF1FE';
  @StorageProp('isWideScreen') isWideScreen: boolean = false;
  @State @Watch('onEggCoinsChanged') eggCoins: number = 0;
  @State checkIn: CheckInData | null = null;
  @State tree: MoneyTreeData | null = null;
  @State boxState: BlindBoxStateData | null = null;
  @State boxCosts: number[] = [];
  @State guardian: GuardianData | null = null;
  @State noSpend: NoSpendData | null = null;
  @State limitInput: string = '';
  @State ledgers: LedgerItem[] = [];
  @State selectedLedgerId: number = DEFAULT_LEDGER_ID;
  @State ledgerChosen: boolean = false;
  @State headerIn: boolean = false;
  @State contentReady: boolean = false;
  @State eggBadgeScale: number = 1;
  @State treeSway: number = -4;
  @State guardianBob: number = 0;
  @State boxBob: number = 0;
  @State betaPulse: number = 1;
  @State pressedTag: string = '';
  @State pressedChipKey: string = '';  // 按压中的胶囊按钮 key（Q弹缩放反馈）
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;

  async aboutToAppear(): Promise<void> {
    // 灵动待机动画：摇钱树摇摆 / 吞金兽悬浮 / 盲盒起伏 / Beta 徽标呼吸
    animateTo({ duration: 1500, curve: Curve.EaseInOut, iterations: -1, playMode: PlayMode.Alternate }, () => {
      this.treeSway = 4;
    });
    animateTo({ duration: 1200, curve: Curve.EaseInOut, iterations: -1, playMode: PlayMode.Alternate }, () => {
      this.guardianBob = -5;
    });
    animateTo({ duration: 1300, curve: Curve.EaseInOut, iterations: -1, playMode: PlayMode.Alternate }, () => {
      this.boxBob = -4;
    });
    animateTo({ duration: 900, curve: Curve.EaseInOut, iterations: -1, playMode: PlayMode.Alternate }, () => {
      this.betaPulse = 1.1;
    });
    // 标题栏滑入
    setTimeout(() => {
      this.headerIn = true;
    }, 50);
    await this.loadLedgers();
    const saved = await loadPlaygroundLedgerId(this.context);
    let savedValid = false;
    for (const l of this.ledgers) {
      if (l.id === saved) {
        savedValid = true;
        break;
      }
    }
    if (savedValid) {
      // 用上次选择的账本直接进入
      this.selectedLedgerId = saved;
      this.ledgerChosen = true;
      await this.enterPlayground();
    } else if (this.ledgers.length <= 1) {
      // 只有一个账本：直接进入，不弹选择
      this.selectedLedgerId = this.ledgers.length === 1 ? this.ledgers[0].id : DEFAULT_LEDGER_ID;
      this.ledgerChosen = true;
      await savePlaygroundLedgerId(this.context, this.selectedLedgerId);
      await this.enterPlayground();
    } else {
      // 多账本且首次进入：先选账本（默认高亮当前账本）
      this.selectedLedgerId = await this.loadCurrentLedgerId();
    }
  }

  async loadLedgers(): Promise<void> {
    try {
      const prefs = await dataPreferences.getPreferences(this.context, 'bill_data');
      const data = await prefs.get('ledgers_key', '[]') as string;
      this.ledgers = JSON.parse(data) as LedgerItem[];
    } catch (e) {
      console.error('读取账本列表失败', e);
      this.ledgers = [];
    }
  }

  async loadCurrentLedgerId(): Promise<number> {
    try {
      const prefs = await dataPreferences.getPreferences(this.context, 'bill_data');
      const data = await prefs.get('current_ledger_id', '') as string;
      if (data.length > 0) {
        const id = parseInt(data, 10);
        if (!isNaN(id)) {
          return id;
        }
      }
    } catch (e) {
      console.error('读取当前账本失败', e);
    }
    return DEFAULT_LEDGER_ID;
  }

  // 选定账本后的进入流程：按该账本结算 + 加载
  async enterPlayground(): Promise<void> {
    await settleNoSpend(this.context, this.selectedLedgerId);
    await accrueTree(this.context, this.selectedLedgerId);
    const bonus = await checkFullMonthBonus(this.context, this.selectedLedgerId);
    if (bonus > 0) {
      this.getUIContext().getPromptAction().showToast({ message: `本月满勤！奖励 ${bonus} 鸡蛋币已到账`, duration: 2500 });
    }
    await this.loadAll();
  }

  // 首次弹窗中选定账本
  async onPickLedger(id: number): Promise<void> {
    this.selectedLedgerId = id;
    this.ledgerChosen = true;
    await savePlaygroundLedgerId(this.context, id);
    await this.enterPlayground();
  }

  // 顶部切换账本：切换后按新账本完整结算加载
  async onSwitchLedger(id: number): Promise<void> {
    if (id === this.selectedLedgerId) {
      return;
    }
    this.selectedLedgerId = id;
    this.limitInput = '';
    await savePlaygroundLedgerId(this.context, id);
    await this.enterPlayground();
  }

  async loadAll(): Promise<void> {
    this.eggCoins = await loadEggCoins(this.context);
    this.checkIn = await loadCheckIn(this.context, this.selectedLedgerId);
    this.tree = await loadTree(this.context, this.selectedLedgerId);
    this.boxState = await loadBlindBoxState(this.context, this.selectedLedgerId);
    const costs: number[] = [];
    for (const tier of BLIND_BOX_TIERS) {
      costs.push(await getBlindBoxCost(this.context, this.selectedLedgerId, tier.id));
    }
    this.boxCosts = costs;
    this.guardian = await loadGuardian(this.context, this.selectedLedgerId);
    this.noSpend = await loadNoSpend(this.context, this.selectedLedgerId);
    if (this.limitInput.length === 0 && this.noSpend !== null && this.noSpend.limit > 0) {
      this.limitInput = String(this.noSpend.limit);
    }
    // 五张卡片交错浮入：数据就绪后触发一次
    if (!this.contentReady) {
      setTimeout(() => {
        this.contentReady = true;
      }, 80);
    }
  }

  // 鸡蛋币数量变化：徽章 Q 弹放大再回弹
  onEggCoinsChanged(): void {
    animateTo({ duration: 150, curve: AnimationConfig.SPRING }, () => {
      this.eggBadgeScale = 1.28;
    });
    setTimeout(() => {
      animateTo({ duration: 320, curve: AnimationConfig.SPRING }, () => {
        this.eggBadgeScale = 1;
      });
    }, 150);
  }

  // 胶囊按钮按压反馈：按下缩小、松开回弹
  onTouchPress(tag: string, event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.pressedTag = tag;
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.pressedTag = '';
    }
  }

  isPressed(tag: string): boolean {
    return this.pressedTag === tag;
  }

  // ---------- 签到日历 ----------
  calendarCells(): number[] {
    if (this.checkIn === null) {
      return [];
    }
    const cells: number[] = [];
    for (let i = 0; i < this.checkIn.firstWeekday; i++) {
      cells.push(0);
    }
    for (let d = 1; d <= this.checkIn.daysInMonth; d++) {
      cells.push(d);
    }
    return cells;
  }

  calendarRows(): number {
    if (this.checkIn === null) {
      return 0;
    }
    return Math.ceil((this.checkIn.firstWeekday + this.checkIn.daysInMonth) / 7);
  }

  isDayChecked(day: number): boolean {
    if (this.checkIn === null) {
      return false;
    }
    return this.checkIn.checkedDayNums.indexOf(day) !== -1;
  }

  async onClaimCheckIn(): Promise<void> {
    const reward = await claimCheckInReward(this.context, this.selectedLedgerId);
    if (reward > 0) {
      this.getUIContext().getPromptAction().showToast({ message: `签到奖励 ${reward} 鸡蛋币已到账`, duration: 1800 });
    } else {
      this.getUIContext().getPromptAction().showToast({ message: '今天记一笔账再来打卡哦', duration: 1500 });
    }
    await this.loadAll();
  }

  // ---------- 摇钱树 ----------
  async onPlantTree(): Promise<void> {
    const ok = await plantTree(this.context, this.selectedLedgerId);
    if (ok) {
      this.getUIContext().getPromptAction().showToast({ message: '种下了一棵摇钱树，每天记账浇水吧', duration: 2000 });
    } else {
      this.getUIContext().getPromptAction().showToast({ message: `鸡蛋币不够（需 ${TREE_PLANT_COST} 币）`, duration: 1500 });
    }
    await this.loadAll();
  }

  async onHarvestTree(): Promise<void> {
    const got = await harvestTree(this.context, this.selectedLedgerId);
    if (got > 0) {
      this.getUIContext().getPromptAction().showToast({ message: `收取 ${got} 鸡蛋币`, duration: 1800 });
    }
    await this.loadAll();
  }

  // ---------- 盲盒机 ----------
  async onDrawBox(tier: BlindBoxTier): Promise<void> {
    const result = await drawBlindBox(this.context, this.selectedLedgerId, tier.id);
    if (result === null) {
      this.getUIContext().getPromptAction().showToast({ message: '鸡蛋币不够啦', duration: 1500 });
      return;
    }
    const suffix: string = result.halfPrice ? '（今日半价）' : '';
    this.getUIContext().getPromptAction().showDialog({
      title: result.jackpot ? '彩蛋大奖！' : result.tierName,
      message: result.jackpot
        ? `开出 ${result.coins} 鸡蛋币！欧气爆棚！\n花费 ${result.cost} 币${suffix}`
        : `开出 ${result.coins} 鸡蛋币\n花费 ${result.cost} 币${suffix}`,
      buttons: [{ text: '收下', color: this.brandMain }]
    });
    await this.loadAll();
  }

  // ---------- 守护战 ----------
  async onClaimGuardian(): Promise<void> {
    const reward = await claimGuardianReward(this.context, this.selectedLedgerId);
    if (reward > 0) {
      this.getUIContext().getPromptAction().showToast({ message: `击败奖励 ${reward} 鸡蛋币 + 20 成长值`, duration: 2000 });
    }
    await this.loadAll();
  }

  // ---------- 无消费日 ----------
  async onSaveLimit(): Promise<void> {
    const v = parseFloat(this.limitInput.length > 0 ? this.limitInput : '0');
    if (isNaN(v) || v < 0) {
      this.getUIContext().getPromptAction().showToast({ message: '请输入有效的金额上限（可为 0）', duration: 1800 });
      return;
    }
    await setNoSpendLimit(this.context, this.selectedLedgerId, v);
    this.getUIContext().getPromptAction().showToast({ message: '每日消费上限已保存', duration: 1500 });
    await this.loadAll();
  }

  async onClaimNoSpend(): Promise<void> {
    const reward = await claimNoSpendReward(this.context, this.selectedLedgerId);
    if (reward > 0) {
      this.getUIContext().getPromptAction().showToast({ message: `节流奖励 ${reward} 鸡蛋币已到账`, duration: 1800 });
    }
    await this.loadAll();
  }

  selectedLedgerName(): string {
    for (const l of this.ledgers) {
      if (l.id === this.selectedLedgerId) {
        return l.name;
      }
    }
    return '默认账本';
  }

  @Builder
  TapeDeco() {
    Column()
      .width(44)
      .height(13)
      .backgroundColor($r('app.color.income_gold'))
      .opacity(0.45)
      .borderRadius(2)
      .rotate({ angle: -6 })
  }

  @Builder
  SquiggleDeco() {
    Image($r('app.media.hd_underline'))
      .width(52)
      .height(8)
      .objectFit(ImageFit.Fill)
  }

  // 全屏沉浸式布局：避让高度由 EntryAbility 发布到 AppStorage，头部内容与滚动内容在内部消化，
  // 页面背景/渐变延伸至状态栏与底部手势条下方，根节点不再整体留白
  @StorageProp('statusBarVp') statusBarVp: number = 46;
  @StorageProp('navBarVp') navBarVp: number = 28;

  build() {
    Stack() {
      Row() {
      Column() {
        // 沉浸式渐变头部：渐变延伸至状态栏，打造全面屏沉浸感
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
                router.back();
              })
              .margin({ right: 8 })

            Text('Beta')
              .fontSize(9)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_white'))
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(6)
              .backgroundColor(this.brandMain)
              .scale({ x: this.betaPulse, y: this.betaPulse })
              .margin({ right: 6 })

            Text('玩法乐园')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .overlay(this.SquiggleDeco(), { align: Alignment.Bottom, offset: { x: 0, y: 6 } })
              .layoutWeight(1)

            Row() {
              HandIcon({ name: 'egg', iconSize: 16 })
              Text(`${this.eggCoins}`)
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.income_gold'))
                .margin({ left: 4 })
            }
            .alignItems(VerticalAlign.Center)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(14)
            .backgroundColor($r('app.color.category_btn_bg'))
            .scale({ x: this.eggBadgeScale, y: this.eggBadgeScale })
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: this.statusBarVp + 20, bottom: 16 })
        }
        .width('100%')
        .linearGradient({
          angle: 180,
          colors: [[this.brandTint, 0], [$r('app.color.bg_main'), 1]]
        })
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
        .opacity(this.headerIn ? 1 : 0)
        .translate({ y: this.headerIn ? 0 : -16 })
        .animation({ duration: 420, curve: AnimationConfig.SPRING_SOFT })

        Scroll() {
          Column() {
            // 账本切换条：随内容一起滚动，消除与下方卡片的分裂感
            // （五个玩法进度均按所选账本独立记录）
            if (this.ledgers.length > 1 && this.ledgerChosen) {
              Scroll() {
                Row() {
                  ForEach(this.ledgers, (ledger: LedgerItem) => {
                    Text(ledger.name)
                      .fontSize(13)
                      .fontWeight(ledger.id === this.selectedLedgerId ? FontWeight.Medium : FontWeight.Normal)
                      .fontColor(ledger.id === this.selectedLedgerId ?
                      this.brandMain : $r('app.color.text_secondary'))
                      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                      .borderRadius(16)
                      .backgroundColor(ledger.id === this.selectedLedgerId ?
                      this.brandTint : $r('app.color.category_btn_bg'))
                      .margin({ right: 8 })
                      .onClick(() => { this.onSwitchLedger(ledger.id); })
                  }, (ledger: LedgerItem) =>
                  `${ledger.id}_${ledger.id === this.selectedLedgerId ? 'on' : 'off'}`)
                }
              }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
              .width('100%')
              .padding({ bottom: 12 })
              .opacity(this.contentReady ? 1 : 0)
              .translate({ y: this.contentReady ? 0 : 20 })
              .animation({ duration: 300, curve: AnimationConfig.SPRING_SOFT })
            }

            // ===== 卡片 1：每日签到 =====
            Column() {
              Row() {
              Row() {
                HandIcon({ name: 'calendar', iconSize: 17 })
                Text('每日签到')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                  .margin({ left: 5 })
              }
              .alignItems(VerticalAlign.Center)
                Blank()
                Text(`记一笔账即自动打卡 · ${this.selectedLedgerName()}`)
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
              }
              .width('100%')
              .margin({ bottom: 12 })

              // 星期表头
              Row() {
                Text('一').fontSize(11).fontColor($r('app.color.text_secondary')).layoutWeight(1).textAlign(TextAlign.Center)
                Text('二').fontSize(11).fontColor($r('app.color.text_secondary')).layoutWeight(1).textAlign(TextAlign.Center)
                Text('三').fontSize(11).fontColor($r('app.color.text_secondary')).layoutWeight(1).textAlign(TextAlign.Center)
                Text('四').fontSize(11).fontColor($r('app.color.text_secondary')).layoutWeight(1).textAlign(TextAlign.Center)
                Text('五').fontSize(11).fontColor($r('app.color.text_secondary')).layoutWeight(1).textAlign(TextAlign.Center)
                Text('六').fontSize(11).fontColor($r('app.color.text_secondary')).layoutWeight(1).textAlign(TextAlign.Center)
                Text('日').fontSize(11).fontColor($r('app.color.text_secondary')).layoutWeight(1).textAlign(TextAlign.Center)
              }
              .width('100%')
              .margin({ bottom: 6 })

              // 月历格子
              Grid() {
                ForEach(this.calendarCells(), (day: number, index: number) => {
                  GridItem() {
                    if (day === 0) {
                      Blank()
                    } else {
                      Column() {
                        Text(String(day))
                          .fontSize(13)
                          .fontWeight(this.checkIn !== null && day === this.checkIn.todayDayNum ?
                          FontWeight.Bold : FontWeight.Normal)
                          .fontColor(this.isDayChecked(day) ? $r('app.color.text_white') :
                          (this.checkIn !== null && day === this.checkIn.todayDayNum ?
                          this.brandMain : $r('app.color.text_secondary')))
                      }
                      .width(34)
                      .height(34)
                      .borderRadius(17)
                      .justifyContent(FlexAlign.Center)
                      .backgroundColor(this.isDayChecked(day) ? this.brandMain : Color.Transparent)
                      .border({
                        width: this.checkIn !== null && day === this.checkIn.todayDayNum && !this.isDayChecked(day) ?
                        1.5 : 0,
                        color: this.brandMain
                      })
                    }
                  }
                }, (day: number, index: number) => `${index}_${day}`)
              }
              .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr')
              .height(this.calendarRows() * 42)
              .width('100%')

              Row() {
                Column() {
                  if (this.checkIn !== null) {
                    Text(`连签 ${this.checkIn.streak} 天 · 累计 ${this.checkIn.totalDays} 天`)
                      .fontSize(13)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_primary'))
                    Text(`本月已签 ${this.checkIn.checkedDayNums.length}/${this.checkIn.daysInMonth} 天，满勤有大奖`)
                      .fontSize(11)
                      .fontColor($r('app.color.text_secondary'))
                      .margin({ top: 2 })
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                if (this.checkIn !== null && this.checkIn.todayChecked && !this.checkIn.todayClaimed) {
                  Text(`领取 +${checkInRewardOf(this.checkIn.streak)} 币`)
                    .fontSize(13)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_white'))
                    .backgroundColor(this.brandMain)
                    .borderRadius(16)
                    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                    .scale({ x: this.isPressed('checkin') ? 0.92 : 1, y: this.isPressed('checkin') ? 0.92 : 1 })
                    .animation({ curve: AnimationConfig.SPRING })
                    .onTouch((event: TouchEvent) => { this.onTouchPress('checkin', event); })
                    .onClick(() => { this.onClaimCheckIn(); })
                } else if (this.checkIn !== null && this.checkIn.todayClaimed) {
                  Text('今日已领 ✓')
                    .fontSize(12)
                    .fontColor($r('app.color.success_green'))
                    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
                }
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .margin({ top: 12 })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 16, bottom: 14 })
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius({ topLeft: 22, topRight: 19, bottomLeft: 21, bottomRight: 23 })
            .shadow({ radius: 0, color: $r('app.color.ink_shadow'), offsetX: 3, offsetY: 3 }).border({ width: 1, color: $r('app.color.ink_line') })
            .overlay(this.TapeDeco(), { align: Alignment.TopStart, offset: { x: 22, y: -7 } })
            .margin({ bottom: 8 })
            .opacity(this.contentReady ? 1 : 0)
            .translate({ y: this.contentReady ? 0 : 28 })
            .animation({ delay: 40, duration: 420, curve: AnimationConfig.SPRING_SOFT })

            // ===== 卡片 2：摇钱树 =====
            Column() {
              Row() {
              Row() {
                HandIcon({ name: 'tree', iconSize: 17 })
                Text('摇钱树养成')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                  .margin({ left: 5 })
              }
              .alignItems(VerticalAlign.Center)
                Blank()
                Text(`每天记账浇水，断签会枯萎 · ${this.selectedLedgerName()}`)
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
              }
              .width('100%')
              .margin({ bottom: 10 })

              if (this.tree === null || !this.tree.planted) {
                Row() {
                  HandIcon({ name: 'nut', iconSize: 34 })
                    .rotate({ angle: this.treeSway })
                  Column() {
                    Text('种一棵摇钱树吧')
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_primary'))
                    Text('连续浇水会长大，长成后每天掉鸡蛋币')
                      .fontSize(11)
                      .fontColor($r('app.color.text_secondary'))
                      .margin({ top: 2 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  .margin({ left: 12 })

                  Row() {
                    HandIcon({ name: 'egg', iconSize: 14 })
                    Text(`${TREE_PLANT_COST} 种树`)
                      .fontSize(13)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.eggCoins >= TREE_PLANT_COST ?
                      this.brandMain : $r('app.color.text_secondary'))
                      .margin({ left: 3 })
                  }
                  .alignItems(VerticalAlign.Center)
                  .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                  .borderRadius(14)
                  .backgroundColor(this.eggCoins >= TREE_PLANT_COST ?
                  this.brandTint : $r('app.color.category_btn_bg'))
                  .scale({ x: this.isPressed('plant') ? 0.92 : 1, y: this.isPressed('plant') ? 0.92 : 1 })
                  .animation({ curve: AnimationConfig.SPRING })
                  .onTouch((event: TouchEvent) => { this.onTouchPress('plant', event); })
                  .onClick(() => { this.onPlantTree(); })
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)
              } else {
                Row() {
                  HandIcon({ name: this.tree.stageEmoji, iconSize: 40 })
                    .rotate({ angle: this.treeSway })
                  Column() {
                    Text(`${this.tree.stageName} · 连续浇水 ${this.tree.streak} 天`)
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_primary'))
                    if (this.tree.nextStageDays > 0) {
                      Text(`再浇 ${this.tree.nextStageDays} 天进化`)
                        .fontSize(11)
                        .fontColor($r('app.color.text_secondary'))
                        .margin({ top: 2 })
                      Progress({
                        value: this.tree.streak - TREE_STAGE_DAYS[this.tree.stage],
                        total: this.tree.nextStageDays > 0 ?
                        (this.tree.nextStageDays + this.tree.streak - TREE_STAGE_DAYS[this.tree.stage]) : 1,
                        type: ProgressType.Linear
                      })
                      .width('100%')
                      .height(6)
                      .borderRadius(3)
                      .color(this.brandMain)
                      .margin({ top: 6 })
                    } else {
                      Text('已是最高形态，树上每天掉 4 币')
                        .fontSize(11)
                        .fontColor($r('app.color.income_gold'))
                        .margin({ top: 2 })
                    }
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  .margin({ left: 12 })

                  Column() {
                    Text(`树上 ${this.tree.coins} 币`)
                      .fontSize(11)
                      .fontColor($r('app.color.text_secondary'))
                    Text(this.tree.coins > 0 ? '摇一摇' : '还没长出')
                      .fontSize(13)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.tree.coins > 0 ?
                      $r('app.color.text_white') : $r('app.color.text_secondary'))
                      .backgroundColor(this.tree.coins > 0 ? this.brandMain : Color.Transparent)
                      .borderRadius(14)
                      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
                      .margin({ top: 4 })
                      .scale({ x: this.isPressed('harvest') ? 0.92 : 1, y: this.isPressed('harvest') ? 0.92 : 1 })
                      .animation({ curve: AnimationConfig.SPRING })
                      .onTouch((event: TouchEvent) => { this.onTouchPress('harvest', event); })
                      .onClick(() => { this.onHarvestTree(); })
                  }
                  .alignItems(HorizontalAlign.End)
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)

                if (this.tree.harvestCount > 0) {
                  Text(`累计收取 ${this.tree.harvestCount} 次 · 树上最多攒 ${TREE_COINS_CAP} 币`)
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ top: 8 })
                }
              }
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 16, bottom: 14 })
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius({ topLeft: 22, topRight: 19, bottomLeft: 21, bottomRight: 23 })
            .shadow({ radius: 0, color: $r('app.color.ink_shadow'), offsetX: 3, offsetY: 3 }).border({ width: 1, color: $r('app.color.ink_line') })
            .overlay(this.TapeDeco(), { align: Alignment.TopStart, offset: { x: 22, y: -7 } })
            .margin({ bottom: 8 })
            .opacity(this.contentReady ? 1 : 0)
            .translate({ y: this.contentReady ? 0 : 28 })
            .animation({ delay: 110, duration: 420, curve: AnimationConfig.SPRING_SOFT })

            // ===== 卡片 3：记账盲盒机 =====
            Column() {
              Row() {
              Row() {
                HandIcon({ name: 'gift', iconSize: 17 })
                Text('记账盲盒机')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                  .margin({ left: 5 })
              }
              .alignItems(VerticalAlign.Center)
                Blank()
                Text(this.boxState !== null && this.boxState.halfPriceToday ? '今日首次抽盒半价！' : '明天再来享半价')
                  .fontSize(11)
                  .fontColor(this.boxState !== null && this.boxState.halfPriceToday ?
                  $r('app.color.income_gold') : $r('app.color.text_secondary'))
              }
              .width('100%')
              .margin({ bottom: 8 })

              ForEach(BLIND_BOX_TIERS, (tier: BlindBoxTier, index: number) => {
                Row() {
                  HandIcon({ name: tier.emoji, iconSize: 26 })
                    .translate({ y: this.boxBob })
                  Column() {
                    Text(tier.name)
                      .fontSize(14)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_primary'))
                    Text(`普通 ${tier.min1}~${tier.max1} 币 · 稀有 ${tier.min2}~${tier.max2} 币 · 彩蛋 ${tier.jackpot} 币`)
                      .fontSize(11)
                      .fontColor($r('app.color.text_secondary'))
                      .margin({ top: 2 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  .margin({ left: 10 })

                  Row() {
                    if (this.boxCosts.length > index && this.boxCosts[index] < tier.cost) {
                      Text('半价')
                        .fontSize(12)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(this.eggCoins >= (this.boxCosts.length > index ? this.boxCosts[index] : tier.cost) ?
                        this.brandMain : $r('app.color.text_secondary'))
                    }
                    HandIcon({ name: 'egg', iconSize: 13 })
                    Text(this.boxCosts.length > index && this.boxCosts[index] < tier.cost ?
                    `${this.boxCosts[index]}` : `${tier.cost} 开盒`)
                      .fontSize(12)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.eggCoins >= (this.boxCosts.length > index ? this.boxCosts[index] : tier.cost) ?
                      this.brandMain : $r('app.color.text_secondary'))
                      .margin({ left: 3 })
                  }
                  .alignItems(VerticalAlign.Center)
                  .padding({ left: 10, right: 10, top: 7, bottom: 7 })
                  .borderRadius(14)
                  .backgroundColor(this.eggCoins >= (this.boxCosts.length > index ? this.boxCosts[index] : tier.cost) ?
                  this.brandTint : $r('app.color.category_btn_bg'))
                  .scale({
                    x: this.isPressed('box_' + tier.id) ? 0.92 : 1,
                    y: this.isPressed('box_' + tier.id) ? 0.92 : 1
                  })
                  .animation({ curve: AnimationConfig.SPRING })
                  .onTouch((event: TouchEvent) => { this.onTouchPress('box_' + tier.id, event); })
                  .onClick(() => { this.onDrawBox(tier); })
                }
                .width('100%')
                .padding({ top: 8, bottom: 8 })
                .alignItems(VerticalAlign.Center)
              }, (tier: BlindBoxTier, index: number) =>
              tier.id + (this.boxCosts.length > index && this.boxCosts[index] < tier.cost ? '_half' : '_full'))

              if (this.boxState !== null && this.boxState.draws > 0) {
                Text(`累计开盒 ${this.boxState.draws} 次 · 中彩蛋 ${this.boxState.jackpots} 次 · ${this.selectedLedgerName()}`)
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
                  .margin({ top: 4 })
              }
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 16, bottom: 12 })
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius({ topLeft: 22, topRight: 19, bottomLeft: 21, bottomRight: 23 })
            .shadow({ radius: 0, color: $r('app.color.ink_shadow'), offsetX: 3, offsetY: 3 }).border({ width: 1, color: $r('app.color.ink_line') })
            .overlay(this.TapeDeco(), { align: Alignment.TopStart, offset: { x: 22, y: -7 } })
            .margin({ bottom: 8 })
            .opacity(this.contentReady ? 1 : 0)
            .translate({ y: this.contentReady ? 0 : 28 })
            .animation({ delay: 180, duration: 420, curve: AnimationConfig.SPRING_SOFT })

            // ===== 卡片 4：预算守护战 =====
            Column() {
              Row() {
              Row() {
                HandIcon({ name: 'swords', iconSize: 17 })
                Text('预算守护战')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                  .margin({ left: 5 })
              }
              .alignItems(VerticalAlign.Center)
                Blank()
                Text(`每周一只吞金兽 · ${this.selectedLedgerName()}`)
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
              }
              .width('100%')
              .margin({ bottom: 10 })

              if (this.guardian !== null) {
                Row() {
                  HandIcon({ name: this.guardian.defeated ? 'skull' : 'monster', iconSize: 34 })
                    .translate({ y: this.guardianBob })
                  Column() {
                    Text(this.guardian.defeated ? '吞金兽已被击败！' : `吞金兽 HP ${this.guardian.hp}/${this.guardian.maxHp}`)
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_primary'))
                    Text(`本周支出 ¥${this.guardian.weeklyExpense.toFixed(0)} / 周预算 ¥${this.guardian.weeklyBudget.toFixed(0)}`)
                      .fontSize(11)
                      .fontColor($r('app.color.text_secondary'))
                      .margin({ top: 2 })
                    Progress({
                      value: this.guardian.hp,
                      total: this.guardian.maxHp,
                      type: ProgressType.Linear
                    })
                    .width('100%')
                    .height(6)
                    .borderRadius(3)
                    .color($r('app.color.expense_red'))
                    .margin({ top: 6 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  .margin({ left: 12 })

                  if (this.guardian.defeated && !this.guardian.rewarded) {
                    Text(`领取 ${GUARDIAN_REWARD} 币`)
                      .fontSize(13)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_white'))
                      .backgroundColor($r('app.color.success_green'))
                      .borderRadius(16)
                      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                      .scale({ x: this.isPressed('guardian') ? 0.92 : 1, y: this.isPressed('guardian') ? 0.92 : 1 })
                      .animation({ curve: AnimationConfig.SPRING })
                      .onTouch((event: TouchEvent) => { this.onTouchPress('guardian', event); })
                      .onClick(() => { this.onClaimGuardian(); })
                  } else if (this.guardian.defeated) {
                    Text('已领奖 ✓')
                      .fontSize(12)
                      .fontColor($r('app.color.success_green'))
                      .padding({ left: 8, right: 8, top: 8, bottom: 8 })
                  }
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)

                Text(this.guardian.defeated ?
                `下周一刷新新一只吞金兽（累计击败 ${this.guardian.defeatedCount} 只）` :
                '预算内每记一笔支出对它造成伤害，超预算它会回血')
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
                  .margin({ top: 8 })
              }
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 16, bottom: 14 })
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius({ topLeft: 22, topRight: 19, bottomLeft: 21, bottomRight: 23 })
            .shadow({ radius: 0, color: $r('app.color.ink_shadow'), offsetX: 3, offsetY: 3 }).border({ width: 1, color: $r('app.color.ink_line') })
            .overlay(this.TapeDeco(), { align: Alignment.TopStart, offset: { x: 22, y: -7 } })
            .margin({ bottom: 8 })
            .opacity(this.contentReady ? 1 : 0)
            .translate({ y: this.contentReady ? 0 : 28 })
            .animation({ delay: 250, duration: 420, curve: AnimationConfig.SPRING_SOFT })

            // ===== 卡片 5：无消费日挑战 =====
            Column() {
              Row() {
              Row() {
                HandIcon({ name: 'ban', iconSize: 17 })
                Text('无消费日挑战')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                  .margin({ left: 5 })
              }
              .alignItems(VerticalAlign.Center)
                Blank()
                Text(`支出不超上限即为节流日 · ${this.selectedLedgerName()}`)
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
              }
              .width('100%')
              .margin({ bottom: 10 })

              if (this.noSpend !== null) {
                // 上限设置
                Row() {
                  Text('每日消费上限')
                    .fontSize(13)
                    .fontColor($r('app.color.text_primary'))
                  TextInput({
                    placeholder: this.noSpend.limit > 0 ? String(this.noSpend.limit) : '0（完全不消费）',
                    text: this.limitInput
                  })
                    .type(InputType.NUMBER_DECIMAL)
                    .fontSize(13)
                    .height(36)
                    .backgroundColor($r('app.color.category_btn_bg'))
                    .borderRadius(8)
                    .padding({ left: 10, right: 10 })
                    .width(110)
                    .margin({ left: 10 })
                    .onChange((val: string) => { this.limitInput = val; })
                  Text('¥')
                    .fontSize(13)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ left: 6 })
                  Blank()
                  Text('保存')
                    .fontSize(13)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.brandMain)
                    .padding({ left: 12, right: 12, top: 7, bottom: 7 })
                    .borderRadius(14)
                    .backgroundColor(this.brandTint)
                    .scale({ x: this.isPressed('save') ? 0.92 : 1, y: this.isPressed('save') ? 0.92 : 1 })
                    .animation({ curve: AnimationConfig.SPRING })
                    .onTouch((event: TouchEvent) => { this.onTouchPress('save', event); })
                    .onClick(() => { this.onSaveLimit(); })
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)

                Row() {
                  Column() {
                    Row() {
                      HandIcon({ name: 'flame', iconSize: 15 })
                      Text(`连击 ${this.noSpend.streak} 天 · 最佳 ${this.noSpend.bestStreak} 天`)
                        .fontSize(14)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.text_primary'))
                        .margin({ left: 4 })
                    }
                    .alignItems(VerticalAlign.Center)
                    Text(`今天已花 ¥${this.noSpend.todayExpense.toFixed(2)} ${this.noSpend.todayQualified ? '✓ 达标中' : '✗ 已超上限'}`)
                      .fontSize(11)
                      .fontColor(this.noSpend.todayQualified ?
                      $r('app.color.success_green') : $r('app.color.expense_red'))
                      .margin({ top: 2 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  if (this.noSpend.pendingReward > 0) {
                    Text(`领取 +${this.noSpend.pendingReward} 币`)
                      .fontSize(13)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_white'))
                      .backgroundColor($r('app.color.income_gold'))
                      .borderRadius(16)
                      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                      .scale({ x: this.isPressed('nospend') ? 0.92 : 1, y: this.isPressed('nospend') ? 0.92 : 1 })
                      .animation({ curve: AnimationConfig.SPRING })
                      .onTouch((event: TouchEvent) => { this.onTouchPress('nospend', event); })
                      .onClick(() => { this.onClaimNoSpend(); })
                  }
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)
                .margin({ top: 12 })

                Text('节流日按天自动结算（昨天及以前），连续天数越多单日奖励越高（5~30 币）')
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
                  .margin({ top: 8 })
              }
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 16, bottom: 14 })
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius({ topLeft: 22, topRight: 19, bottomLeft: 21, bottomRight: 23 })
            .shadow({ radius: 0, color: $r('app.color.ink_shadow'), offsetX: 3, offsetY: 3 }).border({ width: 1, color: $r('app.color.ink_line') })
            .overlay(this.TapeDeco(), { align: Alignment.TopStart, offset: { x: 22, y: -7 } })
            .margin({ bottom: 8 })
            .opacity(this.contentReady ? 1 : 0)
            .translate({ y: this.contentReady ? 0 : 28 })
            .animation({ delay: 320, duration: 420, curve: AnimationConfig.SPRING_SOFT })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: this.navBarVp + 24 })
          // 内容根节点同步扩展：与外层 Scroll 构成完整 expandSafeArea 链，
          // 使卡片内容可滚入底部手势条区域（文档场景二模式）
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
        }
        .layoutWeight(1)
        .width('100%')
        .edgeEffect(EdgeEffect.Spring)
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        // 视口扩展进底部系统栏：内容可滚入手势条区域，消除导航条处空白
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
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      // 首次进入：选择账本弹层（五个玩法进度均按所选账本独立记录）
      if (!this.ledgerChosen && this.ledgers.length > 1) {
        Column() {
          Column() {
            Text('选择账本')
              .fontSize(19)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Text('五个玩法将分别记录每个账本的进度，之后可随时在顶部切换')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .textAlign(TextAlign.Center)
              .margin({ top: 8, bottom: 4 })

            ForEach(this.ledgers, (ledger: LedgerItem) => {
              Text(ledger.name)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(ledger.id === this.selectedLedgerId ?
                this.brandMain : $r('app.color.text_primary'))
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding({ top: 14, bottom: 14 })
                .borderRadius(14)
                .backgroundColor(ledger.id === this.selectedLedgerId ?
                this.brandTint : $r('app.color.category_btn_bg'))
                .margin({ top: 10 })
                .onClick(() => { this.onPickLedger(ledger.id); })
            }, (ledger: LedgerItem) => ledger.id.toString())
          }
          .width('84%')
          .constraintSize({ maxWidth: 420 })
          .padding(20)
          .borderRadius(24)
          .backgroundColor($r('app.color.card_bg'))
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.scale({ x: 0.92, y: 0.92 }))
            .animation({ curve: AnimationConfig.SPRING_SOFT }))
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.5)')
        .justifyContent(FlexAlign.Center)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .transition(TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut }))
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_main'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

}
