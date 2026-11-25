// 四则运算表达式求值：手写递归下降解析器（ArkTS 禁用 eval，且动态求值有安全风险）
// 支持 + - * / ( ) 与小数点、一元正负号；显示用的 × ÷ 会先归一化为 * /
// 语法：expr := term (('+'|'-') term)*；term := factor (('*'|'/') factor)*；
//       factor := '(' expr ')' | ('+'|'-') factor | number
class ExprParser {
  private src: string;
  private pos: number;

  constructor(src: string) {
    this.src = src;
    this.pos = 0;
  }

  private skipSpaces(): void {
    while (this.pos < this.src.length && this.src.charAt(this.pos) === ' ') {
      this.pos++;
    }
  }

  private peek(): string {
    if (this.pos < this.src.length) {
      return this.src.charAt(this.pos);
    }
    return '';
  }

  // 是否已消费到末尾（跳过尾部空白）
  finished(): boolean {
    this.skipSpaces();
    return this.pos >= this.src.length;
  }

  parseExpr(): number | null {
    let value: number | null = this.parseTerm();
    while (value !== null) {
      this.skipSpaces();
      const c: string = this.peek();
      if (c === '+' || c === '-') {
        this.pos++;
        const rhs: number | null = this.parseTerm();
        if (rhs === null) {
          return null;
        }
        value = c === '+' ? value + rhs : value - rhs;
      } else {
        break;
      }
    }
    return value;
  }

  private parseTerm(): number | null {
    let value: number | null = this.parseFactor();
    while (value !== null) {
      this.skipSpaces();
      const c: string = this.peek();
      if (c === '*' || c === '/') {
        this.pos++;
        const rhs: number | null = this.parseFactor();
        if (rhs === null) {
          return null;
        }
        if (c === '/' && rhs === 0) {
          return null; // 除零视为非法表达式
        }
        value = c === '*' ? value * rhs : value / rhs;
      } else {
        break;
      }
    }
    return value;
  }

  private parseFactor(): number | null {
    this.skipSpaces();
    const c: string = this.peek();
    if (c === '(') {
      this.pos++;
      const inner: number | null = this.parseExpr();
      if (inner === null) {
        return null;
      }
      this.skipSpaces();
      if (this.peek() !== ')') {
        return null;
      }
      this.pos++;
      return inner;
    }
    if (c === '-') {
      this.pos++;
      const v: number | null = this.parseFactor();
      if (v === null) {
        return null;
      }
      return -v;
    }
    if (c === '+') {
      this.pos++;
      return this.parseFactor();
    }
    return this.parseNumber();
  }

  private parseNumber(): number | null {
    this.skipSpaces();
    const start: number = this.pos;
    while (this.pos < this.src.length) {
      const ch: string = this.src.charAt(this.pos);
      if ((ch >= '0' && ch <= '9') || ch === '.') {
        this.pos++;
      } else {
        break;
      }
    }
    if (start === this.pos) {
      return null;
    }
    const numStr: string = this.src.substring(start, this.pos);
    let dotCount: number = 0;
    for (let i = 0; i < numStr.length; i++) {
      if (numStr.charAt(i) === '.') {
        dotCount++;
      }
    }
    if (dotCount > 1) {
      return null;
    }
    const value: number = Number(numStr);
    if (isNaN(value)) {
      return null;
    }
    return value;
  }
}

// 求值四则表达式；空串、括号不配对、非法字符、除零、尾部残留等一律返回 null
export function evaluateExpression(input: string): number | null {
  if (input === undefined || input === null) {
    return null;
  }
  const src: string = input.replace(/×/g, '*').replace(/÷/g, '/').trim();
  if (src.length === 0) {
    return null;
  }
  const parser: ExprParser = new ExprParser(src);
  const result: number | null = parser.parseExpr();
  if (result === null) {
    return null;
  }
  if (!parser.finished()) {
    return null; // 末尾有无法解析的残留字符
  }
  if (!isFinite(result)) {
    return null;
  }
  // 归一化浮点误差（0.1+0.2 之类），保留 10 位小数精度
  return Math.round(result * 1e10) / 1e10;
}

// 计算结果格式化为金额文本：四舍五入到两位小数并去掉多余的 0（40 → "40"，40.5 → "40.5"）
export function formatCalcAmount(value: number): string {
  const rounded: number = Math.round(value * 100) / 100;
  return String(rounded);
}
