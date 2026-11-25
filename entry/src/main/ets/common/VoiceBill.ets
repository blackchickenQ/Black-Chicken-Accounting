// ---------- 语音记账：端侧语音识别（Core Speech Kit，纯离线）+ 语义解析金额/分类/来源 ----------
// 解析支持中文数字（二十五/三千五/一百零三/一万二/二十五点五）与阿拉伯数字，带不带「元/块」单位均可
import { speechRecognizer } from '@kit.CoreSpeechKit';
import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';

// 申请麦克风权限（user_grant，需在 module.json5 声明）
export async function requestMicPermission(context: common.UIAbilityContext): Promise<boolean> {
  try {
    const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    const result = await atManager.requestPermissionsFromUser(context, ['ohos.permission.MICROPHONE']);
    return result.authResults.length > 0 && result.authResults[0] === 0;
  } catch (e) {
    console.error('申请麦克风权限失败: ' + JSON.stringify(e));
    return false;
  }
}

// 语音文本解析结果
export interface VoiceBillParse {
  hasAmount: boolean;
  amount: number;
  name: string;
  isIncome: boolean;
  categoryHint: string;
  sourceHint: string;
}

// ---------- 中文数字解析 ----------
const CN_DIGIT_MAP: Record<string, number> = {
  '零': 0, '0': 0, '一': 1, '1': 1, '二': 2, '2': 2, '两': 2, '俩': 2,
  '三': 3, '3': 3, '四': 4, '4': 4, '五': 5, '5': 5, '六': 6, '6': 6,
  '七': 7, '7': 7, '八': 8, '8': 8, '九': 9, '9': 9
};
const CN_UNIT_MAP: Record<string, number> = { '十': 10, '百': 100, '千': 1000, '万': 10000 };
// 数字串字符类（中文数字 + 阿拉伯数字 + 小数点）
const NUM_CHARS: string = '零一二俩两三四五六七八九十百千万两点0-9.';

// 解析中文整数串：一百零三=103、两千零五十=2050、一百二十五=125、三千五=3500（口语）、一万二=12000
function parseCnInteger(s: string): number | null {
  if (s.length === 0) {
    return null;
  }
  // 纯阿拉伯数字直接转换
  if (/^[0-9]+$/.test(s)) {
    return Number(s);
  }
  // 末位是数字、倒数第二位是单位 → 单位段值 + 数字×(单位/10)：三千五=3500、二百五=250、十五=15、二十五=25
  const lastDigit: number | undefined = CN_DIGIT_MAP[s.charAt(s.length - 1)];
  const prevUnit: number | undefined = CN_UNIT_MAP[s.charAt(s.length - 2)];
  if (s.length >= 2 && lastDigit !== undefined && lastDigit > 0 && prevUnit !== undefined) {
    const head: number | null = parseCnInteger(s.substring(0, s.length - 1));
    if (head !== null) {
      return head + lastDigit * (prevUnit / 10);
    }
    return null;
  }
  // 标准解析（末位是单位或零：一百零三、两千零五十、一百、三千五百）
  let total: number = 0;
  let section: number = 0;
  let digit: number = 0;
  let sawAny: boolean = false;
  for (let i = 0; i < s.length; i++) {
    const ch: string = s.charAt(i);
    const d: number | undefined = CN_DIGIT_MAP[ch];
    if (d !== undefined) {
      digit = d;
      sawAny = true;
      continue;
    }
    const unit: number | undefined = CN_UNIT_MAP[ch];
    if (unit === undefined) {
      return null;
    }
    if (unit === 10000) {
      section = (section + digit) * 10000;
      total += section;
      section = 0;
      digit = 0;
    } else {
      // 十五 / 十：单位前无数字按 1 处理
      section += (digit === 0 ? 1 : digit) * unit;
      digit = 0;
    }
    sawAny = true;
  }
  if (!sawAny) {
    return null;
  }
  return total + section + digit;
}

// 解析一个数字串（中文/阿拉伯、可带「点」小数）：二十五点五=25.5、二十五=25、25.5=25.5
function parseCnNumber(s: string): number | null {
  const trimmed: string = s.trim();
  if (trimmed.length === 0) {
    return null;
  }
  if (/^[0-9]+(\.[0-9]{1,2})?$/.test(trimmed)) {
    const v: number = Number(trimmed);
    return v > 0 ? v : null;
  }
  const dotIdx: number = trimmed.indexOf('点');
  if (dotIdx < 0) {
    const intVal: number | null = parseCnInteger(trimmed);
    return intVal !== null && intVal > 0 ? intVal : null;
  }
  // 「点」小数：整数部分逐字解析，小数部分逐位累加
  const intVal: number | null = parseCnInteger(trimmed.substring(0, dotIdx));
  const decStr: string = trimmed.substring(dotIdx + 1);
  if (intVal === null || intVal <= 0 || decStr.length === 0) {
    return null;
  }
  let decVal: number = 0;
  let scale: number = 0.1;
  for (let i = 0; i < decStr.length && i < 2; i++) {
    const d: number | undefined = CN_DIGIT_MAP[decStr.charAt(i)];
    if (d === undefined) {
      return null;
    }
    decVal += d * scale;
    scale /= 10;
  }
  const value: number = intVal + decVal;
  return value > 0 ? value : null;
}

// 金额在文本中的位置与值
interface CnAmountSpan {
  value: number;
  start: number;
  end: number;
}

// 从语音文本提取金额：优先带「元/块」单位（十五块/二十五元/两块五/十五块五毛），其次句尾裸数字（午饭花了二十五）
function findAmountSpan(text: string): CnAmountSpan | null {
  // 1. 带单位的金额，取最后一个（金额一般后置）
  const unitRe: RegExp = new RegExp('([' + NUM_CHARS + ']+)\\s*(块钱|块|元|毛|角)', 'g');
  let m: RegExpExecArray | null = unitRe.exec(text);
  let unitMatch: CnAmountSpan | null = null;
  while (m !== null) {
    // 跳过与上一个金额重叠的匹配（十五块五毛 里的 五毛）
    if (unitMatch !== null && m.index < unitMatch.end) {
      m = unitRe.exec(text);
      continue;
    }
    const value: number | null = parseCnNumber(m[1]);
    if (value !== null) {
      let end: number = m.index + m[0].length;
      let final: number = value;
      // 「块」后跟单个数字表示「毛」：十五块五=15.5、两块五=2.5
      if (m[2] === '块' || m[2] === '块钱') {
        const rest: string = text.substring(end);
        const jiao: RegExpMatchArray | null = rest.match(/^([零一二三四五六七八九])[毛角]?/);
        if (jiao !== null) {
          const jd: number | undefined = CN_DIGIT_MAP[jiao[1]];
          if (jd !== undefined && jd > 0) {
            final = value + jd * 0.1;
            end += jiao[0].length;
          }
        }
      }
      unitMatch = { value: final, start: m.index, end: end };
    }
    m = unitRe.exec(text);
  }
  if (unitMatch !== null) {
    return unitMatch;
  }
  // 2. 无单位：句尾裸数字（允许尾随语气词/标点/空白）
  const bareRe: RegExp = new RegExp('[' + NUM_CHARS + ']+', 'g');
  let bareMatch: CnAmountSpan | null = null;
  m = bareRe.exec(text);
  while (m !== null) {
    const value: number | null = parseCnNumber(m[0]);
    if (value !== null) {
      const tail: string = text.substring(m.index + m[0].length);
      if (/^[了啊哦呀呢吧啦呗，,。！!？?\s]*$/.test(tail)) {
        bareMatch = { value: value, start: m.index, end: m.index + m[0].length };
      }
    }
    m = bareRe.exec(text);
  }
  return bareMatch;
}

const INCOME_RE: RegExp = /工资|薪水|收入|收到|红包|退款|奖金|进账|报销|利息|分红|收益|收款|返现|补贴|零花钱|压岁钱|闲鱼|卖出/;
const FILLER_RE: RegExp = /花了|花掉|花费|用了|用掉|付了|支付了|买了个?|买了点?|买了|充了|消费了?|总共|一共|记一?笔/g;
// 量词短语（两个包子 / 三杯咖啡）：从用途中剔除数量，避免混入
const QUANT_RE: RegExp = /[零一二俩两三四五六七八九十百0-9]+\s*[个只支杯瓶份碗盘条张次趟页颗箱盒包]/g;
const PUNCT_RE: RegExp = /[¥￥,，。！!、？?]/g;

// 分类关键词表（按顺序匹配，命中即停）
class CategoryKeyword {
  readonly category: string;
  readonly keywords: RegExp;

  constructor(category: string, keywords: string) {
    this.category = category;
    this.keywords = new RegExp(keywords);
  }
}

const CATEGORY_KEYWORDS: CategoryKeyword[] = [
  new CategoryKeyword('餐饮', '吃饭|午饭|晚饭|早餐|早饭|夜宵|外卖|奶茶|咖啡|饮料|零食|餐厅|食堂|买菜|火锅|烧烤|面|饭|餐|包子|饺子|馄饨|米线|麻辣烫|汉堡|披萨|寿司|蛋糕|甜品|面包|水果|茶|吃|喝'),
  new CategoryKeyword('交通', '打车|出租|地铁|公交|加油|油费|火车|高铁|机票|飞机|停车|滴滴|单车|骑车|车费|过路费|顺风车|大巴|客运|船票|坐车'),
  new CategoryKeyword('购物', '淘宝|京东|拼多多|超市|购物|网购|衣服|裤子|鞋|充值|日用|纸巾|洗衣液|牙膏|洗发水|买了'),
  new CategoryKeyword('娱乐', '电影|游戏|ktv|KTV|旅游|门票|会员|唱歌|剧本杀|桌游|网吧|演出|展览|密室|唱K'),
  new CategoryKeyword('医疗', '药|医院|看病|挂号|体检|诊所|牙|眼镜|口罩|打针'),
  new CategoryKeyword('教育', '书|课程|学费|培训|文具|网课|考试|打印|复印|报名')
];

// 来源口语同义词：说「刷卡」→ 银行卡
class SourceSynonym {
  readonly keyword: string;
  readonly target: string;

  constructor(keyword: string, target: string) {
    this.keyword = keyword;
    this.target = target;
  }
}

const SOURCE_SYNONYMS: SourceSynonym[] = [
  new SourceSynonym('刷卡', '银行卡'),
  new SourceSynonym('信用卡', '信用卡'),
  new SourceSynonym('花呗', '花呗'),
  new SourceSynonym('白条', '白条')
];

// 解析一句话账单：「午饭花了二十五块」→ 金额25、用途午饭、分类餐饮
export function parseVoiceBillText(raw: string, categories: string[], sources: string[]): VoiceBillParse {
  const text: string = raw.replace(/\s+/g, ' ').trim();
  const result: VoiceBillParse = {
    hasAmount: false,
    amount: 0,
    name: '',
    isIncome: INCOME_RE.test(text),
    categoryHint: '',
    sourceHint: ''
  };
  let nameText: string = text;
  const amountSpan: CnAmountSpan | null = findAmountSpan(text);
  if (amountSpan !== null) {
    result.hasAmount = true;
    result.amount = Math.round(amountSpan.value * 100) / 100;
    nameText = (text.substring(0, amountSpan.start) + ' ' + text.substring(amountSpan.end)).replace(/\s+/g, ' ');
  }
  // 清理语气词/量词短语/标点，剩下的作为用途
  result.name = nameText
    .replace(FILLER_RE, ' ')
    .replace(QUANT_RE, ' ')
    .replace(PUNCT_RE, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  // 分类：先直接匹配分类名（含自定义分类），再走关键词表
  for (let i = 0; i < categories.length; i++) {
    if (categories[i].length > 0 && text.indexOf(categories[i]) !== -1) {
      result.categoryHint = categories[i];
      break;
    }
  }
  if (result.categoryHint === '') {
    for (let i = 0; i < CATEGORY_KEYWORDS.length; i++) {
      if (CATEGORY_KEYWORDS[i].keywords.test(text)) {
        if (categories.indexOf(CATEGORY_KEYWORDS[i].category) !== -1) {
          result.categoryHint = CATEGORY_KEYWORDS[i].category;
        }
        break;
      }
    }
  }
  // 来源：先直接匹配资金账户名（微信/支付宝/自定义），再按口语同义词（刷卡→银行卡）
  for (let i = 0; i < sources.length; i++) {
    if (sources[i].length > 0 && text.indexOf(sources[i]) !== -1) {
      result.sourceHint = sources[i];
      break;
    }
  }
  if (result.sourceHint === '') {
    for (let i = 0; i < SOURCE_SYNONYMS.length; i++) {
      if (text.indexOf(SOURCE_SYNONYMS[i].keyword) !== -1
        && sources.indexOf(SOURCE_SYNONYMS[i].target) !== -1) {
        result.sourceHint = SOURCE_SYNONYMS[i].target;
        break;
      }
    }
  }
  return result;
}

// 端侧语音识别引擎封装：录音识别模式（recognitionMode 0），引擎自动采集麦克风音频
export class VoiceInputEngine {
  private engine: speechRecognizer.SpeechRecognitionEngine | null = null;
  private sessionId: string = '';

  async ensureEngine(): Promise<boolean> {
    if (this.engine !== null) {
      return true;
    }
    return new Promise<boolean>((resolve: (ok: boolean) => void) => {
      const extraParam: Record<string, Object> = { 'locate': 'CN', 'recognizerMode': 'short' };
      const params: speechRecognizer.CreateEngineParams = {
        language: 'zh-CN',
        online: 1,
        extraParams: extraParam
      };
      speechRecognizer.createEngine(params, (err: BusinessError, eng: speechRecognizer.SpeechRecognitionEngine) => {
        if (err) {
          console.error('语音引擎初始化失败: code=' + err.code + ' message=' + err.message);
          resolve(false);
          return;
        }
        this.engine = eng;
        resolve(true);
      });
    });
  }

  // 开始录音识别：onText 实时回调识别文本，onDone 识别完成，onFail 出错
  start(onText: (text: string, isLast: boolean) => void,
    onDone: () => void,
    onFail: (message: string) => void): void {
    if (this.engine === null) {
      onFail('语音引擎未初始化');
      return;
    }
    this.sessionId = util.generateRandomUUID();
    const listener: speechRecognizer.RecognitionListener = {
      onStart: (sessionId: string, eventMessage: string) => {
      },
      onEvent: (sessionId: string, eventCode: number, eventMessage: string) => {
      },
      onResult: (sessionId: string, result: speechRecognizer.SpeechRecognitionResult) => {
        onText(result.result, result.isLast);
      },
      onComplete: (sessionId: string, eventMessage: string) => {
        onDone();
      },
      onError: (sessionId: string, errorCode: number, errorMessage: string) => {
        onFail(errorMessage);
      }
    };
    this.engine.setListener(listener);
    const audioParam: speechRecognizer.AudioInfo = { audioType: 'pcm', sampleRate: 16000, soundChannel: 1, sampleBit: 16 };
    const extraParam: Record<string, Object> = {
      'recognitionMode': 0,
      'vadBegin': 2000,
      'vadEnd': 2500,
      'maxAudioDuration': 20000
    };
    const startParams: speechRecognizer.StartParams = {
      sessionId: this.sessionId,
      audioInfo: audioParam,
      extraParams: extraParam
    };
    this.engine.startListening(startParams);
  }

  // 结束说话（触发最终识别结果）
  finishSession(): void {
    if (this.engine !== null && this.sessionId.length > 0) {
      this.engine.finish(this.sessionId);
    }
  }

  // 取消本次识别（不产生结果）
  cancelSession(): void {
    if (this.engine !== null && this.sessionId.length > 0) {
      this.engine.cancel(this.sessionId);
    }
  }

  // 释放引擎资源
  shutdownEngine(): void {
    if (this.engine !== null) {
      this.engine.shutdown();
      this.engine = null;
    }
  }
}
