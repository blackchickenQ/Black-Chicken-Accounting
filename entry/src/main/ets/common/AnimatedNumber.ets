// ---------- 金额数字滚动组件：值变化时从当前显示值平滑滚动到目标值 ----------
// 用法：AnimatedNumber({ targetValue: this.monthExpense, fontSize: 26, fontColor: ... })
// 实现：animator 帧回调逐帧更新显示值（animateTo 只插值可动画属性，不逐帧更新普通状态变量）
// V2 状态管理：@Param 接收父组件目标值（值变化自动触发 @Monitor 重新滚动）+ @Local 当前显示值
import { AnimatorOptions, AnimatorResult } from '@kit.ArkUI';

@ComponentV2
export struct AnimatedNumber {
  // 目标金额：父组件数据变化时自动触发滚动
  @Param targetValue: number = 0;
  // 数字前缀，如 '¥' 或空字符串
  @Param prefix: string = '';
  // 小数位数（金额默认 2 位）
  @Param decimals: number = 2;
  // 是否给非负数加 '+' 号（结余类金额使用）
  @Param signed: boolean = false;
  // 样式透传
  @Param fontSize: number = 26;
  @Param fontWeight: FontWeight = FontWeight.Bold;
  @Param fontColor: ResourceColor = Color.White;
  // 滚动时长（毫秒）
  @Param durationMs: number = 800;
  // 当前显示值（帧回调驱动）
  @Local displayValue: number = 0;
  private countAnimator: AnimatorResult | null = null;

  aboutToAppear(): void {
    this.displayValue = 0;
    // 首帧延迟启动：确保组件已挂载、getUIContext 可用
    setTimeout(() => {
      this.animateToTarget();
    }, 60);
  }

  aboutToDisappear(): void {
    this.releaseAnimator();
  }

  @Monitor('targetValue')
  onTargetChange(): void {
    this.animateToTarget();
  }

  releaseAnimator(): void {
    if (this.countAnimator !== null) {
      this.countAnimator.cancel();
      this.countAnimator = null;
    }
  }

  animateToTarget(): void {
    const from: number = this.displayValue;
    const to: number = this.targetValue;
    if (from === to) {
      return;
    }
    this.releaseAnimator();
    try {
      const options: AnimatorOptions = {
        duration: this.durationMs,
        easing: 'fast-out-slow-in',
        delay: 0,
        fill: 'forwards',
        direction: 'normal',
        iterations: 1,
        begin: from,
        end: to
      };
      const result: AnimatorResult = this.getUIContext().createAnimator(options);
      result.onFrame = (value: number) => {
        this.displayValue = value;
      };
      result.onFinish = () => {
        this.displayValue = to;
        this.countAnimator = null;
      };
      this.countAnimator = result;
      result.play();
    } catch (e) {
      // 帧动画创建失败时直接落到目标值，保证功能可用
      this.displayValue = to;
    }
  }

  build() {
    Text(this.prefix + (this.signed && this.displayValue >= 0 ? '+' : '') + this.displayValue.toFixed(this.decimals))
      .fontSize(this.fontSize)
      .fontWeight(this.fontWeight)
      .fontColor(this.fontColor)
  }
}
