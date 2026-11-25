// ---------- 小票 OCR：端侧文字识别（Core Vision Kit），自动提取金额/日期/商户/支付方式 ----------
// 纯离线能力，无需联网与权限；识别失败时静默回退，用户手动填写
import { textRecognition } from '@kit.CoreVisionKit';
import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';

export interface OcrBillInfo {
  hasAmount: boolean;
  amount: number;
  hasDate: boolean;
  dateMs: number;
  hasMerchant: boolean;
  merchant: string;
  fullText: string;
}

interface OcrNumber {
  value: number;
  hasDecimal: boolean;
}

const FILE_PREFIX: string = 'file://';
const MIN_AMOUNT: number = 0.01;
const MAX_AMOUNT: number = 9999999;

// 含这些词的行是单号/电话等，其中的数字不是金额
const SKIP_LINE_RE: RegExp = /订单号|单号|编号|流水|电话|手机号|券码|卡号|小票号|会员|积分/;

// 日期/时间行不参与金额提取
const DATE_LINE_RE: RegExp = /日期|时间|date|time/i;

// 显式商户标注：商户名称：xxx / 收款方 xxx 等
const MERCHANT_TAG_RE: RegExp =
  /(?:商户全称|商户名称|收款方|对方账户|门店名称|店铺名称|商户|门店|店铺)[：:\s]+([^\s：:][^：:\n]{1,19})/;

// 头部启发式取商户名时跳过的噪音行（含截图中常见的界面文字）
const MERCHANT_NOISE_RE: RegExp =
  /小票|收银|订单|单号|欢迎|电话|地址|客服|会员|合计|金额|优惠|折扣|支付|日期|时间|编号|流水|收银员|扫码|关注|公众号|网址|www|http|\.com|服务|导购|\btab\b|\bapp\b|wifi|二维码|凭证/i;

// 支付方式别名（与 PAYMENT_KEYS 一一对应）
const PAYMENT_KEYS: string[] = ['支付宝', '微信', '银行卡', '现金'];
const PAYMENT_ALIASES: string[][] = [
  ['支付宝', 'alipay'],
  ['微信', 'wechat', 'wxpay'],
  ['银行卡', '储蓄卡', '信用卡', '云闪付', '银联', 'pos'],
  ['现金']
];

function lineScore(line: string): number {
  if (/实付|实收/.test(line)) {
    return 5;
  }
  if (/合计|总计|应付/.test(line)) {
    return 4;
  }
  if (/金额|小计|total|amount/i.test(line)) {
    return 3;
  }
  if (/[¥￥]/.test(line)) {
    return 2;
  }
  return 1;
}

// 剔除行内的日期/时间片段，避免「2026.10.28」「12:30」等被当作金额
function stripDateAndTime(line: string): string {
  let s: string = line;
  s = s.replace(/(\d{4})[年./-](\d{1,2})[月./-](\d{1,2})日?/g, ' ');
  s = s.replace(/\b\d{4}\d{2}\d{2}\b/g, ' ');
  s = s.replace(/\d{1,2}:\d{2}(:\d{2})?/g, ' ');
  return s;
}

// 从一行文本中提取候选金额数字（兼容千分位与逗号小数）
function extractAmountNumbers(line: string): OcrNumber[] {
  const out: OcrNumber[] = [];
  const norm: string = line.replace(/，/g, ',').replace(/．/g, '.');
  const matches = norm.match(/[0-9]+(?:[.,][0-9]{1,2})?/g);
  if (matches === null) {
    return out;
  }
  for (let i = 0; i < matches.length; i++) {
    const token: string = matches[i];
    let normalized: string = token;
    let hasDecimal: boolean = false;
    if (token.indexOf(',') >= 0) {
      // 「1,234」或「1,234.56」按千分位处理；「12,50」按逗号小数处理
      if (token.indexOf('.') >= 0 || /,\d{3}/.test(token)) {
        normalized = token.replace(/,/g, '');
        hasDecimal = token.indexOf('.') >= 0;
      } else {
        normalized = token.replace(',', '.');
        hasDecimal = true;
      }
    } else if (token.indexOf('.') >= 0) {
      hasDecimal = true;
    }
    const value: number = parseFloat(normalized);
    if (!isNaN(value)) {
      out.push({ value: value, hasDecimal: hasDecimal });
    }
  }
  return out;
}

// 全部行中挑出最可能的金额：先看关键词权重，同权重优先带小数，再取较大值
function pickAmount(lines: string[]): number | null {
  let bestValue: number = -1;
  let bestScore: number = -1;
  let bestHasDecimal: boolean = false;
  for (let i = 0; i < lines.length; i++) {
    const rawLine: string = lines[i];
    if (SKIP_LINE_RE.test(rawLine) || DATE_LINE_RE.test(rawLine)) {
      continue;
    }
    const line: string = stripDateAndTime(rawLine);
    if (line.trim().length === 0) {
      continue;
    }
    const score: number = lineScore(line);
    const nums: OcrNumber[] = extractAmountNumbers(line);
    for (let j = 0; j < nums.length; j++) {
      const n: number = nums[j].value;
      if (n < MIN_AMOUNT || n > MAX_AMOUNT) {
        continue;
      }
      const hasDecimal: boolean = nums[j].hasDecimal;
      // 无关键词、无货币符号的行只接受带小数的数字，避免日期/数量被当成金额
      if (score <= 1 && !hasDecimal) {
        continue;
      }
      if (score > bestScore ||
        (score === bestScore && hasDecimal && !bestHasDecimal) ||
        (score === bestScore && hasDecimal === bestHasDecimal && n > bestValue)) {
        bestScore = score;
        bestValue = n;
        bestHasDecimal = hasDecimal;
      }
    }
  }
  return bestValue > 0 ? bestValue : null;
}

function buildDateMs(year: number, month: number, day: number): number {
  if (year < 2000 || year > 2099 || month < 1 || month > 12 || day < 1 || day > 31) {
    return 0;
  }
  const daysInMonth: number = new Date(year, month, 0).getDate();
  if (day > daysInMonth) {
    return 0;
  }
  return new Date(year, month - 1, day).getTime();
}

// 提取小票上的日期：优先带分隔符写法，其次紧凑写法（20261028）
function parseDateFromText(text: string): number {
  const sepMatch = text.match(/(\d{4})[年./-](\d{1,2})[月./-](\d{1,2})日?/);
  if (sepMatch !== null) {
    const ms: number = buildDateMs(Number(sepMatch[1]), Number(sepMatch[2]), Number(sepMatch[3]));
    if (ms > 0) {
      return ms;
    }
  }
  const compactMatch = text.match(/\b(\d{4})(\d{2})(\d{2})\b/);
  if (compactMatch !== null) {
    const ms: number = buildDateMs(Number(compactMatch[1]), Number(compactMatch[2]), Number(compactMatch[3]));
    if (ms > 0) {
      return ms;
    }
  }
  return 0;
}

function isValidMerchantName(name: string): boolean {
  if (name.length < 2 || name.length > 20) {
    return false;
  }
  if (/订单|单号|编号|流水|电话/.test(name)) {
    return false;
  }
  return /[\u4e00-\u9fa5A-Za-z]/.test(name);
}

// 提取商户名：优先「商户名称: xxx」等显式标注，其次取小票头部第一条像店名的文本
function pickMerchant(lines: string[]): string | null {
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(MERCHANT_TAG_RE);
    if (m !== null) {
      const name: string = m[1].trim();
      if (isValidMerchantName(name)) {
        return name;
      }
    }
  }
  const scanCount: number = Math.min(lines.length, 5);
  for (let i = 0; i < scanCount; i++) {
    const line: string = lines[i].trim();
    if (line.length < 2 || line.length > 20) {
      continue;
    }
    if (MERCHANT_NOISE_RE.test(line)) {
      continue;
    }
    // 中文店名至少 2 个连续汉字；纯英文店名至少 4 个连续字母（过滤 tab/app 等界面短词）
    if (!/[\u4e00-\u9fa5]{2,}/.test(line) && !/[a-zA-Z]{4,}/.test(line)) {
      continue;
    }
    return line;
  }
  return null;
}

// 从 OCR 全文判断支付方式：先按来源列表直接命中，再按常见别名映射；仅返回 sources 中存在的来源
export function pickPayment(fullText: string, sources: string[]): string | null {
  const lower: string = fullText.toLowerCase();
  for (let i = 0; i < sources.length; i++) {
    const src: string = sources[i];
    if (src.length >= 2 && lower.indexOf(src.toLowerCase()) >= 0) {
      return src;
    }
  }
  for (let i = 0; i < PAYMENT_KEYS.length; i++) {
    const target: string = PAYMENT_KEYS[i];
    if (sources.indexOf(target) === -1) {
      continue;
    }
    const aliases: string[] = PAYMENT_ALIASES[i];
    for (let j = 0; j < aliases.length; j++) {
      if (lower.indexOf(aliases[j]) >= 0) {
        return target;
      }
    }
  }
  return null;
}

function buildOcrInfo(lines: string[]): OcrBillInfo {
  const info: OcrBillInfo = {
    hasAmount: false,
    amount: 0,
    hasDate: false,
    dateMs: 0,
    hasMerchant: false,
    merchant: '',
    fullText: lines.join('\n')
  };
  const amount: number | null = pickAmount(lines);
  if (amount !== null) {
    info.hasAmount = true;
    info.amount = amount;
  }
  const dateMs: number = parseDateFromText(lines.join(' '));
  if (dateMs > 0) {
    info.hasDate = true;
    info.dateMs = dateMs;
  }
  const merchant: string | null = pickMerchant(lines);
  if (merchant !== null) {
    info.hasMerchant = true;
    info.merchant = merchant;
  }
  return info;
}

// 对一张沙箱小票图片做端侧 OCR，返回提取到的金额/日期/商户与全文；失败返回 null
export async function recognizeBillInfo(photoUri: string): Promise<OcrBillInfo | null> {
  const path: string = photoUri.startsWith(FILE_PREFIX) ? photoUri.substring(FILE_PREFIX.length) : photoUri;
  if (!fs.accessSync(path)) {
    console.error('小票OCR：文件不存在 ' + photoUri);
    return null;
  }
  let file: fs.File | undefined = undefined;
  let imageSource: image.ImageSource | undefined = undefined;
  let pixelMap: image.PixelMap | undefined = undefined;
  try {
    file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    imageSource = image.createImageSource(file.fd);
    pixelMap = await imageSource.createPixelMap();
    const inited: boolean = await textRecognition.init();
    if (!inited) {
      console.error('小票OCR：初始化失败');
      return null;
    }
    try {
      const visionInfo: textRecognition.VisionInfo = { pixelMap: pixelMap };
      const result: textRecognition.TextRecognitionResult = await textRecognition.recognizeText(visionInfo);
      const lines: string[] = [];
      for (let bi = 0; bi < result.blocks.length; bi++) {
        const blockLines = result.blocks[bi].lines;
        for (let li = 0; li < blockLines.length; li++) {
          lines.push(blockLines[li].value);
        }
      }
      return buildOcrInfo(lines);
    } finally {
      await textRecognition.release();
    }
  } catch (e) {
    console.error('小票OCR识别失败: ' + JSON.stringify(e));
    return null;
  } finally {
    if (pixelMap) {
      void pixelMap.release();
    }
    if (imageSource) {
      void imageSource.release();
    }
    if (file) {
      fs.closeSync(file);
    }
  }
}
