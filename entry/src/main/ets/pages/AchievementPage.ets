import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import dataPreferences from '@ohos.data.preferences';
import { hapticTick } from '../common/Haptics';
import { HandIcon } from '../common/HandIcon';
import { AnimationConfig } from './Index';
import { MotionCurves } from '../common/Motion';
import {
  ACHIEVEMENT_DEFS,
  getLevelInfo,
  getCriteriaValue,
  loadXp,
  loadUnlocked,
  checkAndUnlock,
  buildCriteriaFromPrefs,
  getChickStage,
  CHICK_STAGES,
  AchievementDef,
  AchievementCriteria,
  ChickStage
} from '../common/Achievements';
import {
  DAILY_TASK_DEFS,
  SCENE_DEFS,
  loadEggCoins,
  loadDailyTasks,
  claimDailyTask,
  markDailyTask,
  loadScenes,
  buyScene,
  useScene,
  getSceneDef,
  getStreakMultiplier,
  getMultiplierText,
  PiggyBankState,
  PIGGY_CAPACITY,
  loadPiggyBank,
  openPiggyBank,
  TravelDestination,
  TRAVEL_DESTINATIONS,
  TRAVEL_BOOST_HOURS,
  TravelState,
  loadTravel,
  startTravel,
  isTravelDone,
  claimTravelReward,
  getTravelDestination,
  FortuneState,
  loadFortune,
  drawFortune,
  claimFortuneReward,
  FORTUNE_LEVEL_NAMES,
  FORTUNE_LEVEL_EMOJI,
  FORTUNE_TASK_BILLS,
  FORTUNE_REWARDS,
  ReportBillInput,
  MonthlyReportData,
  buildMonthlyReport,
  DailyTaskDef,
  DailyTaskState,
  SceneDef,
  SceneState
} from '../common/Gameplay';

// ========== 小鸡养成页：小鸡舞台（等级/形态）+ 宝藏网格（原勋章墙） ==========
@Entry
@Component
struct AchievementPage {
  @StorageProp('brand_main') brandMain: string = '#4E6EF2';
  @StorageProp('brand_tint') brandTint: string = '#EEF1FE';
  @State userXp: number = 0;
  @State unlockedIds: string[] = [];
  // 成长值进度条填充动画值；宝藏网格就绪后才揭示，触发交错入场
  @State xpProgressValue: number = 0;
  @State gridReady: boolean = false;
  @State criteria: AchievementCriteria = {
    billCount: 0,
    incomeCount: 0,
    expenseTotal: 0,
    incomeTotal: 0,
    streakDays: 0,
    goalDoneCount: 0,
    hasBudget: false,
    creditCount: 0,
    guideDone: false
  };
  // ---------- 玩法状态：鸡蛋币 / 每日任务 / 鸡窝场景 ----------
  @State eggCoins: number = 0;
  @State taskDone: string[] = [];
  @State taskClaimed: string[] = [];
  @State sceneOwned: string[] = ['default'];
  @State sceneUsing: string = 'default';
  @State taskCardReady: boolean = false;
  @State stageViewIndex: number = 0;
  // ---------- 玩法状态：存钱罐 / 小鸡旅行 / 鸡运签 / 月度报告 ----------
  @State piggy: PiggyBankState = { coins: 0, capacity: PIGGY_CAPACITY };
  @State travel: TravelState | null = null;
  @State fortune: FortuneState | null = null;
  @State report: MonthlyReportData | null = null;
  @State piggyPop: number = 1;
  @State pressedChipKey: string = '';  // 按压中的胶囊按钮 key（Q弹缩放反馈）

  // ---------- 小鸡动画状态 ----------
  @State chickBreathe: number = 1;    // 待机呼吸缩放
  @State chickJumpY: number = 0;      // 点击跳跃位移
  @State chickRotate: number = 0;     // 摇摆/啄米角度
  @State chickScaleBoost: number = 1; // 进化瞬间放大
  @State betaPulse: number = 1;      // Beta 徽标呼吸缩放
  @State bubbleText: string = '';     // 台词气泡
  @State bubbleVisible: boolean = false;
  @State feeding: boolean = false;    // 喂食动画中
  @State feedY: number = -70;         // 米粒下落位移
  @State evolveGlow: boolean = false; // 进化金光
  @State celebrating: boolean = false; // 进化庆祝
  private bubbleTimer: number = -1;
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;

  async aboutToAppear(): Promise<void> {
    // 待机呼吸动画：1.0 ↔ 1.05 无限往复
    animateTo({ duration: 1300, curve: Curve.EaseInOut, iterations: -1, playMode: PlayMode.Alternate }, () => {
      this.chickBreathe = 1.05;
    });
    // Beta 徽标呼吸脉动
    animateTo({ duration: 900, curve: Curve.EaseInOut, iterations: -1, playMode: PlayMode.Alternate }, () => {
      this.betaPulse = 1.1;
    });
    await this.refreshData();
  }

  // 打开页面即全量重算：补算存钱目标 / 预算 / 信用账户类成就
  async refreshData(): Promise<void> {
    const criteria = await buildCriteriaFromPrefs(this.context);
    const fresh = await checkAndUnlock(this.context, criteria);
    this.criteria = criteria;
    this.userXp = await loadXp(this.context);
    this.unlockedIds = await loadUnlocked(this.context);
    // 形态查看初始定位到当前形态
    this.stageViewIndex = this.currentStage().stage - 1;
    // 成长值进度条平滑填充
    animateTo({ duration: 800, curve: Curve.EaseOut }, () => {
      this.xpProgressValue = this.getXpProgress();
    });
    // 宝藏网格交错揭示：数据就绪后再挂载
    if (!this.gridReady) {
      setTimeout(() => {
        animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
          this.gridReady = true;
        });
      }, 80);
    }
    if (fresh.length > 0) {
      const names: string[] = fresh.map((d: AchievementDef): string => d.name);
      promptAction.showToast({ message: `小鸡捡到新宝贝：${names.join('、')}！`, duration: 2500 });
    }
    // 玩法数据：鸡蛋币 / 每日任务 / 鸡窝场景（进来看看小鸡也算完成今日任务）
    const firstVisitToday = await markDailyTask(this.context, 'visit_chick');
    await this.refreshGameplayState();
    if (firstVisitToday) {
      this.showBubble('你来看我啦！今日任务 +1', 1800);
    }
    await this.checkEvolution();
  }

  // ---------- 玩法：鸡蛋币 / 每日任务 / 鸡窝场景 ----------
  async refreshGameplayState(): Promise<void> {
    this.eggCoins = await loadEggCoins(this.context);
    const tasks: DailyTaskState = await loadDailyTasks(this.context);
    this.taskDone = tasks.done;
    this.taskClaimed = tasks.claimed;
    const scenes: SceneState = await loadScenes(this.context);
    this.sceneOwned = scenes.owned;
    this.sceneUsing = scenes.using;
    // 新玩法：存钱罐 / 旅行 / 鸡运签 / 月度报告
    this.piggy = await loadPiggyBank(this.context);
    this.travel = await loadTravel(this.context);
    this.fortune = await loadFortune(this.context);
    await this.loadMonthlyReport();
    // 任务卡数据就绪后挂载，触发交错入场
    if (!this.taskCardReady) {
      setTimeout(() => {
        animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
          this.taskCardReady = true;
        });
      }, 60);
    }
  }

  isTaskDone(id: string): boolean {
    return this.taskDone.indexOf(id) !== -1;
  }

  isTaskClaimed(id: string): boolean {
    return this.taskClaimed.indexOf(id) !== -1;
  }

  // 领取任务奖励：鸡蛋币入账 + 弹跳提示
  async claimTask(id: string): Promise<void> {
    const reward = await claimDailyTask(this.context, id);
    if (reward > 0) {
      hapticTick();
      await this.refreshGameplayState();
      promptAction.showToast({ message: `+${reward} 鸡蛋币已入账！`, duration: 1800 });
    }
  }

  // ---------- 玩法：月度小鸡报告 ----------
  async loadMonthlyReport(): Promise<void> {
    try {
      const prefs = await dataPreferences.getPreferences(this.context, 'bill_data');
      const data = await prefs.get('bills_key', '[]') as string;
      const parsed = JSON.parse(data) as ReportBillInput[];
      this.report = buildMonthlyReport(parsed);
    } catch (e) {
      console.error('生成月度报告失败', e);
    }
  }

  // ---------- 玩法：每日鸡运签 ----------
  async onDrawFortune(): Promise<void> {
    hapticTick();
    const f = await drawFortune(this.context);
    this.fortune = f;
    promptAction.showToast({
      message: `今日运势：${FORTUNE_LEVEL_NAMES[f.level]}`,
      duration: 1800
    });
  }

  async onClaimFortune(): Promise<void> {
    const reward = await claimFortuneReward(this.context);
    if (reward > 0) {
      hapticTick();
      await this.refreshGameplayState();
      promptAction.showToast({ message: `好运奖励 +${reward} 鸡蛋币！`, duration: 1800 });
    }
  }

  // ---------- 玩法：幸运存钱罐 ----------
  async onOpenPiggy(): Promise<void> {
    const coins = await openPiggyBank(this.context);
    if (coins > 0) {
      hapticTick();
      animateTo({ curve: AnimationConfig.SPRING }, () => {
        this.piggyPop = 1.3;
      });
      setTimeout(() => {
        animateTo({ curve: AnimationConfig.SPRING }, () => {
          this.piggyPop = 1;
        });
      }, 280);
      await this.refreshGameplayState();
      promptAction.showToast({ message: `开罐啦！+${coins} 鸡蛋币！`, duration: 2000 });
    }
  }

  // ---------- 玩法：小鸡旅行 ----------
  travelProgress(): number {
    const t = this.travel;
    if (t === null) {
      return 0;
    }
    const total = Math.max(1, t.endTs - t.startTs);
    const p = Math.round((Date.now() - t.startTs) / total * 100);
    return Math.min(100, Math.max(0, p));
  }

  travelRemainHours(): number {
    const t = this.travel;
    if (t === null) {
      return 0;
    }
    return Math.max(0, Math.ceil((t.endTs - Date.now()) / 3600000));
  }

  onStartTravel(dest: TravelDestination): void {
    if (this.eggCoins < dest.cost) {
      promptAction.showToast({ message: '鸡蛋币不够啦，完成每日任务赚币吧', duration: 1800 });
      return;
    }
    promptAction.showDialog({
      title: '小鸡旅行',
      message: `花 ${dest.cost} 鸡蛋币送小鸡去「${dest.name}」？旅途中每记一笔账，归来提前 ${TRAVEL_BOOST_HOURS} 小时。`,
      buttons: [
        { text: '再想想', color: $r('app.color.text_secondary') },
        { text: '出发', color: $r('app.color.income_gold') }
      ]
    }).then((result) => {
      if (result.index === 1) {
        startTravel(this.context, dest.id).then((ok: boolean): void => {
          if (!ok) {
            promptAction.showToast({ message: '出发失败，稍后再试', duration: 1500 });
            return;
          }
          hapticTick();
          this.refreshGameplayState();
          promptAction.showToast({ message: `小鸡出发去「${dest.name}」啦！`, duration: 1800 });
        });
      }
    }).catch(() => {});
  }

  async onClaimTravel(): Promise<void> {
    const state = this.travel;
    if (state === null) {
      return;
    }
    const dest = getTravelDestination(state.destId);
    const reward = await claimTravelReward(this.context);
    if (reward > 0) {
      hapticTick();
      await this.refreshGameplayState();
      this.showBubble(`我回来啦！还带了${dest.souvenir}～`, 3000);
      promptAction.showToast({
        message: `旅行归来！+${reward} 鸡蛋币，还带了${dest.souvenir}`,
        duration: 3000
      });
    }
  }

  // 点场景格：已拥有则切换使用，未拥有则花鸡蛋币购买（购买后自动使用）
  onSceneTap(def: SceneDef): void {
    if (this.sceneOwned.indexOf(def.id) !== -1) {
      hapticTick();
      useScene(this.context, def.id).then((): void => {
        this.refreshGameplayState();
        promptAction.showToast({ message: `小鸡搬进「${def.name}」啦`, duration: 1500 });
      });
      return;
    }
    if (this.eggCoins < def.price) {
      promptAction.showToast({ message: '鸡蛋币不够啦，完成每日任务赚币吧', duration: 1800 });
      return;
    }
    promptAction.showDialog({
      title: '装修鸡窝',
      message: `花 ${def.price} 鸡蛋币解锁「${def.name}」场景？`,
      buttons: [
        { text: '取消', color: $r('app.color.text_secondary') },
        { text: '解锁', color: $r('app.color.income_gold') }
      ]
    }).then((result) => {
      if (result.index === 1) {
        buyScene(this.context, def.id).then((ok: boolean): void => {
          if (!ok) {
            promptAction.showToast({ message: '购买失败，稍后再试', duration: 1500 });
            return;
          }
          useScene(this.context, def.id).then((): void => {
            hapticTick();
            this.refreshGameplayState();
            promptAction.showToast({ message: `已解锁「${def.name}」，小鸡住进新家！`, duration: 1800 });
          });
        });
      }
    }).catch(() => {});
  }

  // 到下一级的进度百分比（满级为 100）
  getXpProgress(): number {
    const info = getLevelInfo(this.userXp);
    if (info.maxed) {
      return 100;
    }
    const span = info.nextLevelXp - info.curLevelXp;
    if (span <= 0) {
      return 0;
    }
    return Math.min(100, Math.max(0, (this.userXp - info.curLevelXp) / span * 100));
  }

  // ---------- 小鸡成长辅助 ----------
  currentStage(): ChickStage {
    return getChickStage(getLevelInfo(this.userXp).level);
  }

  // 当前使用的鸡窝场景（未知 id 兜底为草地鸡窝）
  currentScene(): SceneDef {
    return getSceneDef(this.sceneUsing);
  }

  isMaxed(): boolean {
    return getLevelInfo(this.userXp).maxed;
  }

  // 检测形态进化：与上次进入页面时的形态序号比较
  async checkEvolution(): Promise<void> {
    const stage = this.currentStage();
    try {
      const prefs = await dataPreferences.getPreferences(this.context, 'bill_data');
      const last = await prefs.get('chick_last_stage', 0) as number;
      if (stage.stage > last) {
        if (last > 0) {
          this.playEvolution();
        } else {
          // 首次进入小鸡页：打个招呼
          this.showBubble('你好呀，我是你的小鸡！', 2200);
        }
        await prefs.put('chick_last_stage', stage.stage);
        await prefs.flush();
      }
    } catch (e) {
      console.error('检查小鸡进化失败', e);
    }
  }

  // 进化动画：摇晃蓄力 → 金光爆闪 → 放大回弹 + 庆祝
  playEvolution(): void {
    hapticTick();
    animateTo({ duration: 120, curve: Curve.EaseInOut }, () => { this.chickRotate = -12; });
    setTimeout(() => {
      animateTo({ duration: 120, curve: Curve.EaseInOut }, () => { this.chickRotate = 12; });
    }, 130);
    setTimeout(() => {
      animateTo({ duration: 120, curve: Curve.EaseInOut }, () => { this.chickRotate = -12; });
    }, 260);
    setTimeout(() => {
      animateTo({ duration: 120, curve: Curve.EaseInOut }, () => { this.chickRotate = 12; });
    }, 390);
    setTimeout(() => {
      hapticTick();
      animateTo({ duration: 250, curve: AnimationConfig.SPRING }, () => {
        this.chickRotate = 0;
        this.chickScaleBoost = 1.35;
        this.evolveGlow = true;
      });
    }, 520);
    setTimeout(() => {
      animateTo({ duration: 420, curve: AnimationConfig.SPRING_SOFT }, () => {
        this.chickScaleBoost = 1;
      });
      this.celebrating = true;
      this.showBubble('进化啦！我是' + this.currentStage().name + '！', 2600);
      promptAction.showToast({ message: '小鸡进化：' + this.currentStage().name, duration: 2500 });
    }, 790);
    setTimeout(() => {
      this.celebrating = false;
      this.evolveGlow = false;
    }, 3800);
  }

  // 台词气泡：显示一段时间后淡出
  showBubble(text: string, duration: number): void {
    this.bubbleText = text;
    this.bubbleVisible = true;
    if (this.bubbleTimer >= 0) {
      clearTimeout(this.bubbleTimer);
    }
    this.bubbleTimer = setTimeout(() => {
      animateTo({ duration: 250 }, () => { this.bubbleVisible = false; });
    }, duration);
  }

  // 点击小鸡：蛋形态摇一摇，其余形态跳一下 + 随机台词
  onChickTap(): void {
    if (this.feeding) {
      return;
    }
    hapticTick();
    const stage: ChickStage = this.currentStage();
    const line: string = stage.tapLines[Math.floor(Math.random() * stage.tapLines.length)];
    this.showBubble(line, 1600);
    if (stage.stage === 1) {
      animateTo({ duration: 130, curve: Curve.EaseInOut }, () => { this.chickRotate = -10; });
      setTimeout(() => {
        animateTo({ duration: 220, curve: AnimationConfig.SPRING }, () => { this.chickRotate = 0; });
      }, 140);
      return;
    }
    animateTo({ duration: 200, curve: AnimationConfig.SPRING }, () => {
      this.chickJumpY = -22;
      this.chickRotate = Math.random() > 0.5 ? 9 : -9;
    });
    setTimeout(() => {
      animateTo({ duration: 320, curve: AnimationConfig.SPRING }, () => {
        this.chickJumpY = 0;
        this.chickRotate = 0;
      });
    }, 210);
  }

  // 喂把米：米粒落下 → 小鸡低头啄米 → 吃饱台词（纯互动，不加经验）
  feed(): void {
    if (this.feeding) {
      return;
    }
    hapticTick();
    this.feeding = true;
    this.feedY = -70;
    animateTo({ duration: 450, curve: Curve.EaseIn }, () => { this.feedY = 30; });
    setTimeout(() => {
      hapticTick();
      animateTo({ duration: 160, curve: Curve.EaseInOut }, () => {
        this.chickRotate = 16;
        this.chickJumpY = 4;
      });
    }, 430);
    setTimeout(() => {
      animateTo({ duration: 240, curve: AnimationConfig.SPRING }, () => {
        this.chickRotate = 0;
        this.chickJumpY = 0;
      });
    }, 620);
    setTimeout(() => {
      this.feeding = false;
      this.showBubble('吃饱啦！记账能让本鸡更快长大~', 2000);
      // 喂米完成今日任务（幂等，已做过则无变化）
      markDailyTask(this.context, 'feed').then((fresh: boolean): void => {
        if (fresh) {
          this.refreshGameplayState();
        }
      });
    }, 900);
  }

  // ---------- 宝藏（原勋章）进度辅助 ----------
  isUnlocked(id: string): boolean {
    return this.unlockedIds.indexOf(id) !== -1;
  }

  getProgressValue(def: AchievementDef): number {
    const cur = getCriteriaValue(this.criteria, def.kind);
    return Math.min(cur, def.target);
  }

  // 金额类维度用万元缩写显示，其余直接显示数值
  getProgressText(def: AchievementDef): string {
    const cur = getCriteriaValue(this.criteria, def.kind);
    if (def.kind === 'expenseTotal' || def.kind === 'incomeTotal') {
      return `¥${this.compactNum(cur)} / ¥${this.compactNum(def.target)}`;
    }
    return `${cur} / ${def.target}`;
  }

  compactNum(v: number): string {
    if (v >= 100000000) {
      return parseFloat((v / 100000000).toFixed(2)).toString() + '亿';
    }
    if (v >= 10000) {
      return parseFloat((v / 10000).toFixed(2)).toString() + '万';
    }
    return v.toString();
  }

  // 宽屏断点（全局）：平板/折叠屏下内容限宽居中
  @StorageProp('isWideScreen') isWideScreen: boolean = false;

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

        Text('Beta')
          .fontSize(9)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_white'))
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(6)
          .backgroundColor(this.brandMain)
          .scale({ x: this.betaPulse, y: this.betaPulse })
          .margin({ right: 6 })

        Text('小鸡养成')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        Text(`宝藏 ${this.unlockedIds.length} / ${ACHIEVEMENT_DEFS.length}`)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: this.statusBarVp + 20, bottom: 16 })

      Divider()
        .color($r('app.color.border_color'))
        .height(1)

      Scroll() {
        Column() {
          // ===== 小鸡舞台 =====
          Column() {
            // 小鸡 + 光晕 + 气泡 + 皇冠 + 米粒 + 鸡窝场景背景
            Stack({ alignContent: Alignment.Center }) {
              // 鸡窝场景背景：设计图铺满舞台，小鸡站在图上
              Image(this.currentScene().image)
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Cover)
                .transition(TransitionEffect.OPACITY
                  .combine(TransitionEffect.scale({ x: 0.96, y: 0.96 }))
                  .animation({ curve: AnimationConfig.SPRING }))

              // 进化金光 / 满级光环
              Column()
                .width(160)
                .height(160)
                .borderRadius(80)
                .backgroundColor('rgba(245, 166, 35, 0.16)')
                .visibility((this.evolveGlow || this.isMaxed()) ? Visibility.Visible : Visibility.Hidden)

              // 庆祝彩带
              if (this.celebrating) {
                HandIcon({ name: 'party', iconSize: 26 })
                  .offset({ x: -86, y: -64 })
                HandIcon({ name: 'sparkle', iconSize: 22 })
                  .offset({ x: 82, y: -56 })
                HandIcon({ name: 'confetti', iconSize: 24 })
                  .offset({ x: -78, y: 58 })
                HandIcon({ name: 'sparkle', iconSize: 20 })
                  .offset({ x: 88, y: 62 })
              }

              // 小鸡主体 + 台词气泡 + 鸟窝
              Column() {
                // 台词气泡
                if (this.bubbleVisible) {
                  Text(this.bubbleText)
                    .fontSize(13)
                    .fontColor($r('app.color.text_primary'))
                    .backgroundColor($r('app.color.card_bg'))
                    .border({ width: 1, color: $r('app.color.border_color') })
                    .borderRadius(14)
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    .margin({ bottom: 6 })
                    .transition(TransitionEffect.OPACITY
                      .combine(TransitionEffect.scale({ x: 0.8, y: 0.8 }))
                      .animation({ curve: AnimationConfig.SPRING_SOFT }))
                }

                // 小鸡（站在鸡窝场景里）
                Image(this.currentStage().image)
                  .width(96)
                  .height(96)
                  .borderRadius(48)
                  .clip(true)
                  .scale({
                    x: this.chickBreathe * this.chickScaleBoost,
                    y: this.chickBreathe * this.chickScaleBoost
                  })
                  .rotate({ angle: this.chickRotate })
                  .translate({ y: this.chickJumpY })
                  .onClick(() => { this.onChickTap(); })
                  .margin({ bottom: 2 })

                // 鸟窝
                Column() {
                  Column()
                    .width(84)
                    .height(18)
                    .borderRadius(9)
                    .backgroundColor('#C89B5A')
                  Column()
                    .width(66)
                    .height(10)
                    .borderRadius(5)
                    .backgroundColor('#B3823F')
                    .margin({ top: -8 })
                }
                .margin({ top: -6 })
              }
              .alignItems(HorizontalAlign.Center)
              .translate({ x: 55 })

              // 喂食的米粒
              if (this.feeding) {
                HandIcon({ name: 'rice', iconSize: 22 })
                  .translate({ y: this.feedY, x: 60 })
              }
            }
            .width('100%')
            .height(200)
            .borderRadius(16)
            .clip(true)

            // 形态名 + 等级
            Row() {
              Text(this.currentStage().name)
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
              Text('Lv.' + getLevelInfo(this.userXp).level)
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_white'))
                .backgroundColor(this.isMaxed() ? $r('app.color.income_gold') : this.brandMain)
                .borderRadius(10)
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .margin({ left: 8 })
              Blank()
              Text(getLevelInfo(this.userXp).name)
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
            }
            .width('100%')
            .margin({ top: 4 })

            Text(this.currentStage().desc)
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 4 })

            // 成长值进度（到下一级）
            Progress({
              value: this.xpProgressValue,
              total: 100,
              type: ProgressType.Linear
            })
              .width('100%')
              .height(8)
              .borderRadius(4)
              .color(this.isMaxed() ? $r('app.color.income_gold') : this.brandMain)
              .margin({ top: 12 })

            if (this.isMaxed()) {
              Text(`${this.userXp} 成长值 · 已是满级传说`)
                .fontSize(12)
                .fontColor($r('app.color.income_gold'))
                .margin({ top: 6 })
            } else {
              Text(`${this.userXp} 成长值 · 距下一级还需 ${getLevelInfo(this.userXp).nextLevelXp - this.userXp}`)
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .margin({ top: 6 })
            }

            // 成长路线：左右滑动查看 5 个形态（当前形态高亮，未解锁置灰）
            Swiper() {
              ForEach(CHICK_STAGES, (s: ChickStage) => {
                Row() {
                  Image(s.image)
                    .width(s.stage === this.currentStage().stage ? 64 : 52)
                    .height(s.stage === this.currentStage().stage ? 64 : 52)
                    .borderRadius(s.stage === this.currentStage().stage ? 32 : 26)
                    .clip(true)
                    .opacity(s.stage <= this.currentStage().stage ? 1 : 0.3)
                    .animation({ duration: 320, curve: AnimationConfig.SPRING_SOFT })

                  Column() {
                    Text(s.name)
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(s.stage === this.currentStage().stage ?
                      $r('app.color.text_primary') : $r('app.color.text_secondary'))
                    Text(s.desc)
                      .fontSize(11)
                      .fontColor($r('app.color.text_secondary'))
                      .margin({ top: 2 })
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    if (s.stage === this.currentStage().stage) {
                      Text('当前形态')
                        .fontSize(11)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(this.brandMain)
                        .margin({ top: 4 })
                    } else if (s.stage < this.currentStage().stage) {
                      Text('已成长')
                        .fontSize(11)
                        .fontColor($r('app.color.success_green'))
                        .margin({ top: 4 })
                    } else {
                      Text(`Lv.${s.minLevel} 解锁`)
                        .fontSize(11)
                        .fontColor($r('app.color.text_secondary'))
                        .margin({ top: 4 })
                    }
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  .margin({ left: 14 })
                }
                .width('100%')
                .padding({ left: 14, right: 14, top: 12, bottom: 12 })
                .alignItems(VerticalAlign.Center)
              }, (s: ChickStage) => s.stage.toString() + '_' + this.currentStage().stage.toString())
            }
            .width('100%')
            .height(96)
            .index(this.stageViewIndex)
            .loop(false)
            .duration(300)
            .indicator(new DotIndicator()
              .selectedColor(this.brandMain)
              .color($r('app.color.border_color')))
            .margin({ top: 14, bottom: 2 })

            // 操作行：喂把米
            Row() {
              Row() {
                HandIcon({ name: 'rice', iconSize: 15 })
                Text('喂把米')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.brandMain)
                  .margin({ left: 4 })
              }
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .backgroundColor(this.brandTint)
              .borderRadius(18)
              .scale({ x: this.pressedChipKey === 'feed' ? 0.92 : 1, y: this.pressedChipKey === 'feed' ? 0.92 : 1 })
              .animation({ curve: MotionCurves.PRESS })
              .onTouch((event: TouchEvent) => {
                if (event.type === TouchType.Down) {
                  this.pressedChipKey = 'feed';
                } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                  this.pressedChipKey = '';
                }
              })
              .onClick(() => { this.feed(); })

              Text('每记一笔账 +5 成长值，小鸡会慢慢长大')
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
                .margin({ left: 10 })
            }
            .width('100%')
            .margin({ top: 14 })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 20, bottom: 18 })
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius({ topLeft: 22, topRight: 19, bottomLeft: 21, bottomRight: 23 })
          .shadow({ radius: 0, color: $r('app.color.ink_shadow'), offsetX: 3, offsetY: 3 }).border({ width: 1, color: $r('app.color.ink_line') })
          .overlay(this.TapeDeco(), { align: Alignment.TopStart, offset: { x: 22, y: -7 } })
          .margin({ top: 16, bottom: 8 })

          // ===== 每日鸡运签 =====
          if (this.taskCardReady) {
            Column() {
              Row() {
                Text('每日鸡运签')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                Blank()
                Text('每天一签 · 记账触发好运')
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
              }
              .width('100%')
              .margin({ bottom: 10 })

              if (this.fortune === null) {
                Row() {
                  HandIcon({ name: 'bamboo', iconSize: 32 })
                  Column() {
                    Text('今天还没抽签')
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_primary'))
                    Text('抽一签看看今天的记账运势')
                      .fontSize(11)
                      .fontColor($r('app.color.text_secondary'))
                      .margin({ top: 2 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  .margin({ left: 12 })

                  Text('抽一签')
                    .fontSize(13)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_white'))
                    .backgroundColor(this.brandMain)
                    .borderRadius(16)
                    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                    .onClick(() => { this.onDrawFortune(); })
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)
              } else {
                Row() {
                  HandIcon({ name: FORTUNE_LEVEL_EMOJI[this.fortune.level], iconSize: 34 })
                  Column() {
                    Row() {
                      Text(`今日运势 · ${FORTUNE_LEVEL_NAMES[this.fortune.level]}`)
                        .fontSize(15)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(this.fortune.level >= 2 ?
                        $r('app.color.income_gold') : $r('app.color.text_primary'))
                      if (this.fortune.claimed) {
                        Text('已领奖')
                          .fontSize(10)
                          .fontWeight(FontWeight.Medium)
                          .fontColor($r('app.color.success_green'))
                          .backgroundColor($r('app.color.category_btn_bg'))
                          .borderRadius(8)
                          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                          .margin({ left: 8 })
                      }
                    }
                    Text(this.fortune.text)
                      .fontSize(11)
                      .fontColor($r('app.color.text_secondary'))
                      .margin({ top: 2 })
                    Row() {
                      Progress({
                        value: Math.min(this.fortune.billsDone, FORTUNE_TASK_BILLS[this.fortune.level]),
                        total: FORTUNE_TASK_BILLS[this.fortune.level],
                        type: ProgressType.Linear
                      })
                      .layoutWeight(1)
                      .height(6)
                      .borderRadius(3)
                      .color(this.brandMain)

                      Text(`记账 ${this.fortune.billsDone}/${FORTUNE_TASK_BILLS[this.fortune.level]}`)
                        .fontSize(11)
                        .fontColor($r('app.color.text_secondary'))
                        .margin({ left: 8 })
                    }
                    .width('100%')
                    .margin({ top: 8 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  .margin({ left: 12 })

                  if (!this.fortune.claimed &&
                    this.fortune.billsDone >= FORTUNE_TASK_BILLS[this.fortune.level]) {
                    Text(`领 +${FORTUNE_REWARDS[this.fortune.level]}`)
                      .fontSize(13)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_white'))
                      .backgroundColor($r('app.color.income_gold'))
                      .borderRadius(16)
                      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                      .onClick(() => { this.onClaimFortune(); })
                  }
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)
              }
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 16, bottom: 14 })
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius({ topLeft: 22, topRight: 19, bottomLeft: 21, bottomRight: 23 })
            .shadow({ radius: 0, color: $r('app.color.ink_shadow'), offsetX: 3, offsetY: 3 }).border({ width: 1, color: $r('app.color.ink_line') })
            .overlay(this.TapeDeco(), { align: Alignment.TopStart, offset: { x: 22, y: -7 } })
            .margin({ bottom: 8 })
            .transition(TransitionEffect.OPACITY
              .combine(TransitionEffect.translate({ y: 22 }))
              .animation({ delay: 60, curve: AnimationConfig.SPRING_SOFT }))
          }

          // ===== 每日任务 =====
          Column() {
            Row() {
              Text('每日任务')
                .fontSize(17)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Row() {
                HandIcon({ name: 'flame', iconSize: 13 })
                Text(`连记 ${this.criteria.streakDays} 天 · 记账经验 ${getMultiplierText(getStreakMultiplier(this.criteria.streakDays))}`)
                  .fontSize(11)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(getStreakMultiplier(this.criteria.streakDays) > 1 ?
                  $r('app.color.budget_orange') : $r('app.color.text_secondary'))
                  .margin({ left: 4 })
                  .maxLines(1)
              }
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .backgroundColor($r('app.color.category_btn_bg'))
              .borderRadius(10)
              .margin({ left: 8 })
              .alignItems(VerticalAlign.Center)
              Blank()
              Row() {
                HandIcon({ name: 'egg', iconSize: 14 })
                Text(`${this.eggCoins}`)
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.income_gold'))
                  .margin({ left: 3 })
              }
              .alignItems(VerticalAlign.Center)
            }
            .width('100%')

            if (this.taskCardReady) {
              ForEach(DAILY_TASK_DEFS, (task: DailyTaskDef, index: number) => {
                Row() {
                  Column() {
                    HandIcon({ name: task.emoji, iconSize: 20 })
                  }
                  .width(38)
                  .height(38)
                  .justifyContent(FlexAlign.Center)
                  .alignItems(HorizontalAlign.Center)
                  .backgroundColor($r('app.color.category_btn_bg'))
                  .borderRadius(19)
                  .opacity(this.isTaskClaimed(task.id) ? 0.4 : 1)

                  Column() {
                    Text(task.name)
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.isTaskClaimed(task.id) ?
                        $r('app.color.text_secondary') : $r('app.color.text_primary'))
                    Text(`奖励 ${task.reward} 鸡蛋币`)
                      .fontSize(11)
                      .fontColor($r('app.color.text_secondary'))
                      .opacity(this.isTaskClaimed(task.id) ? 0.6 : 1)
                      .margin({ top: 2 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  .margin({ left: 10 })

                  if (this.isTaskClaimed(task.id)) {
                    Text('已领取')
                      .fontSize(13)
                      .fontColor($r('app.color.text_secondary'))
                  } else if (this.isTaskDone(task.id)) {
                    Text('领取')
                      .fontSize(13)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.text_white'))
                      .backgroundColor($r('app.color.income_gold'))
                      .borderRadius(15)
                      .padding({ left: 16, right: 16, top: 6, bottom: 6 })
                      .onClick(() => { this.claimTask(task.id); })
                  } else {
                    Text('待完成')
                      .fontSize(13)
                      .fontColor($r('app.color.text_secondary'))
                      .opacity(0.7)
                  }
                }
                .width('100%')
                .padding({ top: 10, bottom: 10 })
                .transition(TransitionEffect.OPACITY
                  .combine(TransitionEffect.translate({ y: 18 }))
                  .animation({ delay: index * 45, curve: AnimationConfig.SPRING_SOFT }))
              }, (task: DailyTaskDef) =>
              task.id + (this.isTaskClaimed(task.id) ? '_2' : this.isTaskDone(task.id) ? '_1' : '_0'))
            }

            Text('任务每天 0 点刷新 · 连续记账能放大成长值收益')
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 4 })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 16, bottom: 14 })
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius({ topLeft: 22, topRight: 19, bottomLeft: 21, bottomRight: 23 })
          .shadow({ radius: 0, color: $r('app.color.ink_shadow'), offsetX: 3, offsetY: 3 }).border({ width: 1, color: $r('app.color.ink_line') })
          .overlay(this.TapeDeco(), { align: Alignment.TopStart, offset: { x: 22, y: -7 } })
          .margin({ bottom: 8 })

          // ===== 幸运存钱罐 =====
          if (this.taskCardReady) {
            Column() {
              Row() {
                Text('幸运存钱罐')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                Blank()
                Text('每笔记账随机掉 1~3 金币')
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
              }
              .width('100%')
              .margin({ bottom: 10 })

              Row() {
                HandIcon({ name: 'jar', iconSize: 34 })
                  .scale({ x: this.piggyPop, y: this.piggyPop })
                Column() {
                  Progress({
                    value: this.piggy.coins,
                    total: this.piggy.capacity,
                    type: ProgressType.Linear
                  })
                  .width('100%')
                  .height(8)
                  .borderRadius(4)
                  .color($r('app.color.income_gold'))

                  Text(this.piggy.coins >= this.piggy.capacity ?
                  `罐子满啦（${this.piggy.capacity} 金币），快开罐！` :
                  `罐里已有 ${this.piggy.coins} / ${this.piggy.capacity} 金币`)
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ top: 6 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                .margin({ left: 12 })

                if (this.piggy.coins >= this.piggy.capacity) {
                  Text('开罐！')
                    .fontSize(13)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_white'))
                    .backgroundColor($r('app.color.income_gold'))
                    .borderRadius(16)
                    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                    .onClick(() => { this.onOpenPiggy(); })
                }
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 16, bottom: 14 })
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius({ topLeft: 22, topRight: 19, bottomLeft: 21, bottomRight: 23 })
            .shadow({ radius: 0, color: $r('app.color.ink_shadow'), offsetX: 3, offsetY: 3 }).border({ width: 1, color: $r('app.color.ink_line') })
            .overlay(this.TapeDeco(), { align: Alignment.TopStart, offset: { x: 22, y: -7 } })
            .margin({ bottom: 8 })
            .transition(TransitionEffect.OPACITY
              .combine(TransitionEffect.translate({ y: 22 }))
              .animation({ delay: 100, curve: AnimationConfig.SPRING_SOFT }))
          }

          // ===== 小鸡旅行 =====
          if (this.taskCardReady) {
            Column() {
              Row() {
                Text('小鸡旅行')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                Blank()
                Text('旅途中的每笔账都让它提前回家')
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
              }
              .width('100%')
              .margin({ bottom: 8 })

              if (this.travel !== null) {
                Row() {
                  HandIcon({ name: getTravelDestination(this.travel.destId).emoji, iconSize: 34 })
                  Column() {
                    Text(getTravelDestination(this.travel.destId).name)
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_primary'))
                    if (!isTravelDone(this.travel)) {
                      Text(`还剩约 ${this.travelRemainHours()} 小时 · 已加速 ${this.travel.billsBoosted} 次`)
                        .fontSize(11)
                        .fontColor($r('app.color.text_secondary'))
                        .margin({ top: 2 })
                      Progress({
                        value: this.travelProgress(),
                        total: 100,
                        type: ProgressType.Linear
                      })
                      .width('100%')
                      .height(6)
                      .borderRadius(3)
                      .color(this.brandMain)
                      .margin({ top: 8 })
                    } else {
                      Text('小鸡到家啦，点击迎接它！')
                        .fontSize(11)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.success_green'))
                        .margin({ top: 2 })
                    }
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  .margin({ left: 12 })

                  if (isTravelDone(this.travel)) {
                    Text('迎接')
                      .fontSize(13)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_white'))
                      .backgroundColor($r('app.color.success_green'))
                      .borderRadius(16)
                      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                      .onClick(() => { this.onClaimTravel(); })
                  }
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)
              } else {
                ForEach(TRAVEL_DESTINATIONS, (dest: TravelDestination) => {
                  Row() {
                    HandIcon({ name: dest.emoji, iconSize: 26 })
                    Column() {
                      Text(dest.name)
                        .fontSize(14)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.text_primary'))
                      Text(`${dest.desc} · 奖励约 ${dest.minReward}~${dest.maxReward} 币`)
                        .fontSize(11)
                        .fontColor($r('app.color.text_secondary'))
                        .margin({ top: 2 })
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)
                    .margin({ left: 10 })

                    Row() {
                      HandIcon({ name: 'egg', iconSize: 13 })
                      Text(`${dest.cost} 出发`)
                        .fontSize(12)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(this.eggCoins >= dest.cost ?
                        this.brandMain : $r('app.color.text_secondary'))
                        .margin({ left: 3 })
                    }
                    .alignItems(VerticalAlign.Center)
                    .padding({ left: 10, right: 10, top: 7, bottom: 7 })
                    .borderRadius(14)
                    .backgroundColor(this.eggCoins >= dest.cost ?
                    this.brandTint : $r('app.color.category_btn_bg'))
                    .onClick(() => { this.onStartTravel(dest); })
                  }
                  .width('100%')
                  .padding({ top: 8, bottom: 8 })
                  .alignItems(VerticalAlign.Center)
                }, (dest: TravelDestination) =>
                dest.id + (this.eggCoins >= dest.cost ? '_ok' : '_no'))
              }
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 16, bottom: 12 })
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius({ topLeft: 22, topRight: 19, bottomLeft: 21, bottomRight: 23 })
            .shadow({ radius: 0, color: $r('app.color.ink_shadow'), offsetX: 3, offsetY: 3 }).border({ width: 1, color: $r('app.color.ink_line') })
            .overlay(this.TapeDeco(), { align: Alignment.TopStart, offset: { x: 22, y: -7 } })
            .margin({ bottom: 8 })
            .transition(TransitionEffect.OPACITY
              .combine(TransitionEffect.translate({ y: 22 }))
              .animation({ delay: 140, curve: AnimationConfig.SPRING_SOFT }))
          }

          // ===== 玩法乐园入口 =====
          Column() {
            Row() {
              Text('Beta')
                .fontSize(9)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_white'))
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .borderRadius(6)
                .backgroundColor(this.brandMain)
                .margin({ right: 6 })
              Text('玩法乐园')
                .fontSize(17)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Blank()
              Text('5 种新玩法等你解锁')
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
            }
            .width('100%')
            .margin({ bottom: 10 })

            Row() {
              HandIcon({ name: 'tree', iconSize: 30 })
              Column() {
                Text('摇钱树 · 盲盒机 · 守护战')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                Text('签到日历 · 无消费日挑战')
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              .margin({ left: 12 })

              Text('进入')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_white'))
                .backgroundColor(this.brandMain)
                .borderRadius(16)
                .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                .onClick(() => {
                  hapticTick();
                  router.pushUrl({ url: 'pages/PlaygroundPage' });
                })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 16, bottom: 14 })
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius({ topLeft: 22, topRight: 19, bottomLeft: 21, bottomRight: 23 })
          .shadow({ radius: 0, color: $r('app.color.ink_shadow'), offsetX: 3, offsetY: 3 }).border({ width: 1, color: $r('app.color.ink_line') })
          .overlay(this.TapeDeco(), { align: Alignment.TopStart, offset: { x: 22, y: -7 } })
          .margin({ bottom: 8 })
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.translate({ y: 22 }))
            .animation({ delay: 150, curve: AnimationConfig.SPRING_SOFT }))

          // ===== 鸡窝装修 =====
          Column() {
            Row() {
              Text('鸡窝装修')
                .fontSize(17)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Blank()
              Row() {
                Text('我的鸡蛋币')
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.income_gold'))
                HandIcon({ name: 'egg', iconSize: 13 })
                  .margin({ left: 4, right: 3 })
                Text(`${this.eggCoins}`)
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.income_gold'))
              }
              .alignItems(VerticalAlign.Center)
            }
            .width('100%')
            .margin({ bottom: 10 })

            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
              ForEach(SCENE_DEFS, (def: SceneDef) => {
                Column() {
                  // 场景缩略预览：设计图裁切展示
                  Image(def.image)
                    .width(64)
                    .height(46)
                    .objectFit(ImageFit.Cover)
                    .borderRadius(10)
                    .clip(true)

                  Text(def.name)
                    .fontSize(13)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                    .margin({ top: 6 })
                    .maxLines(1)

                  if (this.sceneUsing === def.id) {
                    Text('使用中')
                      .fontSize(11)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.brandMain)
                      .margin({ top: 2 })
                  } else if (this.sceneOwned.indexOf(def.id) !== -1) {
                    Text('点击使用')
                      .fontSize(11)
                      .fontColor($r('app.color.success_green'))
                      .margin({ top: 2 })
                  } else {
                    Row() {
                      HandIcon({ name: 'egg', iconSize: 12 })
                      Text(`${def.price}`)
                        .fontSize(11)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(this.eggCoins >= def.price ?
                        $r('app.color.income_gold') : $r('app.color.text_secondary'))
                        .margin({ left: 2 })
                    }
                    .margin({ top: 2 })
                    .alignItems(VerticalAlign.Center)
                  }
                }
                .width('31%')
                .padding({ top: 12, bottom: 10 })
                .alignItems(HorizontalAlign.Center)
                .borderRadius(16)
                .backgroundColor($r('app.color.card_bg'))
                .border({
                  width: this.sceneUsing === def.id ? 1.5 : 1,
                  color: this.sceneUsing === def.id ? this.brandMain : $r('app.color.border_color')
                })
                .margin({ bottom: 10 })
                .onClick(() => { this.onSceneTap(def); })
              }, (def: SceneDef) =>
              def.id + (this.sceneUsing === def.id ? '_w' : '') + (this.sceneOwned.indexOf(def.id) !== -1 ? '_o' : ''))
            }
            .width('100%')

            Text('做任务赚鸡蛋币，给小鸡安个漂亮的家')
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 16, bottom: 12 })
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius({ topLeft: 22, topRight: 19, bottomLeft: 21, bottomRight: 23 })
          .shadow({ radius: 0, color: $r('app.color.ink_shadow'), offsetX: 3, offsetY: 3 }).border({ width: 1, color: $r('app.color.ink_line') })
          .overlay(this.TapeDeco(), { align: Alignment.TopStart, offset: { x: 22, y: -7 } })
          .margin({ bottom: 8 })

          // ===== 本月小鸡报告 =====
          if (this.taskCardReady && this.report !== null) {
            Column() {
              Row() {
              Row() {
                HandIcon({ name: 'chart', iconSize: 17 })
                Text(`${this.report.monthLabel}小鸡报告`)
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                  .margin({ left: 5 })
              }
              .alignItems(VerticalAlign.Center)
                Blank()
                Text(`记账 ${this.report.billCount} 笔`)
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
              }
              .width('100%')

              Row() {
                Column() {
                  Text('收入')
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                  Text(`¥${this.report.incomeTotal.toFixed(0)}`)
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.income_gold'))
                    .margin({ top: 2 })
                }
                .layoutWeight(1)

                Column() {
                  Text('支出')
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                  Text(`¥${this.report.expenseTotal.toFixed(0)}`)
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.expense_red'))
                    .margin({ top: 2 })
                }
                .layoutWeight(1)

                Column() {
                  Text('结余')
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                  Text(`¥${this.report.savedAmount.toFixed(0)}`)
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.report.savedAmount >= 0 ?
                    $r('app.color.success_green') : $r('app.color.expense_red'))
                    .margin({ top: 2 })
                }
                .layoutWeight(1)
              }
              .width('100%')
              .margin({ top: 14 })

              Divider()
                .color($r('app.color.border_color'))
                .height(1)
                .margin({ top: 12, bottom: 10 })

              ForEach(this.report.comments, (c: string) => {
                Row() {
                  HandIcon({ name: 'chick', iconSize: 13 })
                    .margin({ right: 6 })
                  Text(c)
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                    .layoutWeight(1)
                }
                .width('100%')
                .alignItems(VerticalAlign.Top)
                .margin({ top: 3, bottom: 3 })
              }, (c: string) => c)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 16, bottom: 14 })
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius({ topLeft: 22, topRight: 19, bottomLeft: 21, bottomRight: 23 })
            .shadow({ radius: 0, color: $r('app.color.ink_shadow'), offsetX: 3, offsetY: 3 }).border({ width: 1, color: $r('app.color.ink_line') })
            .overlay(this.TapeDeco(), { align: Alignment.TopStart, offset: { x: 22, y: -7 } })
            .margin({ bottom: 8 })
            .transition(TransitionEffect.OPACITY
              .combine(TransitionEffect.translate({ y: 22 }))
              .animation({ delay: 180, curve: AnimationConfig.SPRING_SOFT }))
          }

          // ===== 小鸡的宝藏（原勋章墙） =====
          Row() {
            Text('小鸡的宝藏')
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Blank()
            Text('解锁成就 = 小鸡捡到新宝贝')
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .margin({ top: 8, bottom: 12 })

          // 宝藏网格（2 列）：就绪后按序号交错上滑入场
          if (this.gridReady) {
            Flex({
              wrap: FlexWrap.Wrap,
              justifyContent: FlexAlign.SpaceBetween
            }) {
              ForEach(ACHIEVEMENT_DEFS, (def: AchievementDef, index: number) => {
                Column() {
                  // 圆形宝藏图标
                  Column() {
                    SymbolGlyph(def.icon)
                      .fontSize(30)
                      .fontWeight(FontWeight.Bold)
                      .fontColor([this.isUnlocked(def.id) ?
                      Color.White : $r('app.color.text_secondary')])
                  }
                  .width(56)
                  .height(56)
                  .borderRadius(28)
                  .backgroundColor(this.isUnlocked(def.id) ?
                  def.color : $r('app.color.category_btn_bg'))
                  .justifyContent(FlexAlign.Center)
                  .margin({ top: 2 })

                  Text(def.name)
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.isUnlocked(def.id) ?
                    $r('app.color.text_primary') : $r('app.color.text_secondary'))
                    .margin({ top: 8 })

                  Text(def.desc)
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ top: 2 })
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })

                  if (this.isUnlocked(def.id)) {
                    Text(`已收藏 · +${def.reward} 成长值`)
                      .fontSize(11)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.success_green'))
                      .margin({ top: 8 })
                  } else {
                    Progress({
                      value: this.getProgressValue(def),
                      total: def.target,
                      type: ProgressType.Linear
                    })
                    .width('100%')
                    .height(6)
                    .borderRadius(3)
                    .color(this.brandMain)
                    .margin({ top: 10 })

                    Text(this.getProgressText(def))
                      .fontSize(11)
                      .fontColor($r('app.color.text_secondary'))
                      .margin({ top: 4 })
                  }
                }
                .width('48.5%')
                .padding({ top: 14, bottom: 14, left: 10, right: 10 })
                .alignItems(HorizontalAlign.Center)
                .backgroundColor($r('app.color.card_bg'))
                .borderRadius({ topLeft: 18, topRight: 15, bottomLeft: 17, bottomRight: 19 })
                .shadow({ radius: 0, color: $r('app.color.ink_shadow'), offsetX: 3, offsetY: 3 }).border({ width: 1, color: $r('app.color.ink_line') })
                .margin({ bottom: 12 })
                .transition(TransitionEffect.OPACITY
                  .combine(TransitionEffect.translate({ y: 26 }))
                  .animation({ delay: index * 45, curve: AnimationConfig.SPRING_SOFT }))
              }, (def: AchievementDef) =>
              def.id + (this.isUnlocked(def.id) ? '_1' : '_0') + '_' + this.getProgressValue(def).toString())
            }
            .width('100%')
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
