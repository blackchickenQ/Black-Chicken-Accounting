// ---------- 全局动效库：Q弹弹簧曲线 / 按压回弹组件 / 入场动画工厂 ----------
import { curves } from '@kit.ArkUI';
import { hapticTick } from './Haptics';

// Q弹弹簧曲线集合（springMotion：response 越小回弹越快，dampingFraction 越小弹跳越明显）
export class MotionCurves {
  // 标准Q弹：按钮按压回弹
  static readonly PRESS: curves.ICurve = curves.springMotion(0.4, 0.55);
  // 轻柔回弹：内容切换、面板过渡
  static readonly SOFT: curves.ICurve = curves.springMotion(0.5, 0.8);
  // 高弹跳：图标弹跳、强调动效
  static readonly BOUNCY: curves.ICurve = curves.springMotion(0.3, 0.5);
  // 果冻感：大卡片按压
  static readonly JELLY: curves.ICurve = curves.springMotion(0.45, 0.62);
}

// ---------- 按压回弹包装组件 ----------
// 用法：BounceTouch({ pressScale: 0.94 }) { 你的卡片/按钮内容 }
// 触摸按下时内容缩小，松手后以弹簧曲线回弹，带轻微触感反馈
@Component
export struct BounceTouch {
  // 按下时的缩放比例：按钮建议 0.92-0.95，卡片建议 0.97
  @Prop pressScale: number = 0.94;
  // 按下时是否触发触感反馈
  @Prop hapticOnPress: boolean = false;
  @State private isPressed: boolean = false;
  @BuilderParam content: () => void;

  build() {
    Column() {
      this.content()
    }
    .scale({
      x: this.isPressed ? this.pressScale : 1,
      y: this.isPressed ? this.pressScale : 1
    })
    .animation({ curve: MotionCurves.PRESS })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.isPressed = true;
        if (this.hapticOnPress) {
          hapticTick();
        }
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.isPressed = false;
      }
    })
  }
}

// ---------- 入场动画工厂 ----------

// 卡片/区块弹入入场：上浮 + 渐显 + 轻微放大，带交错延迟
// 用法：.transition(bounceIn(0)) / .transition(bounceIn(80))
export function bounceIn(delayMs: number): TransitionEffect {
  return TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 26 }))
    .combine(TransitionEffect.scale({ x: 0.94, y: 0.94 }))
    .animation({
      duration: 420,
      curve: MotionCurves.SOFT,
      delay: delayMs
    });
}

// 列表项交错入场：按下标递增延迟（索引过大时收敛到上限，避免长列表等待）
export function listBounceIn(index: number): TransitionEffect {
  const delayMs: number = Math.min(index * 45, 360);
  return TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 22 }))
    .combine(TransitionEffect.scale({ x: 0.96, y: 0.96 }))
    .animation({
      duration: 380,
      curve: MotionCurves.SOFT,
      delay: delayMs
    });
}

// 弹窗/浮层内容入场：更Q弹的放大回弹
export function popIn(delayMs: number = 0): TransitionEffect {
  return TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.8, y: 0.8 }))
    .animation({
      duration: 400,
      curve: MotionCurves.BOUNCY,
      delay: delayMs
    });
}

// ---------- 页面转场（router 跳转的 @Entry 页面统一风格） ----------
// 与既有报告页保持一致：子页面自右侧滑入、返回时右滑出。
// 在 @Entry struct 内添加 pageTransition() 方法，语句必须直接写在方法体内：
//
//   pageTransition() {
//     PageTransitionEnter({ type: RouteType.Push, duration: 360, curve: Curve.EaseInOut })
//       .slide(SlideEffect.Right)
//     PageTransitionEnter({ type: RouteType.Pop, duration: 300, curve: Curve.EaseInOut })
//       .opacity(0)
//     PageTransitionExit({ type: RouteType.Push, duration: 300, curve: Curve.EaseInOut })
//       .opacity(0)
//     PageTransitionExit({ type: RouteType.Pop, duration: 360, curve: Curve.EaseInOut })
//       .slide(SlideEffect.Right)
//   }
