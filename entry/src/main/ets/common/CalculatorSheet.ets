// 计算器弹层内容：由金额输入框旁的「计算器」按钮经 bindSheet 承载（半模态）
// 仅四则运算 + 括号 + 小数点；显示区实时预览求值结果，「使用结果」回填金额
import { evaluateExpression, formatCalcAmount } from './CalcExpr';
import { BrandSignals } from './V2Signals';
import { hapticTick } from './Haptics';
import { MotionCurves } from './Motion';

@ComponentV2
export struct CalculatorSheet {
  @Local brandSignals: BrandSignals = BrandSignals.connect();
  @Computed get brandMain(): string { return this.brandSignals.main; }
  // 进入计算器时带入的初始表达式（通常为当前金额文本，可继续按运算符续算）
  @Param initialExpr: string = '';
  // 计算结果确认回调：父组件回填金额并关闭弹层
  @Param onConfirm: (value: number) => void = () => {};
  @Local calcExpr: string = '';
  @Local pressedKey: string = '';

  // 4 列 × 5 行键盘布局
  private keyRows: string[][] = [
    ['C', '⌫', '(', ')'],
    ['7', '8', '9', '÷'],
    ['4', '5', '6', '×'],
    ['1', '2', '3', '-'],
    ['0', '.', '=', '+']
  ];

  aboutToAppear(): void {
    this.calcExpr = this.initialExpr;
  }

  @Computed
  get liveResult(): number | null {
    return evaluateExpression(this.calcExpr);
  }

  // 预览文本：表达式含运算符时显示实时结果；无法求值时提示无效
  @Computed
  get previewText(): string {
    if (this.calcExpr.length === 0) {
      return '';
    }
    const hasOp: boolean = this.calcExpr.includes('+') || this.calcExpr.includes('-') ||
      this.calcExpr.includes('×') || this.calcExpr.includes('÷') || this.calcExpr.includes('(');
    if (!hasOp) {
      return '';
    }
    const r: number | null = this.liveResult;
    if (r === null) {
      return '表达式无效';
    }
    return '= ' + formatCalcAmount(r);
  }

  private isDigitKey(key: string): boolean {
    return key >= '0' && key <= '9';
  }

  private keyTextColor(key: string): ResourceColor {
    if (key === '=') {
      return $r('app.color.text_white');
    }
    if (key === 'C') {
      return '#D94838';
    }
    if (key === '⌫') {
      return $r('app.color.text_secondary');
    }
    if (this.isDigitKey(key) || key === '.') {
      return $r('app.color.text_primary');
    }
    return this.brandMain;
  }

  private keyBgColor(key: string): ResourceColor {
    if (key === '=') {
      return this.brandMain;
    }
    if (this.isDigitKey(key) || key === '.') {
      return $r('app.color.card_bg');
    }
    return $r('app.color.category_btn_bg');
  }

  onCalcKey(key: string): void {
    hapticTick();
    if (key === 'C') {
      this.calcExpr = '';
      return;
    }
    if (key === '⌫') {
      this.calcExpr = this.calcExpr.substring(0, this.calcExpr.length - 1);
      return;
    }
    if (key === '=') {
      const r: number | null = evaluateExpression(this.calcExpr);
      if (r === null) {
        this.getUIContext().getPromptAction().showToast({ message: '表达式无效，请检查', duration: 1500 });
        return;
      }
      // 「=」把表达式折叠为结果，方便继续链式运算
      this.calcExpr = formatCalcAmount(r);
      return;
    }
    // 空表达式不允许以运算符/右括号/小数点开头（允许负号表示负数）
    if (this.calcExpr.length === 0 &&
      (key === '+' || key === '×' || key === '÷' || key === ')' || key === '.')) {
      return;
    }
    this.calcExpr += key;
  }

  confirmResult(): void {
    const r: number | null = evaluateExpression(this.calcExpr);
    if (r === null) {
      return;
    }
    this.onConfirm(r);
  }

  build() {
    Column() {
      Text('计算器')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .alignSelf(ItemAlign.Start)
        .margin({ top: 20, bottom: 12 })

      // 显示区：表达式 + 实时预览
      Column({ space: 4 }) {
        Text(this.calcExpr.length > 0 ? this.calcExpr : '0')
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.calcExpr.length > 0 ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .textAlign(TextAlign.End)
        if (this.previewText.length > 0) {
          Text(this.previewText)
            .fontSize(14)
            .fontColor(this.liveResult === null ? '#D94838' : $r('app.color.text_secondary'))
            .width('100%')
            .textAlign(TextAlign.End)
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .backgroundColor($r('app.color.card_bg'))
      .borderRadius(16)
      .margin({ bottom: 14 })

      // 键盘：4 列 × 5 行
      Column({ space: 8 }) {
        ForEach(this.keyRows, (rowKeys: string[]) => {
          Row({ space: 8 }) {
            ForEach(rowKeys, (key: string) => {
              Button(key)
                .fontSize(this.isDigitKey(key) ? 20 : 18)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.keyTextColor(key))
                .backgroundColor(this.keyBgColor(key))
                .borderRadius(14)
                .height(48)
                .layoutWeight(1)
                .padding(0)
                .scale({ x: this.pressedKey === key ? 0.92 : 1, y: this.pressedKey === key ? 0.92 : 1 })
                .animation({ curve: MotionCurves.PRESS })
                .onTouch((event: TouchEvent) => {
                  if (event.type === TouchType.Down) {
                    this.pressedKey = key;
                  } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                    this.pressedKey = '';
                  }
                })
                .onClick(() => { this.onCalcKey(key); })
            }, (key: string) => key)
          }
          .width('100%')
        }, (rowKeys: string[], rowIndex: number) => rowIndex.toString())
      }
      .width('100%')

      // 使用结果（无法求值时置灰不可点）
      Button('使用结果')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_white'))
        .backgroundColor(this.brandMain)
        .borderRadius(24)
        .height(46)
        .width('100%')
        .opacity(this.liveResult === null ? 0.4 : 1)
        .enabled(this.liveResult !== null)
        .margin({ top: 14 })
        .onClick(() => { this.confirmResult(); })
    }
    .width('100%')
    .padding({ left: 20, right: 20, bottom: 28 })
  }
}
