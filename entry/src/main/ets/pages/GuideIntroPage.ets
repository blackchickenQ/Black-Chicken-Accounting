import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { hapticTick } from '../common/Haptics';
import { AnimationConfig } from './Index';
import { MotionCurves } from '../common/Motion';
import {
  isGuideIntroDone,
  setGuideIntroDone,
  isGuideDone,
  finishGuide
} from '../common/Gameplay';

// 引导介绍页单页内容定义
interface IntroPageDef {
  image: Resource;     // 插图（应用图标 / 小鸡成长阶段图）
  title: string;
  subtitle: string;
  lines: string[];     // 详细说明行
}

// 5 页详细引导：欢迎 → 记账成长 → 任务场景 → 攒钱玩法 → 数据隐私
const INTRO_PAGES: IntroPageDef[] = [
  {
    image: $r('app.media.foreground'),
    title: '欢迎使用乌鸡记账',
    subtitle: '一个会陪你成长的记账本',
    lines: [
      '记账只需几秒：金额、分类、账户一键完成',
      '多账本管理，支持微信 / 支付宝账单导入',
      '底部五个标签页：记账 · 统计 · 账单 · 财富 · 我的'
    ]
  },
  {
    image: $r('app.media.chick_stage1'),
    title: '记一笔账，喂大你的小鸡',
    subtitle: '每一笔记录都会化作成长值',
    lines: [
      '每记一笔账 +5 成长值，连续记账最高享 2 倍加成',
      '小鸡会随成长值进化：蛋 → 破壳 → 雏鸡 → 乌鸡 → 金乌鸡',
      '成长值可在「我的 → 小鸡养成」中查看'
    ]
  },
  {
    image: $r('app.media.chick_stage3'),
    title: '做任务，赚鸡蛋币',
    subtitle: '给小鸡安个漂亮的家吧',
    lines: [
      '每日任务：记账、存钱、喂鸡都能赚鸡蛋币',
      '鸡窝装修：樱花庭院、星空月夜、黄金宫殿等你解锁',
      '任务每天 0 点刷新，记得每天来看看小鸡'
    ]
  },
  {
    image: $r('app.media.chick_stage5'),
    title: '攒钱也可以很上瘾',
    subtitle: '「财富」页里有你的攒钱工具箱',
    lines: [
      '存钱目标：为想买的大件制定计划，一键存入',
      '52 周 / 30 天阶梯挑战，可选将存入计入收支账单',
      '愿望清单：想买的先冷静 30 天，防止冲动消费'
    ]
  },
  {
    image: $r('app.media.foreground'),
    title: '数据只属于你',
    subtitle: '隐私与安心同样重要',
    lines: [
      '所有账单仅保存在手机本地，不上传服务器',
      '可开启隐私锁与指纹解锁保护账本',
      '支持账单导出与回收站找回，数据不丢失'
    ]
  }
];

// 引导介绍页：首启展示，也可从「设置 → 新手引导」重新体验
// 页面切换不用 Swiper，改用键控内容 + 过渡动画：点击/滑动均可靠，动画更 Q 弹
@Entry
@Component
struct GuideIntroPage {
  @StorageProp('brand_main') brandMain: string = '#4E6EF2';
  @State curPage: number = 0;
  @State imageBreath: number = 1;
  @State nextBtnScale: number = 1;
  @State skipBtnScale: number = 1;
  @State pressedChipKey: string = '';  // 按压中的胶囊按钮 key（Q弹缩放反馈）

  aboutToAppear(): void {
    // 插图呼吸：轻微缩放往复，让页面有生命感
    animateTo({
      duration: 1400,
      curve: Curve.EaseInOut,
      iterations: -1,
      playMode: PlayMode.Alternate
    }, () => {
      this.imageBreath = 1.07;
    });
  }

  // 切页：震感 + 弹簧驱动（圆点宽度等属性随之弹动）
  goToPage(target: number): void {
    if (target < 0 || target >= INTRO_PAGES.length || target === this.curPage) {
      return;
    }
    hapticTick();
    animateTo({ curve: AnimationConfig.SPRING }, () => {
      this.curPage = target;
    });
  }

  // 结束引导：标记已看过；首次结束发放新手礼包（幂等）
  // 首次启动 → 进入主页；从设置页重新体验 → 返回设置页
  async finishIntro(): Promise<void> {
    hapticTick();
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (!context) {
      router.replaceUrl({ url: 'pages/Index' });
      return;
    }
    const alreadyDone = await isGuideIntroDone(context);
    await setGuideIntroDone(context);
    if (!await isGuideDone(context)) {
      await finishGuide(context);
      promptAction.showToast({
        message: '新手礼包：鸡蛋币 +50、樱花庭院场景已解锁！',
        duration: 3000
      });
    }
    if (alreadyDone) {
      router.back();
    } else {
      router.replaceUrl({ url: 'pages/Index' });
    }
  }

  // 全屏沉浸式布局：状态栏/手势条避让高度由 EntryAbility 发布到 AppStorage，页面据此留白避让
  @StorageProp('statusBarVp') statusBarVp: number = 46;
  @StorageProp('navBarVp') navBarVp: number = 28;

  build() {
    Column() {
      // 顶部品牌行：应用图标 + 名称
      Row() {
        Image($r('app.media.foreground'))
          .width(34)
          .height(34)
          .borderRadius(9)
          .clip(true)
        Text('乌鸡记账')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 8 })
      }
      .alignItems(VerticalAlign.Center)
      .margin({ top: this.statusBarVp + 18, bottom: 6 })

      // 内容区：键控切换（curPage 变化 → 旧页退场、新页弹性入场），支持左右滑动
      Stack() {
        ForEach([this.curPage], (p: number) => {
          Column() {
            // 插图：入场从小弹到大（低阻尼弹簧），平时轻微呼吸
            Column() {
              Image(INTRO_PAGES[p].image)
                .width(128)
                .height(128)
                .borderRadius(28)
                .clip(true)
                .scale({ x: this.imageBreath, y: this.imageBreath })
            }
            .transition(TransitionEffect.OPACITY
              .combine(TransitionEffect.scale({ x: 0.35, y: 0.35 }))
              .animation({ duration: 500, curve: AnimationConfig.SPRING }))

            Text(INTRO_PAGES[p].title)
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .margin({ top: 22 })
              .transition(TransitionEffect.OPACITY
                .combine(TransitionEffect.translate({ y: 18 }))
                .animation({ delay: 90, duration: 420, curve: AnimationConfig.SPRING }))

            Text(INTRO_PAGES[p].subtitle)
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 8 })
              .transition(TransitionEffect.OPACITY
                .combine(TransitionEffect.translate({ y: 14 }))
                .animation({ delay: 150, duration: 420, curve: AnimationConfig.SPRING }))

            // 详细说明行：逐条交错弹入
            Column() {
              ForEach(INTRO_PAGES[p].lines, (line: string, idx: number) => {
                Row() {
                  Column()
                    .width(6)
                    .height(6)
                    .borderRadius(3)
                    .backgroundColor(this.brandMain)
                    .margin({ right: 10 })
                  Text(line)
                    .fontSize(14)
                    .fontColor($r('app.color.text_primary'))
                    .lineHeight(21)
                    .layoutWeight(1)
                }
                .alignItems(VerticalAlign.Center)
                .width('100%')
                .margin({ top: 12 })
                .transition(TransitionEffect.OPACITY
                  .combine(TransitionEffect.translate({ y: 16 }))
                  .animation({ delay: 210 + idx * 80, duration: 420, curve: AnimationConfig.SPRING }))
              }, (line: string, idx: number) => `${p}_${idx}`)
            }
            .width('100%')
            .constraintSize({ maxWidth: 300 })
            .alignItems(HorizontalAlign.Start)
            .margin({ top: 14 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .transition(TransitionEffect.asymmetric(
            // 入场：整体上浮 + 轻微放大淡入（弹簧回弹）
            TransitionEffect.OPACITY
              .combine(TransitionEffect.translate({ y: 30 }))
              .combine(TransitionEffect.scale({ x: 0.88, y: 0.88 }))
              .animation({ duration: 450, curve: AnimationConfig.SPRING }),
            // 退场：快速左滑淡出，给新页让位
            TransitionEffect.OPACITY
              .combine(TransitionEffect.translate({ x: -46 }))
              .animation({ duration: 200, curve: Curve.EaseIn })
          ))
        }, (p: number) => `page_${p}`)
      }
      .width('100%')
      .layoutWeight(1)
      .gesture(PanGesture({ fingers: 1 })
        .onActionEnd((event: GestureEvent) => {
          if (event.offsetX < -50) {
            this.goToPage(this.curPage + 1);
          } else if (event.offsetX > 50) {
            this.goToPage(this.curPage - 1);
          }
        }))

      // 自定义指示点：当前页胶囊形（宽度弹簧过渡），可点击跳页
      Row() {
        ForEach(INTRO_PAGES, (page: IntroPageDef, idx: number) => {
          Column()
            .width(this.curPage === idx ? 22 : 8)
            .height(8)
            .borderRadius(4)
            .backgroundColor(this.curPage === idx ? this.brandMain : $r('app.color.border_color'))
            .margin({ left: idx === 0 ? 0 : 6 })
            .onClick(() => { this.goToPage(idx); })
        }, (page: IntroPageDef, idx: number) => `dot_${idx}_${this.curPage === idx}`)
      }
      .margin({ bottom: 22 })

      // 底部按钮：跳过（最后一页隐藏）/ 下一页 · 开始使用
      Row() {
        if (this.curPage < INTRO_PAGES.length - 1) {
          Text('跳过')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .padding({ left: 14, right: 14, top: 10, bottom: 10 })
            .scale({ x: this.skipBtnScale, y: this.skipBtnScale })
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) {
                animateTo({ curve: AnimationConfig.SPRING }, () => { this.skipBtnScale = 0.9; });
              } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                animateTo({ curve: AnimationConfig.SPRING }, () => { this.skipBtnScale = 1; });
              }
            })
            .onClick(() => { this.finishIntro(); })
        }

        Blank().layoutWeight(1)

        Text(this.curPage < INTRO_PAGES.length - 1 ? '下一页' : '开始使用')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_white'))
          .backgroundColor(this.brandMain)
          .borderRadius(24)
          .padding({ left: 34, right: 34, top: 12, bottom: 12 })
          .scale({ x: this.nextBtnScale, y: this.nextBtnScale })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              animateTo({ curve: AnimationConfig.SPRING }, () => { this.nextBtnScale = 0.92; });
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              animateTo({ curve: AnimationConfig.SPRING }, () => { this.nextBtnScale = 1; });
            }
          })
          .onClick(() => {
            if (this.curPage < INTRO_PAGES.length - 1) {
              this.goToPage(this.curPage + 1);
            } else {
              this.finishIntro();
            }
          })
      }
      .width('100%')
      .padding({ bottom: this.navBarVp + 30 })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 28, right: 28 })
    .backgroundColor($r('app.color.bg_main'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
  }

}
