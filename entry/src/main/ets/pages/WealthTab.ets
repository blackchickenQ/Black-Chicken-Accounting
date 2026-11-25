import dataPreferences from '@ohos.data.preferences';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { AnimationConfig, BillItem, DEFAULT_LEDGER_ID, LedgerItem } from './Index';
import { MotionCurves } from '../common/Motion';
import { ASSET_PALETTE } from '../common/AppTheme';
import { HandIcon } from '../common/HandIcon';
import {
  CHALLENGE_TEMPLATES,
  ChallengeTemplate,
  WISH_COOLING_DAYS,
  WishItem,
  loadWishes,
  saveWishes,
  wishCoolingRemain,
  getChallengeTemplate,
  getChallengeCurrentPeriod,
  getChallengePeriodAmount,
  getChallengePlannedTotal
} from '../common/Gameplay';
import { BrandSignals, ColorModeSignals, DeviceSignals, WealthSignals } from '../common/V2Signals';

interface FundAccount {
  name: string;
  amount: number;
}

interface CreditAccount {
  id: number;
  name: string;
  debt: number;
  dueDate: number;  // 还款日时间戳，0 = 未设置
}

export interface SavingGoal {
  id: number;
  name: string;
  target: number;
  saved: number;
  deadline: number;  // 截止日时间戳，0 = 未设置
  records?: GoalRecord[];  // 攒钱旅程记录（存入/日记），旧数据无此字段
  challengeType?: string;    // 52周/30天挑战模板 id，普通目标无此字段
  challengeStart?: number;   // 挑战发起时间戳
  billOnDeposit?: boolean;   // 挑战目标：每笔存入是否同步记一笔支出账单（计入收支）
  remindChallenge?: boolean; // 挑战目标：是否在提醒中心按每期（每天/每周）提醒应存金额
}

// 攒钱旅程单条记录：amount > 0 为存入，amount = 0 为纯日记心得
export interface GoalRecord {
  id: number;
  amount: number;
  note: string;
  time: number;  // 创建时间戳
}

// 目标详情页路由参数
export interface GoalDetailParams {
  id: number;  // 目标 id
}

// 某月收支汇总
interface MonthFlows {
  income: number;
  expense: number;
}

// 净资产趋势点
interface NetAssetPoint {
  label: string;
  value: number;
}

// 财务健康度单项指标
interface HealthItem {
  name: string;
  valueText: string;
  score: number;  // 0-25
}

// 财务健康度综合结果
interface HealthResult {
  score: number;   // 0-100
  grade: string;
  items: HealthItem[];
  suggestions: string[];
}

// 用户财务画像（问卷答案）
interface FinanceProfile {
  incomeStable: string;  // '稳定' | '波动大' | '' 未填
  fixedExpense: string;  // '有房贷/房租' | '无' | ''
  emergency: string;     // '充足' | '一般' | '没有储备' | ''
  debtStatus: string;    // '无负债' | '少量分期' | '有贷款压力' | ''
  riskPref: string;      // '保守' | '平衡' | '进取' | ''
  investExp: string;     // '无理财经验' | '低风险为主' | '有权益类投资' | ''
}

const PROFILE_INCOME_OPTIONS: string[] = ['稳定（工资为主）', '波动大（自由职业/经营）'];
const PROFILE_FIXED_OPTIONS: string[] = ['有房贷/房租', '无'];
const PROFILE_EMERGENCY_OPTIONS: string[] = ['充足（3个月以上）', '一般（1-3个月）', '没有储备'];
const PROFILE_DEBT_OPTIONS: string[] = ['无负债', '少量消费分期', '有房贷车贷压力'];
const PROFILE_RISK_OPTIONS: string[] = ['保守', '平衡', '进取'];
const PROFILE_INVEST_OPTIONS: string[] = ['无理财经验', '低风险为主（存款/货基）', '有权益类投资（股/基）'];

// ========== 信用账户编辑弹窗 ==========
@CustomDialog
struct CreditAccountDialog {
  @StorageProp('brand_main') brandMain: string = '#4E6EF2';
  controller: CustomDialogController = new CustomDialogController({
    builder: () => {}
  });
  @State inputName: string = '';
  @State inputDebt: string = '';
  @State dueDate: number = 0;  // 还款日时间戳，0 = 未设置
  title: string = '添加信用账户';
  confirmText: string = '确定';
  onConfirm: (name: string, debt: number, dueDate: number) => void = () => {};
  onCancel?: () => void;

  formatDueDate(ts: number): string {
    const d = new Date(ts);
    return `${d.getFullYear()}年${d.getMonth() + 1}月${d.getDate()}日`;
  }

  build() {
    Column() {
      Text(this.title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .alignSelf(ItemAlign.Start)
        .margin({ bottom: 16 })

      TextInput({ placeholder: '账户名称（如：招商信用卡、花呗）', text: this.inputName })
        .width('100%')
        .height(44)
        .fontSize(16)
        .borderRadius(12)
        .backgroundColor($r('app.color.card_bg'))
        .borderColor($r('app.color.border_color'))
        .borderWidth(1)
        .padding({ left: 16, right: 16 })
        .onChange((val: string) => { this.inputName = val; })
        .margin({ bottom: 12 })

      TextInput({ placeholder: '欠款金额', text: this.inputDebt })
        .width('100%')
        .height(44)
        .fontSize(16)
        .borderRadius(12)
        .backgroundColor($r('app.color.card_bg'))
        .borderColor($r('app.color.border_color'))
        .borderWidth(1)
        .padding({ left: 16, right: 16 })
        .type(InputType.NUMBER_DECIMAL)
        .onChange((val: string) => { this.inputDebt = val; })
        .margin({ bottom: 12 })

      // 还款日选择行
      Row() {
        Text('还款日')
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
        Blank()
        if (this.dueDate > 0) {
          Text('清除')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .onClick(() => { this.dueDate = 0; })
        }
        Text(this.dueDate > 0 ? this.formatDueDate(this.dueDate) : '未设置')
          .fontSize(14)
          .fontColor(this.dueDate > 0 ? this.brandMain : $r('app.color.text_secondary'))
          .margin({ left: 8 })
      }
      .width('100%')
      .height(44)
      .borderRadius(12)
      .backgroundColor($r('app.color.card_bg'))
      .border({ width: 1, color: $r('app.color.border_color') })
      .padding({ left: 16, right: 16 })
      .margin({ bottom: 20 })
      .onClick(() => {
        this.getUIContext().showDatePickerDialog({
          start: new Date('2020-01-01'),
          end: new Date('2099-12-31'),
          selected: this.dueDate > 0 ? new Date(this.dueDate) : new Date(),
          onDateAccept: (value: Date) => {
            this.dueDate = value.getTime();
          }
        });
      })

      Row() {
        Button('取消')
          .backgroundColor('transparent')
          .fontColor($r('app.color.text_secondary'))
          .borderRadius(20)
          .height(40)
          .layoutWeight(1)
          .onClick(() => {
            this.onCancel?.();
          })

        Blank().width(16)

        Button(this.confirmText)
          .backgroundColor(this.brandMain)
          .fontColor($r('app.color.text_white'))
          .borderRadius(22)
          .height(44)
          .layoutWeight(1)
          .onClick(() => {
            const name = this.inputName.trim();
            const debt = parseFloat(this.inputDebt);
            if (!name) {
              this.getUIContext().getPromptAction().showToast({ message: '请输入账户名称', duration: 1500 });
              return;
            }
            if (isNaN(debt) || debt < 0) {
              this.getUIContext().getPromptAction().showToast({ message: '请输入有效金额', duration: 1500 });
              return;
            }
            this.onConfirm(name, debt, this.dueDate);
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

// ========== 资金账户编辑弹窗 ==========
@CustomDialog
struct FundAccountDialog {
  @StorageProp('brand_main') brandMain: string = '#4E6EF2';
  controller: CustomDialogController = new CustomDialogController({
    builder: () => {}
  });
  @State inputName: string = '';
  @State inputAmount: string = '';
  title: string = '添加资金账户';
  confirmText: string = '确定';
  onConfirm: (name: string, amount: number) => void = () => {};
  onCancel?: () => void;

  build() {
    Column() {
      Text(this.title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .alignSelf(ItemAlign.Start)
        .margin({ bottom: 16 })

      TextInput({ placeholder: '账户名称（如：微信、支付宝）', text: this.inputName })
        .width('100%')
        .height(44)
        .fontSize(16)
        .borderRadius(12)
        .backgroundColor($r('app.color.card_bg'))
        .borderColor($r('app.color.border_color'))
        .borderWidth(1)
        .padding({ left: 16, right: 16 })
        .onChange((val: string) => { this.inputName = val; })
        .margin({ bottom: 12 })

      TextInput({ placeholder: '账户余额', text: this.inputAmount })
        .width('100%')
        .height(44)
        .fontSize(16)
        .borderRadius(12)
        .backgroundColor($r('app.color.card_bg'))
        .borderColor($r('app.color.border_color'))
        .borderWidth(1)
        .padding({ left: 16, right: 16 })
        .type(InputType.NUMBER_DECIMAL)
        .onChange((val: string) => { this.inputAmount = val; })
        .margin({ bottom: 20 })

      Row() {
        Button('取消')
          .backgroundColor('transparent')
          .fontColor($r('app.color.text_secondary'))
          .borderRadius(20)
          .height(40)
          .layoutWeight(1)
          .onClick(() => {
            this.onCancel?.();
          })

        Blank().width(16)

        Button(this.confirmText)
          .backgroundColor(this.brandMain)
          .fontColor($r('app.color.text_white'))
          .borderRadius(22)
          .height(44)
          .layoutWeight(1)
          .onClick(() => {
            const name = this.inputName.trim();
            const amount = parseFloat(this.inputAmount);
            if (!name) {
              this.getUIContext().getPromptAction().showToast({ message: '请输入账户名称', duration: 1500 });
              return;
            }
            if (isNaN(amount)) {
              this.getUIContext().getPromptAction().showToast({ message: '请输入有效金额', duration: 1500 });
              return;
            }
            this.onConfirm(name, amount);
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

// ========== 存钱目标编辑弹窗 ==========
@CustomDialog
export struct SavingGoalDialog {
  @StorageProp('brand_main') brandMain: string = '#4E6EF2';
  controller: CustomDialogController = new CustomDialogController({
    builder: () => {}
  });
  @State inputName: string = '';
  @State inputTarget: string = '';
  @State inputSaved: string = '';
  @State deadline: number = 0;  // 截止日时间戳，0 = 未设置
  @State unitWan: boolean = false;  // 金额单位：false 个（元）| true 万
  title: string = '添加存钱目标';
  confirmText: string = '确定';
  onConfirm: (name: string, target: number, saved: number, deadline: number) => void = () => {};
  onCancel?: () => void;

  formatDeadline(ts: number): string {
    const d = new Date(ts);
    return `${d.getFullYear()}年${d.getMonth() + 1}月${d.getDate()}日`;
  }

  build() {
    Column() {
      Text(this.title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .alignSelf(ItemAlign.Start)
        .margin({ bottom: 16 })

      // 金额单位切换（个 / 万，滑块过渡）
      Row() {
        Text('金额单位')
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Stack({ alignContent: Alignment.Start }) {
          Column()
            .width(40)
            .height(28)
            .borderRadius(14)
            .backgroundColor($r('app.color.category_btn_bg'))
            .offset({ x: this.unitWan ? 40 : 0 })

          Row() {
            Text('个')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.unitWan ? $r('app.color.text_secondary') : this.brandMain)
              .width(40)
              .height(28)
              .textAlign(TextAlign.Center)
              .onClick(() => {
                animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => { this.unitWan = false; });
              })

            Text('万')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.unitWan ? this.brandMain : $r('app.color.text_secondary'))
              .width(40)
              .height(28)
              .textAlign(TextAlign.Center)
              .onClick(() => {
                animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => { this.unitWan = true; });
              })
          }
        }
        .height(30)
        .borderRadius(15)
        .border({ width: 1, color: $r('app.color.border_color') })
        .backgroundColor($r('app.color.card_bg'))
      }
      .width('100%')
      .margin({ bottom: 16 })

      TextInput({ placeholder: '目标名称（如：旅行基金）', text: this.inputName })
        .width('100%')
        .height(44)
        .fontSize(16)
        .borderRadius(12)
        .backgroundColor($r('app.color.card_bg'))
        .borderColor($r('app.color.border_color'))
        .borderWidth(1)
        .padding({ left: 16, right: 16 })
        .onChange((val: string) => { this.inputName = val; })
        .margin({ bottom: 12 })

      TextInput({ placeholder: this.unitWan ? '目标金额（万元）' : '目标金额（元）', text: this.inputTarget })
        .width('100%')
        .height(44)
        .fontSize(16)
        .borderRadius(12)
        .backgroundColor($r('app.color.card_bg'))
        .borderColor($r('app.color.border_color'))
        .borderWidth(1)
        .padding({ left: 16, right: 16 })
        .type(InputType.NUMBER_DECIMAL)
        .onChange((val: string) => { this.inputTarget = val; })
        .margin({ bottom: 12 })

      TextInput({ placeholder: this.unitWan ? '已存金额（万元）' : '已存金额（元）', text: this.inputSaved })
        .width('100%')
        .height(44)
        .fontSize(16)
        .borderRadius(12)
        .backgroundColor($r('app.color.card_bg'))
        .borderColor($r('app.color.border_color'))
        .borderWidth(1)
        .padding({ left: 16, right: 16 })
        .type(InputType.NUMBER_DECIMAL)
        .onChange((val: string) => { this.inputSaved = val; })
        .margin({ bottom: 12 })

      // 截止日期选择行（可选）
      Row() {
        Text('截止日期')
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
        Blank()
        if (this.deadline > 0) {
          Text('清除')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .onClick(() => { this.deadline = 0; })
        }
        Text(this.deadline > 0 ? this.formatDeadline(this.deadline) : '不设置')
          .fontSize(14)
          .fontColor(this.deadline > 0 ? this.brandMain : $r('app.color.text_secondary'))
          .margin({ left: 8 })
      }
      .width('100%')
      .height(44)
      .borderRadius(12)
      .backgroundColor($r('app.color.card_bg'))
      .border({ width: 1, color: $r('app.color.border_color') })
      .padding({ left: 16, right: 16 })
      .margin({ bottom: 20 })
      .onClick(() => {
        this.getUIContext().showDatePickerDialog({
          start: new Date(),
          end: new Date('2099-12-31'),
          selected: this.deadline > 0 ? new Date(this.deadline) : new Date(),
          onDateAccept: (value: Date) => {
            this.deadline = value.getTime();
          }
        });
      })

      Row() {
        Button('取消')
          .backgroundColor('transparent')
          .fontColor($r('app.color.text_secondary'))
          .borderRadius(20)
          .height(40)
          .layoutWeight(1)
          .onClick(() => {
            this.onCancel?.();
          })

        Blank().width(16)

        Button(this.confirmText)
          .backgroundColor(this.brandMain)
          .fontColor($r('app.color.text_white'))
          .borderRadius(22)
          .height(44)
          .layoutWeight(1)
          .onClick(() => {
            const name = this.inputName.trim();
            const targetRaw = parseFloat(this.inputTarget);
            const savedRaw = parseFloat(this.inputSaved);
            if (!name) {
              this.getUIContext().getPromptAction().showToast({ message: '请输入目标名称', duration: 1500 });
              return;
            }
            if (isNaN(targetRaw) || targetRaw <= 0) {
              this.getUIContext().getPromptAction().showToast({ message: '请输入有效的目标金额', duration: 1500 });
              return;
            }
            // 按所选单位换算成元，并消除浮点误差
            const multiplier = this.unitWan ? 10000 : 1;
            const target = Math.round(targetRaw * multiplier * 100) / 100;
            const saved = isNaN(savedRaw) || savedRaw < 0 ? 0 : Math.round(savedRaw * multiplier * 100) / 100;
            this.onConfirm(name, target, saved, this.deadline);
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

// ========== 52周 / 30天存钱挑战发起弹窗 ==========
@CustomDialog
struct ChallengeStartDialog {
  @StorageProp('brand_main') brandMain: string = '#4E6EF2';
  controller: CustomDialogController = new CustomDialogController({
    builder: () => {}
  });
  @State selectedId: string = 'week52';
  @State billOnDeposit: boolean = false;  // 存入是否同步记一笔支出账单（计入收支）
  @State remindChallenge: boolean = true; // 是否在提醒中心按每期（每天/每周）提醒
  onStart: (template: ChallengeTemplate, billOnDeposit: boolean, remindChallenge: boolean) => void = () => {};
  onCancel?: () => void;

  // 当前选中的挑战模板（用于每期提醒开关的文案）
  private selectedTemplate(): ChallengeTemplate {
    for (const tpl of CHALLENGE_TEMPLATES) {
      if (tpl.id === this.selectedId) {
        return tpl;
      }
    }
    return CHALLENGE_TEMPLATES[0];
  }

  build() {
    Column() {
      Row() {
        HandIcon({ name: 'target', iconSize: 20 })
        Text('发起存钱挑战')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 6 })
      }
      .alignItems(VerticalAlign.Center)
      .alignSelf(ItemAlign.Start)
      .margin({ bottom: 4 })

      Text('阶梯式攒钱，每期比上一期多存一点，不知不觉攒下一大笔')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .alignSelf(ItemAlign.Start)
        .margin({ bottom: 14 })

      ForEach(CHALLENGE_TEMPLATES, (tpl: ChallengeTemplate) => {
        Column() {
          Row() {
            Text(tpl.emoji)
              .fontSize(26)
            Column() {
              Text(tpl.name)
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
              Text(tpl.desc)
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            .margin({ left: 12 })
          }
          .width('100%')

          Row() {
            Text(`共 ${tpl.periods} 期`)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
            Blank()
            Text(`累计 ¥${tpl.totalAmount.toLocaleString()}`)
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.income_gold'))
          }
          .width('100%')
          .margin({ top: 10 })
        }
        .width('100%')
        .padding(14)
        .borderRadius(16)
        .backgroundColor($r('app.color.card_bg'))
        .border({
          width: this.selectedId === tpl.id ? 1.5 : 1,
          color: this.selectedId === tpl.id ? this.brandMain : $r('app.color.border_color')
        })
        .margin({ bottom: 12 })
        .onClick(() => {
          animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
            this.selectedId = tpl.id;
          });
        })
      }, (tpl: ChallengeTemplate) => tpl.id + (this.selectedId === tpl.id ? '_1' : '_0'))

      // 存入是否计入收支账单
      Row() {
        Column() {
          Text('存入计入收支和账单')
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
          Text('开启后每笔存入自动记一笔「存钱」支出账单')
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.billOnDeposit })
          .onChange((isOn: boolean) => {
            this.billOnDeposit = isOn;
          })
      }
      .width('100%')
      .margin({ bottom: 14 })

      // 每期存钱提醒：按挑战节奏（每天/每周）在提醒中心提醒
      Row() {
        Column() {
          Text('每期存钱提醒')
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
          Text(this.selectedTemplate().periodDays === 1 ?
            '每天在提醒中心提醒当日应存金额' : '每周在提醒中心提醒本周应存金额')
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.remindChallenge })
          .onChange((isOn: boolean) => {
            this.remindChallenge = isOn;
          })
      }
      .width('100%')
      .margin({ bottom: 16 })

      Row() {
        Button('取消')
          .backgroundColor('transparent')
          .fontColor($r('app.color.text_secondary'))
          .borderRadius(20)
          .height(40)
          .layoutWeight(1)
          .onClick(() => {
            this.onCancel?.();
          })

        Blank().width(16)

        Button('开始挑战')
          .backgroundColor(this.brandMain)
          .fontColor($r('app.color.text_white'))
          .borderRadius(22)
          .height(44)
          .layoutWeight(1)
          .onClick(() => {
            for (const tpl of CHALLENGE_TEMPLATES) {
              if (tpl.id === this.selectedId) {
                this.onStart(tpl, this.billOnDeposit, this.remindChallenge);
                return;
              }
            }
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

// ========== 愿望清单添加弹窗（30 天冷静期） ==========
@CustomDialog
struct WishAddDialog {
  @StorageProp('brand_main') brandMain: string = '#4E6EF2';
  controller: CustomDialogController = new CustomDialogController({
    builder: () => {}
  });
  @State inputName: string = '';
  @State inputPrice: string = '';
  onConfirm: (name: string, price: number) => void = () => {};
  onCancel?: () => void;

  build() {
    Column() {
      Row() {
        HandIcon({ name: 'star_glow', iconSize: 20 })
        Text('许个愿')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 6 })
      }
      .alignItems(VerticalAlign.Center)
      .alignSelf(ItemAlign.Start)
      .margin({ bottom: 4 })

      Text(`先冷静 ${WISH_COOLING_DAYS} 天，冷静期满后还想买再出手`)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .alignSelf(ItemAlign.Start)
        .margin({ bottom: 14 })

      TextInput({ placeholder: '想要什么（如：新款手机）', text: this.inputName })
        .width('100%')
        .height(44)
        .fontSize(16)
        .borderRadius(12)
        .backgroundColor($r('app.color.card_bg'))
        .borderColor($r('app.color.border_color'))
        .borderWidth(1)
        .padding({ left: 16, right: 16 })
        .onChange((val: string) => { this.inputName = val; })
        .margin({ bottom: 12 })

      TextInput({ placeholder: '价格（元）', text: this.inputPrice })
        .width('100%')
        .height(44)
        .fontSize(16)
        .borderRadius(12)
        .backgroundColor($r('app.color.card_bg'))
        .borderColor($r('app.color.border_color'))
        .borderWidth(1)
        .padding({ left: 16, right: 16 })
        .type(InputType.NUMBER_DECIMAL)
        .onChange((val: string) => { this.inputPrice = val; })
        .margin({ bottom: 20 })

      Row() {
        Button('取消')
          .backgroundColor('transparent')
          .fontColor($r('app.color.text_secondary'))
          .borderRadius(20)
          .height(40)
          .layoutWeight(1)
          .onClick(() => {
            this.onCancel?.();
          })

        Blank().width(16)

        Button('开始冷静期')
          .backgroundColor(this.brandMain)
          .fontColor($r('app.color.text_white'))
          .borderRadius(22)
          .height(44)
          .layoutWeight(1)
          .onClick(() => {
            const name = this.inputName.trim();
            const price = parseFloat(this.inputPrice);
            if (!name) {
              this.getUIContext().getPromptAction().showToast({ message: '请写下想要的宝贝', duration: 1500 });
              return;
            }
            if (isNaN(price) || price <= 0) {
              this.getUIContext().getPromptAction().showToast({ message: '请输入有效的价格', duration: 1500 });
              return;
            }
            this.onConfirm(name, Math.round(price * 100) / 100);
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
// 选项 chip 必须是独立组件：@Prop 选中态才能随父组件 @State 变化实时刷新
// （@Builder 按值传参不会引起内部 UI 刷新，导致点击无高亮）
@ComponentV2
struct ProfileOptionChip {
  @Local brandSignals: BrandSignals = BrandSignals.connect();
  @Computed get brandMain(): string { return this.brandSignals.main; }
  @Param selected: boolean = false;
  @Param label: string = '';
  @Param onTap: () => void = () => {};

  build() {
    Text(this.label)
      .fontSize(13)
      .fontColor(this.selected ? $r('app.color.text_white') : $r('app.color.text_primary'))
      .padding({ left: 14, right: 14, top: 7, bottom: 7 })
      .backgroundColor(this.selected ? this.brandMain : $r('app.color.category_btn_bg'))
      .borderRadius(16)
      .margin({ right: 8, bottom: 8 })
      .onClick(() => { this.onTap(); })
  }
}

@CustomDialog
struct FinanceProfileDialog {
  @StorageProp('brand_main') brandMain: string = '#4E6EF2';
  controller: CustomDialogController = new CustomDialogController({
    builder: () => {}
  });
  @State selIncome: string = '';
  @State selFixed: string = '';
  @State selEmergency: string = '';
  @State selDebt: string = '';
  @State selRisk: string = '';
  @State selInvest: string = '';
  onConfirm: (profile: FinanceProfile) => void = () => {};
  onCancel?: () => void;

  @Builder
  QuestionTitle(text: string) {
    Text(text)
      .fontSize(15)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_primary'))
      .alignSelf(ItemAlign.Start)
      .margin({ bottom: 8 })
  }

  build() {
    Column() {
      Text('财务画像问卷')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .alignSelf(ItemAlign.Start)
        .margin({ bottom: 6 })

      Text('共6题，答案仅保存在本机，用于个性化财务健康度评估')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .alignSelf(ItemAlign.Start)
        .margin({ bottom: 12 })

      Scroll() {
        Column() {
          this.QuestionTitle('1. 你的收入情况？')
          Flex({ wrap: FlexWrap.Wrap }) {
            ProfileOptionChip({
              label: PROFILE_INCOME_OPTIONS[0],
              selected: this.selIncome === '稳定',
              onTap: () => { this.selIncome = '稳定'; }
            })
            ProfileOptionChip({
              label: PROFILE_INCOME_OPTIONS[1],
              selected: this.selIncome === '波动大',
              onTap: () => { this.selIncome = '波动大'; }
            })
          }
          .width('100%')
          .margin({ bottom: 12 })

          this.QuestionTitle('2. 是否有房贷、房租等固定大额支出？')
          Flex({ wrap: FlexWrap.Wrap }) {
            ProfileOptionChip({
              label: PROFILE_FIXED_OPTIONS[0],
              selected: this.selFixed === '有房贷/房租',
              onTap: () => { this.selFixed = '有房贷/房租'; }
            })
            ProfileOptionChip({
              label: PROFILE_FIXED_OPTIONS[1],
              selected: this.selFixed === '无',
              onTap: () => { this.selFixed = '无'; }
            })
          }
          .width('100%')
          .margin({ bottom: 12 })

          this.QuestionTitle('3. 应急资金可支撑多久的生活开支？')
          Flex({ wrap: FlexWrap.Wrap }) {
            ProfileOptionChip({
              label: PROFILE_EMERGENCY_OPTIONS[0],
              selected: this.selEmergency === '充足',
              onTap: () => { this.selEmergency = '充足'; }
            })
            ProfileOptionChip({
              label: PROFILE_EMERGENCY_OPTIONS[1],
              selected: this.selEmergency === '一般',
              onTap: () => { this.selEmergency = '一般'; }
            })
            ProfileOptionChip({
              label: PROFILE_EMERGENCY_OPTIONS[2],
              selected: this.selEmergency === '没有储备',
              onTap: () => { this.selEmergency = '没有储备'; }
            })
          }
          .width('100%')
          .margin({ bottom: 12 })

          this.QuestionTitle('4. 目前的负债情况？')
          Flex({ wrap: FlexWrap.Wrap }) {
            ProfileOptionChip({
              label: PROFILE_DEBT_OPTIONS[0],
              selected: this.selDebt === '无负债',
              onTap: () => { this.selDebt = '无负债'; }
            })
            ProfileOptionChip({
              label: PROFILE_DEBT_OPTIONS[1],
              selected: this.selDebt === '少量分期',
              onTap: () => { this.selDebt = '少量分期'; }
            })
            ProfileOptionChip({
              label: PROFILE_DEBT_OPTIONS[2],
              selected: this.selDebt === '有贷款压力',
              onTap: () => { this.selDebt = '有贷款压力'; }
            })
          }
          .width('100%')
          .margin({ bottom: 12 })

          this.QuestionTitle('5. 你的理财风险偏好？')
          Flex({ wrap: FlexWrap.Wrap }) {
            ProfileOptionChip({
              label: PROFILE_RISK_OPTIONS[0],
              selected: this.selRisk === '保守',
              onTap: () => { this.selRisk = '保守'; }
            })
            ProfileOptionChip({
              label: PROFILE_RISK_OPTIONS[1],
              selected: this.selRisk === '平衡',
              onTap: () => { this.selRisk = '平衡'; }
            })
            ProfileOptionChip({
              label: PROFILE_RISK_OPTIONS[2],
              selected: this.selRisk === '进取',
              onTap: () => { this.selRisk = '进取'; }
            })
          }
          .width('100%')
          .margin({ bottom: 12 })

          this.QuestionTitle('6. 你的理财投资经验？')
          Flex({ wrap: FlexWrap.Wrap }) {
            ProfileOptionChip({
              label: PROFILE_INVEST_OPTIONS[0],
              selected: this.selInvest === '无理财经验',
              onTap: () => { this.selInvest = '无理财经验'; }
            })
            ProfileOptionChip({
              label: PROFILE_INVEST_OPTIONS[1],
              selected: this.selInvest === '低风险为主',
              onTap: () => { this.selInvest = '低风险为主'; }
            })
            ProfileOptionChip({
              label: PROFILE_INVEST_OPTIONS[2],
              selected: this.selInvest === '有权益类投资',
              onTap: () => { this.selInvest = '有权益类投资'; }
            })
          }
          .width('100%')
          .margin({ bottom: 4 })
        }
        .width('100%')
      }
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)
      .width('100%')
      .constraintSize({ maxHeight: 420 })
      .margin({ bottom: 8 })

      Row() {
        Button('取消')
          .backgroundColor('transparent')
          .fontColor($r('app.color.text_secondary'))
          .borderRadius(20)
          .height(40)
          .layoutWeight(1)
          .onClick(() => {
            this.onCancel?.();
          })

        Blank().width(16)

        Button('保存')
          .backgroundColor(this.brandMain)
          .fontColor($r('app.color.text_white'))
          .borderRadius(22)
          .height(44)
          .layoutWeight(1)
          .onClick(() => {
            if (this.selIncome === '' || this.selFixed === '' || this.selEmergency === '' ||
              this.selDebt === '' || this.selRisk === '' || this.selInvest === '') {
              this.getUIContext().getPromptAction().showToast({ message: '请答完全部6题', duration: 1500 });
              return;
            }
            const profile: FinanceProfile = {
              incomeStable: this.selIncome,
              fixedExpense: this.selFixed,
              emergency: this.selEmergency,
              debtStatus: this.selDebt,
              riskPref: this.selRisk,
              investExp: this.selInvest
            };
            this.onConfirm(profile);
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

// ========== 财富页 ==========
@ComponentV2
export struct WealthTab {
  // V2 全局信号（AppStorageV2 桥接层，替代原 @StorageProp）
  @Local brandSignals: BrandSignals = BrandSignals.connect();
  @Computed get brandMain(): string { return this.brandSignals.main; }
  @Computed get brandTint(): string { return this.brandSignals.tint; }
  @Local deviceSignals: DeviceSignals = DeviceSignals.connect();
  // 沉浸式布局：状态栏避让高度（顶部占位条内部消化，背景延伸到状态栏下）
  @Computed get statusBarVp(): number { return this.deviceSignals.statusBarVp; }
  // 底部手势条避让高度：滚动内容尾部留白据此避开悬浮页签栏
  @Computed get navBarVp(): number { return this.deviceSignals.navBarVp; }
  // 总资产变化（记账/资产明细页改动）时触发资金账户刷新
  @Param totalAsset: number = 0;
  // 资金账户在财富页被增删改后，通知首页刷新总资产
  @Param onAssetsChanged: () => void = () => {};
  // 信用账户/存钱目标变更时通知首页（刷新提醒中心角标，不必等打开弹窗）
  @Param onWealthDataChanged: () => void = () => {};
  // 'asset' 资产 | 'saving' 存钱；StorageLink 便于资产明细页跳转时切回资产界面
  @Local wealthSignals: WealthSignals = WealthSignals.connect();
  @Computed get wealthMode(): string { return this.wealthSignals.mode; }
  // 滚动联动顶部玻璃栏：0=顶部（全透明）→ 1=已滚动（毛玻璃+发丝线），主内容区 onDidScroll 驱动
  @Local headerGlass: number = 0;
  // 深浅色判断（玻璃栏配色分支）
  @Local colorModeSignals: ColorModeSignals = ColorModeSignals.connect();
  // 主导航栈（Index 传入）：存钱目标详情经系统路由表压入
  @Param navPathStack: NavPathStack = new NavPathStack();
  // 目标详情页改动存钱数据后置位，回到财富页时自动刷新目标列表
  @Computed get wealthRefreshFlag(): number { return this.wealthSignals.refreshFlag; }
  @Local fundAccounts: FundAccount[] = [];
  @Local creditAccounts: CreditAccount[] = [];
  @Local savingGoals: SavingGoal[] = [];
  // 按压中的胶囊/按钮 key（Q弹缩放反馈）
  @Local pressedChipKey: string = '';
  @Local wishes: WishItem[] = [];
  // 小眼睛：一键隐藏/显示资产金额（与资产明细页风格一致）
  @Local amountVisible: boolean = true;
  // 资产规划数据
  @Local bills: BillItem[] = [];
  @Local monthBudget: number = 0;
  @Local healthResult: HealthResult = { score: 0, grade: '—', items: [], suggestions: [] };
  // 健康度动画：环形进度插值值 / 分数滚动显示值 / 评级徽章缩放
  @Local healthRingValue: number = 0;
  @Local healthScoreDisplay: number = 0;
  @Local healthGradeScale: number = 1;
  private healthCountTimer: number = -1;
  @Local trendPoints: NetAssetPoint[] = [];
  @Local pieEntries: FundAccount[] = [];
  // 账本分类分析：0 = 全部账本
  @Local ledgers: LedgerItem[] = [];
  @Local selectedLedgerId: number = 0;
  // 用户财务画像（问卷）
  @Local profile: FinanceProfile = {
    incomeStable: '',
    fixedExpense: '',
    emergency: '',
    debtStatus: '',
    riskPref: '',
    investExp: ''
  };
  private budgetMap: Record<string, number> = {};
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;

  aboutToAppear(): void {
    this.loadAmountVisible();
    this.loadAllData();
  }

  @Monitor('totalAsset')
  onExternalRefresh(monitor: IMonitor): void {
    this.loadFundAccounts();
    this.loadBills().then((): void => {
      this.computePlannerData();
    });
  }

  // 目标详情页（存入/日记/编辑）返回后刷新存钱目标列表
  @Monitor('wealthRefreshFlag')
  onGoalDetailChanged(monitor: IMonitor): void {
    this.loadSavingGoals();
    this.onWealthDataChanged();
  }

  // 进入存钱目标详情页：旅程/存入/日记都在详情页完成
  openGoalDetail(goal: SavingGoal): void {
    this.navPathStack.pushPathByName('SavingGoalDetailPage', { id: goal.id } as GoalDetailParams);
  }

  // 加载全部数据后统一计算规划指标
  async loadAllData(): Promise<void> {
    await this.loadFundAccounts();
    await this.loadCreditAccounts();
    await this.loadSavingGoals();
    await this.loadWishList();
    await this.loadBills();
    await this.loadBudget();
    await this.loadLedgers();
    await this.loadProfile();
    this.computePlannerData();
  }

  // ---------- 愿望清单（30 天冷静期） ----------
  async loadWishList(): Promise<void> {
    this.wishes = await loadWishes(this.context);
  }

  openWishAddDialog(): void {
    const controller = new CustomDialogController({
      builder: WishAddDialog({
        onConfirm: (name: string, price: number) => {
          const item: WishItem = {
            id: Date.now(),
            name: name,
            price: price,
            createdAt: Date.now(),
            status: 'cooling'
          };
          animateTo({ curve: AnimationConfig.SPRING }, () => {
            this.wishes = [item, ...this.wishes];
          });
          saveWishes(this.context, this.wishes);
          controller.close();
          this.getUIContext().getPromptAction().showToast({
            message: `已进入 ${WISH_COOLING_DAYS} 天冷静期，冲动是魔鬼~`,
            duration: 2200
          });
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

  // 冷静期满：还想买，保留在清单并提示去攒钱
  keepWish(index: number): void {
    const item = this.wishes[index];
    this.wishes[index] = {
      id: item.id,
      name: item.name,
      price: item.price,
      createdAt: item.createdAt,
      status: 'want'
    };
    this.wishes = [...this.wishes];
    saveWishes(this.context, this.wishes);
    this.getUIContext().getPromptAction().showToast({ message: '那就为它好好攒钱吧！', duration: 1800 });
  }

  // 放下愿望：从清单移除；convert 为 true 时同时转为同名存钱目标
  dropWish(index: number, convert: boolean): void {
    const item = this.wishes[index];
    if (convert) {
      const goal: SavingGoal = {
        id: Date.now(),
        name: `${item.name}基金`,
        target: item.price,
        saved: 0,
        deadline: 0,
        records: []
      };
      animateTo({ curve: AnimationConfig.SPRING }, () => {
        this.savingGoals = [goal, ...this.savingGoals];
      });
      this.saveSavingGoals();
      this.getUIContext().getPromptAction().showToast({ message: '已转为存钱目标，把想买变成攒到！', duration: 2200 });
    } else {
      this.getUIContext().getPromptAction().showToast({ message: '放下也是省钱，为你点赞！', duration: 1800 });
    }
    animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
      this.wishes = this.wishes.filter((w: WishItem): boolean => w.id !== item.id);
    });
    saveWishes(this.context, this.wishes);
  }

  // 点击冷静期满的愿望：做决定
  onWishDecide(index: number): void {
    const item = this.wishes[index];
    this.getUIContext().getPromptAction().showDialog({
      title: '冷静期已满',
      message: `还想买「${item.name}」（¥${item.price.toFixed(2)}）吗？`,
      buttons: [
        { text: '不买了', color: $r('app.color.text_secondary') },
        { text: '转存钱目标', color: $r('app.color.income_gold') },
        { text: '还想买', color: this.brandMain }
      ]
    }).then((result) => {
      if (result.index === 0) {
        this.dropWish(index, false);
      } else if (result.index === 1) {
        this.dropWish(index, true);
      } else if (result.index === 2) {
        this.keepWish(index);
      }
    }).catch(() => {});
  }

  // ---------- 52周 / 30天存钱挑战 ----------
  openChallengeDialog(): void {
    const controller = new CustomDialogController({
      builder: ChallengeStartDialog({
        onStart: (tpl: ChallengeTemplate, billOnDeposit: boolean, remindChallenge: boolean) => {
          const goal: SavingGoal = {
            id: Date.now(),
            name: tpl.name,
            target: tpl.totalAmount,
            saved: 0,
            deadline: 0,
            records: [],
            challengeType: tpl.id,
            challengeStart: Date.now(),
            billOnDeposit: billOnDeposit,
            remindChallenge: remindChallenge
          };
          animateTo({ curve: AnimationConfig.SPRING }, () => {
            this.savingGoals = [goal, ...this.savingGoals];
          });
          this.saveSavingGoals();
          controller.close();
          this.getUIContext().getPromptAction().showToast({
            message: billOnDeposit ? `挑战开始！每笔存入将同步记账` : `挑战开始！${tpl.desc}`,
            duration: 2500
          });
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

  // ---------- 账单与预算（资产规划用） ----------
  async loadBills(): Promise<void> {
    try {
      const prefs = await dataPreferences.getPreferences(this.context, 'bill_data');
      const data = await prefs.get('bills_key', '[]') as string;
      this.bills = JSON.parse(data) as BillItem[];
    } catch (e) {
      console.error('加载账单失败', e);
      this.bills = [];
    }
  }

  async loadBudget(): Promise<void> {
    try {
      const prefs = await dataPreferences.getPreferences(this.context, 'bill_data');
      const raw = await prefs.get('budget', '') as string;
      this.budgetMap = raw.length > 0 ? JSON.parse(raw) as Record<string, number> : {};
    } catch (e) {
      console.error('加载预算失败', e);
      this.budgetMap = {};
    }
  }

  // 按所选账本取当月预算：全部 = 各账本当月预算之和
  getBudgetForSelection(): number {
    const now = new Date();
    const ym = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
    if (this.selectedLedgerId === 0) {
      let total = 0;
      const keys = Object.keys(this.budgetMap);
      for (const k of keys) {
        if (k.endsWith(':' + ym)) {
          const v = this.budgetMap[k];
          if (v !== undefined && v > 0) {
            total += v;
          }
        }
      }
      return total;
    }
    let v = this.budgetMap[`${this.selectedLedgerId}:${ym}`];
    if (v === undefined && this.selectedLedgerId === DEFAULT_LEDGER_ID) {
      v = this.budgetMap[ym];
    }
    return v !== undefined && v > 0 ? v : 0;
  }

  // “全部”视图下，仅当所有账本都已设置当月预算时才评估预算执行
  allLedgersHaveBudget(): boolean {
    const now = new Date();
    const ym = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
    if (this.ledgers.length === 0) {
      const defV = this.budgetMap[`${DEFAULT_LEDGER_ID}:${ym}`];
      const legacyV = this.budgetMap[ym];
      return (defV !== undefined && defV > 0) || (legacyV !== undefined && legacyV > 0);
    }
    for (const ledger of this.ledgers) {
      let v = this.budgetMap[`${ledger.id}:${ym}`];
      if (v === undefined && ledger.id === DEFAULT_LEDGER_ID) {
        v = this.budgetMap[ym];
      }
      if (v === undefined || v <= 0) {
        return false;
      }
    }
    return true;
  }

  async loadLedgers(): Promise<void> {
    try {
      const prefs = await dataPreferences.getPreferences(this.context, 'bill_data');
      const data = await prefs.get('ledgers_key', '[]') as string;
      this.ledgers = JSON.parse(data) as LedgerItem[];
    } catch (e) {
      console.error('加载账本列表失败', e);
      this.ledgers = [];
    }
  }

  async loadProfile(): Promise<void> {
    try {
      const prefs = await dataPreferences.getPreferences(this.context, 'bill_data');
      const raw = await prefs.get('finance_profile', '') as string;
      if (raw.length > 0) {
        const saved = JSON.parse(raw) as FinanceProfile;
        // 兼容旧版本数据：缺失的新字段回填为空，引导用户补充作答
        this.profile = {
          incomeStable: saved.incomeStable ?? '',
          fixedExpense: saved.fixedExpense ?? '',
          emergency: saved.emergency ?? '',
          debtStatus: saved.debtStatus ?? '',
          riskPref: saved.riskPref ?? '',
          investExp: saved.investExp ?? ''
        };
      }
    } catch (e) {
      console.error('加载财务画像失败', e);
    }
  }

  async saveProfile(p: FinanceProfile): Promise<void> {
    try {
      const prefs = await dataPreferences.getPreferences(this.context, 'bill_data');
      await prefs.put('finance_profile', JSON.stringify(p));
      await prefs.flush();
    } catch (e) {
      console.error('保存财务画像失败', e);
    }
    this.computePlannerData();
  }

  hasProfile(): boolean {
    return this.profile.incomeStable !== '' && this.profile.fixedExpense !== '' &&
      this.profile.emergency !== '' && this.profile.debtStatus !== '' &&
      this.profile.riskPref !== '' && this.profile.investExp !== '';
  }

  // ---------- 健康度：问卷 / 账本切换 ----------
  openProfileDialog(): void {
    const controller = new CustomDialogController({
      builder: FinanceProfileDialog({
        selIncome: this.profile.incomeStable,
        selFixed: this.profile.fixedExpense,
        selEmergency: this.profile.emergency,
        selDebt: this.profile.debtStatus,
        selRisk: this.profile.riskPref,
        selInvest: this.profile.investExp,
        onConfirm: (p: FinanceProfile) => {
          this.profile = p;
          this.saveProfile(p);
          this.getUIContext().getPromptAction().showToast({ message: '画像已更新，健康度已重新评估', duration: 1500 });
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

  selectLedger(id: number): void {
    if (id === this.selectedLedgerId) {
      return;
    }
    animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
      this.selectedLedgerId = id;
    });
    this.computePlannerData();
  }

  getLedgerName(id: number): string {
    if (id === 0) {
      return '全部';
    }
    const found = this.ledgers.find((item: LedgerItem): boolean => item.id === id);
    return found !== undefined ? found.name : '账本';
  }

  computePlannerData(): void {
    this.monthBudget = this.getBudgetForSelection();
    this.healthResult = this.getHealthResult();
    this.trendPoints = this.getNetAssetTrend();
    this.pieEntries = this.getPieEntries();
    this.playHealthReveal();
  }

  // 健康度重算后的揭示动画：环形进度扫入 + 分数滚动上升 + 评级徽章回弹
  playHealthReveal(): void {
    const target = this.healthResult.score;
    const from = this.healthScoreDisplay;
    if (this.healthCountTimer >= 0) {
      clearInterval(this.healthCountTimer);
      this.healthCountTimer = -1;
    }
    // 环形进度：EaseOut 扫入，接近秒级更有"体检报告"感
    animateTo({ duration: 850, curve: Curve.EaseOut }, () => {
      this.healthRingValue = target;
    });
    // 分数滚动：三阶缓出插值，与环形进度同步
    const start = Date.now();
    this.healthCountTimer = setInterval(() => {
      const t = Math.min(1, (Date.now() - start) / 850);
      const eased = 1 - Math.pow(1 - t, 3);
      this.healthScoreDisplay = Math.round(from + (target - from) * eased);
      if (t >= 1) {
        clearInterval(this.healthCountTimer);
        this.healthCountTimer = -1;
      }
    }, 34);
    // 评级徽章弹跳
    animateTo({ duration: 200, curve: AnimationConfig.SPRING }, () => {
      this.healthGradeScale = 1.25;
    });
    setTimeout(() => {
      animateTo({ duration: 320, curve: AnimationConfig.SPRING }, () => {
        this.healthGradeScale = 1;
      });
    }, 180);
  }

  aboutToDisappear(): void {
    if (this.healthCountTimer >= 0) {
      clearInterval(this.healthCountTimer);
      this.healthCountTimer = -1;
    }
  }

  // ---------- 金额显示状态持久化 ----------
  async loadAmountVisible(): Promise<void> {
    try {
      const prefs = await dataPreferences.getPreferences(this.context, 'bill_data');
      this.amountVisible = (await prefs.get('wealth_amount_visible', true)) as boolean;
    } catch (e) {
      console.error('加载金额显示状态失败', e);
    }
  }

  async saveAmountVisible(visible: boolean): Promise<void> {
    try {
      const prefs = await dataPreferences.getPreferences(this.context, 'bill_data');
      await prefs.put('wealth_amount_visible', visible);
      await prefs.flush();
    } catch (e) {
      console.error('保存金额显示状态失败', e);
    }
  }

  // ---------- 数据读写 ----------
  async loadFundAccounts(): Promise<void> {
    try {
      const prefs = await dataPreferences.getPreferences(this.context, 'bill_data');
      const data = await prefs.get('asset_categories', '[]') as string;
      this.fundAccounts = JSON.parse(data) as FundAccount[];
    } catch (e) {
      console.error('加载资金账户失败', e);
      this.fundAccounts = [];
    }
  }

  async loadCreditAccounts(): Promise<void> {
    try {
      const prefs = await dataPreferences.getPreferences(this.context, 'bill_data');
      const data = await prefs.get('credit_accounts', '[]') as string;
      const parsed = JSON.parse(data) as CreditAccount[];
      // 旧数据无 dueDate 字段，加载时补 0
      this.creditAccounts = parsed.map((item: CreditAccount): CreditAccount => {
        return { id: item.id, name: item.name, debt: item.debt, dueDate: item.dueDate ? item.dueDate : 0 };
      });
    } catch (e) {
      console.error('加载信用账户失败', e);
      this.creditAccounts = [];
    }
  }

  async saveFundAccounts(): Promise<void> {
    try {
      const prefs = await dataPreferences.getPreferences(this.context, 'bill_data');
      await prefs.put('asset_categories', JSON.stringify(this.fundAccounts));
      await prefs.flush();
      this.computePlannerData();
      this.onAssetsChanged();
    } catch (e) {
      console.error('保存资金账户失败', e);
    }
  }

  async saveCreditAccounts(): Promise<void> {
    try {
      const prefs = await dataPreferences.getPreferences(this.context, 'bill_data');
      await prefs.put('credit_accounts', JSON.stringify(this.creditAccounts));
      await prefs.flush();
      this.computePlannerData();
      this.onWealthDataChanged();
    } catch (e) {
      console.error('保存信用账户失败', e);
    }
  }

  async loadSavingGoals(): Promise<void> {
    try {
      const prefs = await dataPreferences.getPreferences(this.context, 'bill_data');
      const data = await prefs.get('saving_goals', '[]') as string;
      const parsed = JSON.parse(data) as SavingGoal[];
      // 旧数据无 deadline / records 字段，加载时补默认值
      this.savingGoals = parsed.map((item: SavingGoal): SavingGoal => {
        return {
          id: item.id,
          name: item.name,
          target: item.target,
          saved: item.saved,
          deadline: item.deadline ? item.deadline : 0,
          records: item.records ? item.records : [],
          challengeType: item.challengeType ? item.challengeType : undefined,
          challengeStart: item.challengeStart ? item.challengeStart : undefined,
          billOnDeposit: item.billOnDeposit ? item.billOnDeposit : undefined,
          remindChallenge: item.remindChallenge ? item.remindChallenge : undefined
        };
      });
    } catch (e) {
      console.error('加载存钱目标失败');
      this.savingGoals = [];
    }
  }

  async saveSavingGoals(): Promise<void> {
    try {
      const prefs = await dataPreferences.getPreferences(this.context, 'bill_data');
      await prefs.put('saving_goals', JSON.stringify(this.savingGoals));
      await prefs.flush();
      this.onWealthDataChanged();
    } catch (e) {
      console.error('保存存钱目标失败', e);
    }
  }

  // ---------- 汇总计算 ----------
  getFundTotal(): number {
    let total = 0;
    for (const item of this.fundAccounts) {
      total += item.amount;
    }
    return total;
  }

  getTotalDebt(): number {
    let total = 0;
    for (const item of this.creditAccounts) {
      total += item.debt;
    }
    return total;
  }

  getNetAsset(): number {
    return this.getFundTotal() - this.getTotalDebt();
  }

  // ---------- 资产规划：数据计算 ----------
  // 某月收支（按所选账本过滤，0 = 全部账本）
  getMonthFlows(year: number, month: number): MonthFlows {
    let income = 0;
    let expense = 0;
    for (const b of this.bills) {
      if (this.selectedLedgerId !== 0 && (b.ledgerId ?? DEFAULT_LEDGER_ID) !== this.selectedLedgerId) {
        continue;
      }
      const d = new Date(b.date);
      if (d.getFullYear() === year && d.getMonth() + 1 === month) {
        if (b.type === '收入') {
          income += b.amount;
        } else if (b.type === '支出') {
          expense += b.amount;
        }
      }
    }
    return { income: income, expense: expense };
  }

  // 近 n 个月（含本月）平均收支
  getRecentAvgFlows(n: number): MonthFlows {
    let income = 0;
    let expense = 0;
    const now = new Date();
    for (let i = 0; i < n; i++) {
      const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
      const f = this.getMonthFlows(d.getFullYear(), d.getMonth() + 1);
      income += f.income;
      expense += f.expense;
    }
    return { income: income / n, expense: expense / n };
  }

  // 近6个月月末净资产：以当前净资产为基准，按收支回推估算（假设收支均经由资产账户）
  getNetAssetTrend(): NetAssetPoint[] {
    const points: NetAssetPoint[] = [];
    const currentNet = this.getNetAsset();
    const now = new Date();
    let incomeAfter = 0;
    let expenseAfter = 0;
    const values: number[] = [];
    const labels: string[] = [];
    for (let i = 0; i < 6; i++) {
      const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
      values.unshift(currentNet - incomeAfter + expenseAfter);
      labels.unshift(`${d.getMonth() + 1}月`);
      const f = this.getMonthFlows(d.getFullYear(), d.getMonth() + 1);
      incomeAfter += f.income;
      expenseAfter += f.expense;
    }
    for (let i = 0; i < 6; i++) {
      points.push({ label: labels[i], value: values[i] });
    }
    return points;
  }

  getTrendBarHeight(value: number): number {
    let maxAbs = 0;
    for (const p of this.trendPoints) {
      maxAbs = Math.max(maxAbs, Math.abs(p.value));
    }
    if (maxAbs <= 0) {
      return 4;
    }
    return Math.max(4, Math.abs(value) / maxAbs * 64);
  }

  // 资产分布：正余额账户，最多取前9个（DataPanel 上限）
  getPieEntries(): FundAccount[] {
    return this.fundAccounts
      .filter((item: FundAccount): boolean => item.amount > 0)
      .sort((a: FundAccount, b: FundAccount): number => b.amount - a.amount)
      .slice(0, 9);
  }

  getPieMax(): number {
    let total = 0;
    for (const item of this.pieEntries) {
      total += item.amount;
    }
    return total;
  }

  getPieValues(): number[] {
    return this.pieEntries.map((item: FundAccount): number => item.amount);
  }

  getPieColors(): ResourceColor[] {
    return this.pieEntries.map((item: FundAccount, index: number): ResourceColor => this.getPaletteColor(index));
  }

  getPiePercent(item: FundAccount): string {
    const max = this.getPieMax();
    if (max <= 0) {
      return '0';
    }
    return (item.amount / max * 100).toFixed(0);
  }

  // 财务健康度：负债率 / 储蓄率 / 预算执行 / 应急储备 各25分
  getHealthResult(): HealthResult {
    const fundTotal = this.getFundTotal();
    const totalDebt = this.getTotalDebt();
    const avg3 = this.getRecentAvgFlows(3);
    const now = new Date();
    const curFlows = this.getMonthFlows(now.getFullYear(), now.getMonth() + 1);
    const items: HealthItem[] = [];
    const suggestions: string[] = [];

    // 1) 负债率
    let debtScore = 25;
    let debtText = '无负债';
    if (totalDebt > 0) {
      const ratio = fundTotal > 0 ? totalDebt / fundTotal * 100 : 200;
      debtText = ratio.toFixed(0) + '%';
      if (ratio <= 20) {
        debtScore = 20;
      } else if (ratio <= 50) {
        debtScore = 14;
      } else if (ratio <= 100) {
        debtScore = 8;
      } else {
        debtScore = 0;
      }
      if (debtScore <= 10) {
        suggestions.push('负债偏高，建议优先偿还高息欠款');
      }
    }
    items.push({ name: '负债率', valueText: debtText, score: debtScore });

    // 2) 储蓄率（近3个月；有房贷/房租等固定支出时达标线适当放宽）
    let saveScore = 12;
    let saveText = '暂无数据';
    const hasFixedCost = this.profile.fixedExpense === '有房贷/房租';
    if (avg3.income > 0) {
      const rate = (avg3.income - avg3.expense) / avg3.income * 100;
      saveText = rate.toFixed(0) + '%';
      if (hasFixedCost) {
        if (rate >= 20) {
          saveScore = 25;
        } else if (rate >= 10) {
          saveScore = 20;
        } else if (rate >= 5) {
          saveScore = 15;
        } else if (rate >= 0) {
          saveScore = 8;
        } else {
          saveScore = 0;
        }
      } else {
        if (rate >= 30) {
          saveScore = 25;
        } else if (rate >= 20) {
          saveScore = 20;
        } else if (rate >= 10) {
          saveScore = 15;
        } else if (rate >= 0) {
          saveScore = 8;
        } else {
          saveScore = 0;
        }
      }
    }
    if (saveScore <= 8) {
      suggestions.push('近3个月结余不足，建议先存后花');
    }
    items.push({ name: '储蓄率(近3月)', valueText: saveText, score: saveScore });

    // 3) 预算执行（本月）
    // “全部”视图：只要有账本未设当月预算，汇总口径就不完整，不予评估
    let budgetScore = 12;
    let budgetText = '未设预算';
    const canEvalBudget = this.monthBudget > 0 &&
      (this.selectedLedgerId !== 0 || this.allLedgersHaveBudget());
    if (canEvalBudget) {
      const useRate = curFlows.expense / this.monthBudget * 100;
      budgetText = useRate.toFixed(0) + '%';
      if (useRate <= 80) {
        budgetScore = 25;
      } else if (useRate <= 100) {
        budgetScore = 18;
      } else if (useRate <= 120) {
        budgetScore = 8;
      } else {
        budgetScore = 0;
      }
      if (budgetScore <= 8) {
        suggestions.push('本月支出已超预算，注意控制非必要开支');
      }
    } else if (this.monthBudget > 0) {
      budgetText = '部分账本未设预算';
      suggestions.push('部分账本未设置当月预算，补齐后"全部"视图才会评估预算执行');
    } else {
      suggestions.push('尚未设置月度预算，建议为每月支出设上限');
    }
    items.push({ name: '预算执行(本月)', valueText: budgetText, score: budgetScore });

    // 4) 应急储备（当前资产可支撑月数；收入波动大时达标线提高）
    let reserveScore = 0;
    let reserveText = '暂无数据';
    const volatileIncome = this.profile.incomeStable === '波动大';
    if (avg3.expense > 0) {
      const months = fundTotal / avg3.expense;
      reserveText = months.toFixed(1) + '个月';
      if (volatileIncome) {
        if (months >= 12) {
          reserveScore = 25;
        } else if (months >= 6) {
          reserveScore = 20;
        } else if (months >= 3) {
          reserveScore = 12;
        } else if (fundTotal > 0) {
          reserveScore = 6;
        }
      } else {
        if (months >= 6) {
          reserveScore = 25;
        } else if (months >= 3) {
          reserveScore = 20;
        } else if (months >= 1) {
          reserveScore = 12;
        } else if (fundTotal > 0) {
          reserveScore = 6;
        }
      }
    } else if (fundTotal > 0) {
      reserveScore = 25;
      reserveText = '充足';
    }
    if (reserveScore <= 6) {
      suggestions.push('应急储备不足，建议留足3-6个月开支');
    }
    items.push({ name: '应急储备', valueText: reserveText, score: reserveScore });

    // 5) 画像驱动的个性化建议
    if (!this.hasProfile()) {
      suggestions.push('尚未填写财务画像问卷，完善后评估更精准');
    } else {
      if (volatileIncome && reserveScore < 20) {
        suggestions.push('收入波动较大，建议储备6个月以上应急资金');
      }
      if (hasFixedCost && saveScore <= 8) {
        suggestions.push('有房贷/房租等固定支出，优先保障每月结余为正');
      }
      if (this.profile.riskPref === '保守' && fundTotal > 0 && saveScore >= 15) {
        suggestions.push('偏好稳健，可将部分结余放入低风险理财');
      }
      if (this.profile.riskPref === '进取' && saveScore >= 20) {
        suggestions.push('结余状况良好，可考虑定期投资让资产增值');
      }
      if (this.profile.emergency === '没有储备' && reserveScore < 20) {
        suggestions.push('尚无应急储备，建议每月固定存一笔备用金');
      }
      if (this.profile.debtStatus === '有贷款压力') {
        suggestions.push('负债压力较大，优先偿还高息贷款并控制新增负债');
      }
      if (this.profile.investExp === '无理财经验' && saveScore >= 15) {
        suggestions.push('可从存款/货币基金等低风险产品起步培养理财习惯');
      }
    }

    const score = debtScore + saveScore + budgetScore + reserveScore;
    let grade = '需改善';
    if (score >= 85) {
      grade = '优秀';
    } else if (score >= 70) {
      grade = '良好';
    } else if (score >= 50) {
      grade = '一般';
    }
    return { score: score, grade: grade, items: items, suggestions: suggestions };
  }

  getGradeColor(grade: string): ResourceColor {
    if (grade === '优秀') {
      return $r('app.color.success_green');
    }
    if (grade === '良好') {
      return $r('app.color.income_gold');
    }
    if (grade === '一般') {
      return $r('app.color.budget_orange');
    }
    return $r('app.color.expense_red');
  }

  getItemColor(score: number): ResourceColor {
    if (score >= 20) {
      return $r('app.color.success_green');
    }
    if (score >= 10) {
      return $r('app.color.budget_orange');
    }
    return $r('app.color.expense_red');
  }

  // ---------- 存钱目标达成预测 ----------
  // 设了截止日：按剩余天数/差额提示；未设：按近3个月平均结余估算达成时间
  getGoalPrediction(goal: SavingGoal): string {
    if (goal.saved >= goal.target) {
      return '已达成目标';
    }
    const remain = goal.target - goal.saved;
    if (goal.deadline > 0) {
      const days = this.getDueDays(goal.deadline);
      const d = new Date(goal.deadline);
      const dateStr = `${d.getMonth() + 1}月${d.getDate()}日`;
      if (days < 0) {
        return `已于 ${dateStr} 过截止日，还差 ¥${remain.toFixed(2)}`;
      }
      if (days === 0) {
        return `今天截止，还差 ¥${remain.toFixed(2)}`;
      }
      return `距截止日 ${dateStr} 还有${days}天，还差 ¥${remain.toFixed(2)}`;
    }
    const avg3 = this.getRecentAvgFlows(3);
    const balance = avg3.income - avg3.expense;
    if (balance <= 0) {
      return '近3个月无结余，建议控制支出后再攒';
    }
    const months = Math.ceil((goal.target - goal.saved) / balance);
    if (months <= 1) {
      return '按近3月平均结余，预计下月即可达成';
    }
    const now = new Date();
    const targetDate = new Date(now.getFullYear(), now.getMonth() + months, 1);
    return `按近3月平均结余，预计 ${targetDate.getFullYear()}年${targetDate.getMonth() + 1}月 达成`;
  }

  getGoalPredictionColor(goal: SavingGoal): ResourceColor {
    if (goal.saved >= goal.target) {
      return $r('app.color.success_green');
    }
    if (goal.deadline > 0) {
      const days = this.getDueDays(goal.deadline);
      if (days < 0) {
        return $r('app.color.expense_red');
      }
      if (days <= 7) {
        return $r('app.color.budget_orange');
      }
      return $r('app.color.text_secondary');
    }
    const avg3 = this.getRecentAvgFlows(3);
    if (avg3.income - avg3.expense <= 0) {
      return $r('app.color.budget_orange');
    }
    return $r('app.color.text_secondary');
  }

  getGoalPercent(saved: number, target: number): number {
    if (target <= 0) return 0;
    const percent = Math.floor(saved / target * 100);
    if (percent < 0) return 0;
    if (percent > 100) return 100;
    return percent;
  }

  // 金额缩写：过万显示 xx万，过亿显示 xx亿
  trimAmount(value: number): string {
    return parseFloat(value.toFixed(2)).toString();
  }

  formatAmount(value: number): string {
    const abs = Math.abs(value);
    if (abs >= 100000000) {
      return this.trimAmount(value / 100000000) + '亿';
    }
    if (abs >= 10000) {
      return this.trimAmount(value / 10000) + '万';
    }
    return value.toFixed(2);
  }

  getAccountInitial(name: string): string {
    return name.length > 0 ? name.charAt(0) : '账';
  }

  // 金额显示：隐藏时统一显示 ¥****
  amountText(value: number): string {
    return this.amountVisible ? '¥' + value.toFixed(2) : '¥****';
  }

  getPaletteColor(index: number): string {
    return ASSET_PALETTE[index % ASSET_PALETTE.length];
  }

  // 距还款日的天数：正数未到期，0 今天，负数已逾期
  getDueDays(ts: number): number {
    const now = new Date();
    const nowStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
    const d = new Date(ts);
    const dueStart = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
    return Math.round((dueStart - nowStart) / 86400000);
  }

  getDueDateText(ts: number): string {
    const days = this.getDueDays(ts);
    const d = new Date(ts);
    const dateStr = `${d.getMonth() + 1}月${d.getDate()}日`;
    if (days === 0) {
      return `今天还款日`;
    }
    if (days < 0) {
      return `还款日 ${dateStr} · 已逾期${-days}天`;
    }
    return `还款日 ${dateStr} · 还有${days}天`;
  }

  // ---------- 模式切换 ----------
  switchWealthMode(mode: string): void {
    if (mode === this.wealthMode) return;
    // 滑块用 Q 弹弹簧曲线；内容横滑过渡在各自 transition 上用柔和弹簧
    animateTo({ curve: AnimationConfig.SPRING }, () => {
      this.wealthSignals.mode = mode;
    });
  }

  // ---------- 资金账户：增删改 ----------
  openFundAddDialog(): void {
    const controller = new CustomDialogController({
      builder: FundAccountDialog({
        title: '添加资金账户',
        confirmText: '添加',
        onConfirm: (name: string, amount: number) => {
          if (this.fundAccounts.some(item => item.name === name)) {
            this.getUIContext().getPromptAction().showToast({ message: '已存在同名账户', duration: 1500 });
            return;
          }
          const account: FundAccount = { name: name, amount: amount };
          animateTo({ curve: AnimationConfig.SPRING }, () => {
            this.fundAccounts = [...this.fundAccounts, account];
          });
          this.saveFundAccounts();
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

  openFundEditDialog(index: number): void {
    const item = this.fundAccounts[index];
    const controller = new CustomDialogController({
      builder: FundAccountDialog({
        title: '编辑资金账户',
        confirmText: '保存',
        inputName: item.name,
        inputAmount: item.amount.toString(),
        onConfirm: (name: string, amount: number) => {
          if (name !== item.name && this.fundAccounts.some(i => i.name === name)) {
            this.getUIContext().getPromptAction().showToast({ message: '已存在同名账户', duration: 1500 });
            return;
          }
          animateTo({ curve: AnimationConfig.SPRING }, () => {
            this.fundAccounts[index] = { name: name, amount: amount };
            this.fundAccounts = [...this.fundAccounts];
          });
          this.saveFundAccounts();
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

  deleteFundAccount(index: number): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '确认删除',
      message: `删除资金账户「${this.fundAccounts[index].name}」？已记录的账单不受影响。`,
      buttons: [
        { text: '取消', color: $r('app.color.text_secondary') },
        { text: '删除', color: $r('app.color.expense_red') }
      ]
    }).then((result) => {
      if (result.index === 1) {
        animateTo({ curve: AnimationConfig.SPRING }, () => {
          this.fundAccounts.splice(index, 1);
          this.fundAccounts = [...this.fundAccounts];
        });
        this.saveFundAccounts();
      }
    });
  }

  // ---------- 信用账户：增删改 ----------
  openCreditAddDialog(): void {
    const controller = new CustomDialogController({
      builder: CreditAccountDialog({
        title: '添加信用账户',
        confirmText: '添加',
        onConfirm: (name: string, debt: number, dueDate: number) => {
          if (this.creditAccounts.some(item => item.name === name)) {
            this.getUIContext().getPromptAction().showToast({ message: '已存在同名账户', duration: 1500 });
            return;
          }
          const account: CreditAccount = { id: Date.now(), name: name, debt: debt, dueDate: dueDate };
          animateTo({ curve: AnimationConfig.SPRING }, () => {
            this.creditAccounts = [account, ...this.creditAccounts];
          });
          this.saveCreditAccounts();
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

  openCreditEditDialog(index: number): void {
    const item = this.creditAccounts[index];
    const controller = new CustomDialogController({
      builder: CreditAccountDialog({
        title: '编辑信用账户',
        confirmText: '保存',
        inputName: item.name,
        inputDebt: item.debt.toString(),
        dueDate: item.dueDate,
        onConfirm: (name: string, debt: number, dueDate: number) => {
          if (name !== item.name && this.creditAccounts.some(i => i.name === name)) {
            this.getUIContext().getPromptAction().showToast({ message: '已存在同名账户', duration: 1500 });
            return;
          }
          animateTo({ curve: AnimationConfig.SPRING }, () => {
            this.creditAccounts[index] = { id: item.id, name: name, debt: debt, dueDate: dueDate };
            this.creditAccounts = [...this.creditAccounts];
          });
          this.saveCreditAccounts();
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

  deleteCreditAccount(index: number): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '确认删除',
      message: `删除信用账户「${this.creditAccounts[index].name}」？`,
      buttons: [
        { text: '取消', color: $r('app.color.text_secondary') },
        { text: '删除', color: $r('app.color.expense_red') }
      ]
    }).then((result) => {
      if (result.index === 1) {
        animateTo({ curve: AnimationConfig.SPRING }, () => {
          this.creditAccounts.splice(index, 1);
          this.creditAccounts = [...this.creditAccounts];
        });
        this.saveCreditAccounts();
      }
    });
  }

  // ---------- 存钱目标：增删改 ----------
  openGoalAddDialog(): void {
    const controller = new CustomDialogController({
      builder: SavingGoalDialog({
        title: '添加存钱目标',
        confirmText: '添加',
        onConfirm: (name: string, target: number, saved: number, deadline: number) => {
          if (this.savingGoals.some(item => item.name === name)) {
            this.getUIContext().getPromptAction().showToast({ message: '已存在同名目标', duration: 1500 });
            return;
          }
          const goal: SavingGoal = { id: Date.now(), name: name, target: target, saved: saved, deadline: deadline, records: [] };
          animateTo({ curve: AnimationConfig.SPRING }, () => {
            this.savingGoals = [goal, ...this.savingGoals];
          });
          this.saveSavingGoals();
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

  openGoalEditDialog(index: number): void {
    const item = this.savingGoals[index];
    // 目标金额过万时自动以「万」为单位回填
    const useWan = item.target >= 10000;
    const controller = new CustomDialogController({
      builder: SavingGoalDialog({
        title: '编辑存钱目标',
        confirmText: '保存',
        inputName: item.name,
        inputTarget: useWan ? (item.target / 10000).toString() : item.target.toString(),
        inputSaved: useWan ? (item.saved / 10000).toString() : item.saved.toString(),
        deadline: item.deadline ? item.deadline : 0,
        unitWan: useWan,
        onConfirm: (name: string, target: number, saved: number, deadline: number) => {
          if (name !== item.name && this.savingGoals.some(i => i.name === name)) {
            this.getUIContext().getPromptAction().showToast({ message: '已存在同名目标', duration: 1500 });
            return;
          }
          animateTo({ curve: AnimationConfig.SPRING }, () => {
            this.savingGoals[index] = {
              id: item.id,
              name: name,
              target: target,
              saved: saved,
              deadline: deadline,
              records: item.records ? item.records : [],
              challengeType: item.challengeType,
              challengeStart: item.challengeStart,
              billOnDeposit: item.billOnDeposit,
              remindChallenge: item.remindChallenge
            };
            this.savingGoals = [...this.savingGoals];
          });
          this.saveSavingGoals();
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

  deleteSavingGoal(index: number): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '确认删除',
      message: `删除存钱目标「${this.savingGoals[index].name}」？`,
      buttons: [
        { text: '取消', color: $r('app.color.text_secondary') },
        { text: '删除', color: $r('app.color.expense_red') }
      ]
    }).then((result) => {
      if (result.index === 1) {
        animateTo({ curve: AnimationConfig.SPRING }, () => {
          this.savingGoals.splice(index, 1);
          this.savingGoals = [...this.savingGoals];
        });
        this.saveSavingGoals();
      }
    });
  }

  // ---------- 复用 UI ----------
  @Builder
  AddChip(onTap: () => void) {
    Text('+ 添加')
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.brandMain)
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .backgroundColor($r('app.color.category_btn_bg'))
      .borderRadius(8)
      .scale({ x: this.pressedChipKey === 'add_chip' ? 0.88 : 1, y: this.pressedChipKey === 'add_chip' ? 0.88 : 1 })
      .animation({ curve: MotionCurves.PRESS })
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.pressedChipKey = 'add_chip';
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.pressedChipKey = '';
        }
      })
      .onClick(() => { onTap(); })
  }

  @Builder
  AccountAvatar(name: string, color: string) {
    Column() {
      Text(this.getAccountInitial(name))
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
    }
    .width(36)
    .height(36)
    .borderRadius(18)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(color)
  }

  @Builder
  RowActionIcons(onEdit: () => void, onDelete: () => void) {
    Image($r('sys.media.ohos_ic_public_edit'))
      .width(20)
      .height(20)
      .fillColor(this.brandMain)
      .onClick(() => { onEdit(); })
      .margin({ left: 8 })

    Image($r('sys.media.ohos_ic_public_remove'))
      .width(20)
      .height(20)
      .fillColor($r('app.color.expense_red'))
      .onClick(() => { onDelete(); })
      .margin({ left: 8 })
  }

  // ---------- 资产规划卡片 ----------
  @Builder
  LedgerChip(id: number, name: string) {
    Text(name)
      .fontSize(12)
      .fontColor(this.selectedLedgerId === id ? $r('app.color.text_white') : $r('app.color.text_secondary'))
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor(this.selectedLedgerId === id ? this.brandMain : $r('app.color.category_btn_bg'))
      .borderRadius(14)
      .scale({ x: this.pressedChipKey === ('ledger_' + id) ? 0.88 : 1, y: this.pressedChipKey === ('ledger_' + id) ? 0.88 : 1 })
      .animation({ curve: MotionCurves.PRESS })
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.pressedChipKey = 'ledger_' + id;
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.pressedChipKey = '';
        }
      })
      .onClick(() => { this.selectLedger(id); })
  }

  @Builder
  HealthCard() {
    Column() {
      Row() {
        Text('财务健康度')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Image($r('sys.media.ohos_ic_public_edit'))
          .width(18)
          .height(18)
          .fillColor(this.brandMain)
          .margin({ right: 10 })
          .onClick(() => { this.openProfileDialog(); })
        Text(this.healthResult.grade)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getGradeColor(this.healthResult.grade))
          .scale({ x: this.healthGradeScale, y: this.healthGradeScale })
      }
      .width('100%')

      // 画像标签 / 完善引导
      if (this.hasProfile()) {
        Text(`画像：收入${this.profile.incomeStable} · ${this.profile.fixedExpense} · 应急${this.profile.emergency} · ${this.profile.debtStatus} · 偏好${this.profile.riskPref}`)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 6 })
          .onClick(() => { this.openProfileDialog(); })
      } else {
        Row() {
          Text('完善财务画像问卷，获得更精准的评估')
            .fontSize(12)
            .fontColor(this.brandMain)
            .fontWeight(FontWeight.Medium)
        }
        .width('100%')
        .padding({ top: 8, bottom: 8, left: 10, right: 10 })
        .borderRadius(10)
        .backgroundColor($r('app.color.category_btn_bg'))
        .margin({ top: 8 })
        .onClick(() => { this.openProfileDialog(); })
      }

      // 账本筛选
      if (this.ledgers.length > 0) {
        Scroll() {
          Row({ space: 8 }) {
            this.LedgerChip(0, '全部')
            ForEach(this.ledgers, (item: LedgerItem) => {
              this.LedgerChip(item.id, item.name)
            }, (item: LedgerItem) => item.id.toString() + '_' + item.name)
          }
          .padding({ top: 2, bottom: 2 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .margin({ top: 10 })
      }

      Row() {
        Stack({ alignContent: Alignment.Center }) {
          Progress({ value: this.healthRingValue, total: 100, type: ProgressType.Ring })
            .width(84)
            .height(84)
            .color(this.getGradeColor(this.healthResult.grade))
            .style({ strokeWidth: 8 })
          Column() {
            Text(this.healthScoreDisplay.toString())
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Text('综合评分')
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 2 })
          }
        }

        Column() {
          ForEach(this.healthResult.items, (item: HealthItem, index: number) => {
            Row() {
              Text(item.name)
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
              Blank()
              Text(item.valueText)
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.getItemColor(item.score))
            }
            .width('100%')
            .padding({ top: 5, bottom: 5 })
            .transition(TransitionEffect.OPACITY
              .combine(TransitionEffect.translate({ x: 26 }))
              .animation({ delay: index * 80, curve: AnimationConfig.SPRING_SOFT }))
          }, (item: HealthItem) => item.name + '_' + item.valueText + '_' + item.score.toString())
        }
        .layoutWeight(1)
        .margin({ left: 18 })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .margin({ top: 12 })
      .alignItems(VerticalAlign.Center)

      if (this.healthResult.suggestions.length > 0) {
        Divider()
          .color($r('app.color.border_color'))
          .margin({ top: 10, bottom: 8 })

        Column() {
          ForEach(this.healthResult.suggestions, (tip: string) => {
            Text('· ' + tip)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 3, bottom: 3 })
              .transition(TransitionEffect.OPACITY
                .combine(TransitionEffect.translate({ y: 10 }))
                .animation({ duration: 300, curve: Curve.EaseOut }))
          }, (tip: string) => tip)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(18)
    .shadow({ radius: 20, color: $r('app.color.shadow_color'), offsetX: 0, offsetY: 8 }).border({ width: 1, color: $r('app.color.border_color') })
    .margin({ bottom: 12 })
  }

  @Builder
  AssetPieCard() {
    if (this.pieEntries.length > 0) {
      Column() {
        Row() {
          Text('资产分布')
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Blank()
          Text(this.amountText(this.getFundTotal()))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')

        Row() {
          Stack({ alignContent: Alignment.Center }) {
            DataPanel({
              values: this.getPieValues(),
              max: this.getPieMax(),
              type: DataPanelType.Circle
            })
              .width(160)
              .height(160)
              .valueColors(this.getPieColors())
            Column() {
              Text('总资产')
                .fontSize(10)
                .fontColor($r('app.color.text_secondary'))
              Text(this.amountVisible ? this.formatAmount(this.getFundTotal()) : '****')
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                .margin({ top: 2 })
            }
          }

          Column() {
            ForEach(this.pieEntries, (item: FundAccount, index: number) => {
              Row() {
                Column()
                  .width(10)
                  .height(10)
                  .borderRadius(5)
                  .backgroundColor(this.getPaletteColor(index))
                  .margin({ right: 8 })
                Text(item.name)
                  .fontSize(13)
                  .fontColor($r('app.color.text_primary'))
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(this.getPiePercent(item) + '%')
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
              }
              .width('100%')
              .padding({ top: 4, bottom: 4 })
            }, (item: FundAccount) => item.name + '_' + item.amount.toFixed(2))
          }
          .layoutWeight(1)
          .margin({ left: 16 })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .margin({ top: 14 })
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .padding(16)
      .backgroundColor($r('app.color.card_bg'))
      .borderRadius(18)
      .shadow({ radius: 20, color: $r('app.color.shadow_color'), offsetX: 0, offsetY: 8 }).border({ width: 1, color: $r('app.color.border_color') })
      .margin({ bottom: 12 })
    }
  }

  @Builder
  NetAssetTrendCard() {
    if (this.bills.length > 0) {
      Column() {
        Row() {
          Text('净资产趋势')
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Blank()
          Text(`近6个月 · ${this.getLedgerName(this.selectedLedgerId)} · 按收支估算`)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')

        Row() {
          ForEach(this.trendPoints, (p: NetAssetPoint, index: number) => {
            Column() {
              if (index === this.trendPoints.length - 1) {
                Text(this.amountVisible ? this.formatAmount(p.value) : '****')
                  .fontSize(10)
                  .fontColor(p.value >= 0 ? $r('app.color.income_gold') : $r('app.color.expense_red'))
                  .margin({ bottom: 4 })
              }
              Column()
                .width(14)
                .height(this.getTrendBarHeight(p.value))
                .borderRadius(4)
                .backgroundColor(p.value >= 0 ? $r('app.color.income_gold') : $r('app.color.expense_red'))
              Text(p.label)
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
                .margin({ top: 6 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Center)
          }, (p: NetAssetPoint, index: number) => p.label + '_' + p.value.toFixed(0) + '_' + index.toString())
        }
        .width('100%')
        .margin({ top: 14 })
        .alignItems(VerticalAlign.Bottom)
      }
      .width('100%')
      .padding(16)
      .backgroundColor($r('app.color.card_bg'))
      .borderRadius(18)
      .shadow({ radius: 20, color: $r('app.color.shadow_color'), offsetX: 0, offsetY: 8 }).border({ width: 1, color: $r('app.color.border_color') })
      .margin({ bottom: 12 })
    }
  }

  @Builder
  SquiggleDeco() {
    Image($r('app.media.hd_underline'))
      .width(52)
      .height(8)
      .objectFit(ImageFit.Fill)
  }

  // ---------- 滚动联动顶部玻璃栏：随滚动渐显的毛玻璃底与发丝线 ----------
  // level: 0（顶部）→ 1（滚动后），56vp 滚动行程内完成透明过渡
  headerPlateBg(level: number): string {
    const clamped: number = Math.max(0, Math.min(1, level));
    if (this.colorModeSignals.mode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK) {
      return 'rgba(14, 15, 21, ' + (clamped * 0.86).toFixed(3) + ')';
    }
    return 'rgba(241, 243, 250, ' + (clamped * 0.86).toFixed(3) + ')';
  }

  headerPlateLine(level: number): string {
    const clamped: number = Math.max(0, Math.min(1, level));
    if (this.colorModeSignals.mode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK) {
      return 'rgba(40, 43, 56, ' + (clamped * 0.7).toFixed(3) + ')';
    }
    return 'rgba(203, 209, 224, ' + (clamped * 0.7).toFixed(3) + ')';
  }

  build() {
    Column() {
      // 顶部玻璃栏：初始全透明，随内容滚动渐显毛玻璃+发丝线（系统应用式透明过渡）
      Column() {
      // 状态栏占位：高度含状态栏避让，背景延伸到状态栏下（沉浸式）
      Row()
        .width('100%')
        .height(this.statusBarVp + 10)
        .backgroundColor(Color.Transparent)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
        .flexShrink(0)

      // 标题栏 + 模式切换
      Row() {
        Text('财富')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Blank()

        // 资产 / 存钱 模式切换（选中底色滑动过渡）
        Row() {
          Stack({ alignContent: Alignment.Start }) {
            Column()
              .width(56)
              .height(36)
              .borderRadius(18)
              .backgroundColor($r('app.color.category_btn_bg'))
              .offset({ x: this.wealthMode === 'asset' ? 0 : 56 })

            Row() {
              Row() {
                Text('资产')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.wealthMode === 'asset' ?
                  this.brandMain : $r('app.color.text_secondary'))
              }
              .width(56)
              .height(36)
              .justifyContent(FlexAlign.Center)
              .scale({ x: this.pressedChipKey === 'mode_asset' ? 0.9 : 1, y: this.pressedChipKey === 'mode_asset' ? 0.9 : 1 })
              .animation({ curve: MotionCurves.PRESS })
              .onTouch((event: TouchEvent) => {
                if (event.type === TouchType.Down) {
                  this.pressedChipKey = 'mode_asset';
                } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                  this.pressedChipKey = '';
                }
              })
              .onClick(() => { this.switchWealthMode('asset'); })

              Row() {
                Text('存钱')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.wealthMode === 'saving' ?
                  this.brandMain : $r('app.color.text_secondary'))
              }
              .width(56)
              .height(36)
              .justifyContent(FlexAlign.Center)
              .scale({ x: this.pressedChipKey === 'mode_saving' ? 0.9 : 1, y: this.pressedChipKey === 'mode_saving' ? 0.9 : 1 })
              .animation({ curve: MotionCurves.PRESS })
              .onTouch((event: TouchEvent) => {
                if (event.type === TouchType.Down) {
                  this.pressedChipKey = 'mode_saving';
                } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                  this.pressedChipKey = '';
                }
              })
              .onClick(() => { this.switchWealthMode('saving'); })
            }
          }
        }
        .height(38)
        .borderRadius(19)
        .border({ width: 1, color: $r('app.color.border_color') })
        .backgroundColor($r('app.color.card_bg'))
      }
      .width('100%')
      .margin({ top: 10, bottom: 12 })
      }
      .width('100%')
      .backgroundEffect({
        // 模糊半径随滚动渐增：顶部 0（完全透明直透背景光斑）→ 40vp 毛玻璃
        radius: this.headerGlass * 40,
        color: this.headerPlateBg(this.headerGlass)
      })
      .border({ width: { bottom: 1 }, color: this.headerPlateLine(this.headerGlass) })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])

      Scroll() {
        Column() {
          if (this.wealthMode === 'asset') {
            // ===== 资产模式 =====
            Column() {
              // 卡片 1：总资产 / 总负债 / 净资产
              Column() {
                Row() {
                  Column() {
                    Text('总资产')
                      .fontSize(13)
                      .fontColor($r('app.color.text_secondary'))
                    Text(this.amountText(this.getFundTotal()))
                      .fontSize(24)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.text_primary'))
                      .margin({ top: 4 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Column() {
                    Text('总负债')
                      .fontSize(13)
                      .fontColor($r('app.color.text_secondary'))
                    Text(this.amountText(this.getTotalDebt()))
                      .fontSize(24)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.expense_red'))
                      .margin({ top: 4 })
                  }
                  .alignItems(HorizontalAlign.End)
                  .layoutWeight(1)

                  // 小眼睛：一键隐藏/显示资产金额
                  SymbolGlyph(this.amountVisible ? $r('sys.symbol.eye') : $r('sys.symbol.eye_slash'))
                    .fontSize(20)
                    .fontColor([$r('app.color.text_secondary')])
                    .margin({ left: 10 })
                    .onClick(() => {
                      animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
                        this.amountVisible = !this.amountVisible;
                      });
                      this.saveAmountVisible(this.amountVisible);
                    })
                }
                .width('100%')

                Divider()
                  .color($r('app.color.border_color'))
                  .margin({ top: 14, bottom: 10 })

                Row() {
                  Text('净资产')
                    .fontSize(13)
                    .fontColor($r('app.color.text_secondary'))
                  Blank()
                  Text(this.amountText(this.getNetAsset()))
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.getNetAsset() >= 0 ?
                    $r('app.color.income_gold') : $r('app.color.expense_red'))
                }
                .width('100%')
              }
              .width('100%')
              .padding(16)
              .backgroundColor($r('app.color.card_bg'))
              .borderRadius(18)
              .shadow({ radius: 20, color: $r('app.color.shadow_color'), offsetX: 0, offsetY: 8 }).border({ width: 1, color: $r('app.color.border_color') })
              .margin({ bottom: 12 })

              // 卡片 1.5：财务健康度
              this.HealthCard()

              // 卡片 2：资金账户
              Column() {
                Row() {
                  Text('资金账户')
                    .fontSize(17)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                  Blank()
                  Text(this.amountText(this.getFundTotal()))
                    .fontSize(14)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ right: 10 })
                  this.AddChip(() => { this.openFundAddDialog(); })
                }
                .width('100%')
                .margin({ bottom: 4 })

                if (this.fundAccounts.length === 0) {
                  Column() {
                    Text('暂无资金账户')
                      .fontSize(14)
                      .fontColor($r('app.color.text_secondary'))
                    Text('添加现金、微信、支付宝等账户，自动计入总资产')
                      .fontSize(12)
                      .fontColor($r('app.color.text_secondary'))
                      .margin({ top: 4 })
                  }
                  .width('100%')
                  .alignItems(HorizontalAlign.Center)
                  .padding({ top: 20, bottom: 20 })
                } else {
                  ForEach(this.fundAccounts, (item: FundAccount, index: number) => {
                    Row() {
                      this.AccountAvatar(item.name, this.getPaletteColor(index))

                      Text(item.name)
                        .fontSize(15)
                        .fontColor($r('app.color.text_primary'))
                        .margin({ left: 12 })
                        .layoutWeight(1)

                      Text(this.amountText(item.amount))
                        .fontSize(15)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.text_primary'))
                        .margin({ right: 8 })

                      this.RowActionIcons(
                        () => { this.openFundEditDialog(index); },
                        () => { this.deleteFundAccount(index); }
                      )
                    }
                    .width('100%')
                    .padding({ top: 10, bottom: 10 })
                  }, (item: FundAccount) => item.name + '_' + item.amount.toFixed(2))
                }
              }
              .width('100%')
              .padding(16)
              .backgroundColor($r('app.color.card_bg'))
              .borderRadius(18)
              .shadow({ radius: 20, color: $r('app.color.shadow_color'), offsetX: 0, offsetY: 8 }).border({ width: 1, color: $r('app.color.border_color') })
              .margin({ bottom: 12 })

              // 卡片 2.5：资产分布
              this.AssetPieCard()

              // 卡片 3：信用账户
              Column() {
                Row() {
                  Text('信用账户')
                    .fontSize(17)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                  Blank()
                  this.AddChip(() => { this.openCreditAddDialog(); })
                }
                .width('100%')
                .margin({ bottom: 4 })

                if (this.creditAccounts.length === 0) {
                  Column() {
                    Text('暂无信用账户')
                      .fontSize(14)
                      .fontColor($r('app.color.text_secondary'))
                    Text('添加信用卡、花呗等账户，记录欠款情况')
                      .fontSize(12)
                      .fontColor($r('app.color.text_secondary'))
                      .margin({ top: 4 })
                  }
                  .width('100%')
                  .alignItems(HorizontalAlign.Center)
                  .padding({ top: 20, bottom: 20 })
                } else {
                  ForEach(this.creditAccounts, (item: CreditAccount, index: number) => {
                    Row() {
                      this.AccountAvatar(item.name, this.getPaletteColor(index))

                      Column() {
                        Text(item.name)
                          .fontSize(15)
                          .fontColor($r('app.color.text_primary'))
                        if (item.dueDate > 0) {
                          Text(this.getDueDateText(item.dueDate))
                            .fontSize(12)
                            .fontColor(this.getDueDays(item.dueDate) < 0 ?
                            $r('app.color.expense_red') : $r('app.color.text_secondary'))
                            .margin({ top: 2 })
                        }
                      }
                      .alignItems(HorizontalAlign.Start)
                      .margin({ left: 12 })
                      .layoutWeight(1)

                      Text(this.amountText(item.debt))
                        .fontSize(15)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.expense_red'))
                        .margin({ right: 8 })

                      this.RowActionIcons(
                        () => { this.openCreditEditDialog(index); },
                        () => { this.deleteCreditAccount(index); }
                      )
                    }
                    .width('100%')
                    .padding({ top: 10, bottom: 10 })
                  }, (item: CreditAccount) =>
                  item.id.toString() + '_' + item.debt.toFixed(2) + '_' + item.dueDate.toString())

                  Divider()
                    .color($r('app.color.border_color'))
                    .margin({ top: 6, bottom: 6 })

                  Row() {
                    Text('合计欠款')
                      .fontSize(13)
                      .fontColor($r('app.color.text_secondary'))
                    Blank()
                    Text(this.amountText(this.getTotalDebt()))
                      .fontSize(15)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.expense_red'))
                  }
                  .width('100%')
                }
              }
              .width('100%')
              .padding(16)
              .backgroundColor($r('app.color.card_bg'))
              .borderRadius(18)
              .shadow({ radius: 20, color: $r('app.color.shadow_color'), offsetX: 0, offsetY: 8 }).border({ width: 1, color: $r('app.color.border_color') })
              .margin({ bottom: 12 })

              // 卡片 3.5：净资产趋势
              this.NetAssetTrendCard()
            }
            .width('100%')
            // 左侧 Tab 内容：从左侧滑入/滑出（跟随滑块方向，柔和弹簧）
            .transition(TransitionEffect.translate({ x: -48 })
              .combine(TransitionEffect.OPACITY)
              .animation({ curve: AnimationConfig.SPRING_SOFT }))
          } else {
            // ===== 存钱模式 =====
            Column() {
              // 目标列表标题
              Row() {
                Text('存钱目标')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                  .overlay(this.SquiggleDeco(), { align: Alignment.Bottom, offset: { x: 0, y: 5 } })
                Blank()
                Row() {
                  HandIcon({ name: 'target', iconSize: 13 })
                  Text('发起挑战')
                    .fontSize(13)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.income_gold'))
                    .margin({ left: 3 })
                }
                .alignItems(VerticalAlign.Center)
                .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                .backgroundColor($r('app.color.category_btn_bg'))
                .borderRadius(8)
                .margin({ right: 8 })
                .scale({ x: this.pressedChipKey === 'challenge' ? 0.9 : 1, y: this.pressedChipKey === 'challenge' ? 0.9 : 1 })
                .animation({ curve: MotionCurves.PRESS })
                .onTouch((event: TouchEvent) => {
                  if (event.type === TouchType.Down) {
                    this.pressedChipKey = 'challenge';
                  } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                    this.pressedChipKey = '';
                  }
                })
                .onClick(() => { this.openChallengeDialog(); })
                this.AddChip(() => { this.openGoalAddDialog(); })
              }
              .width('100%')
              .margin({ bottom: 12 })

              if (this.savingGoals.length === 0) {
                Column() {
                  Text('还没有存钱目标')
                    .fontSize(14)
                    .fontColor($r('app.color.text_secondary'))
                  Text('点击「添加」，为想买的东西攒钱吧')
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ top: 4 })
                }
                .width('100%')
                .alignItems(HorizontalAlign.Center)
                .padding({ top: 40, bottom: 40 })
                .backgroundColor($r('app.color.card_bg'))
                .borderRadius(18)
                .shadow({ radius: 20, color: $r('app.color.shadow_color'), offsetX: 0, offsetY: 8 }).border({ width: 1, color: $r('app.color.border_color') })
              } else {
                // 每个存钱目标一张独立小卡片：点击卡片进入目标详情页（旅程/存入/日记）
                ForEach(this.savingGoals, (item: SavingGoal, index: number) => {
                  Column() {
                    Row() {
                      Text(item.name)
                        .fontSize(16)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.text_primary'))
                      if (item.challengeType && getChallengeTemplate(item.challengeType)) {
                        Row() {
                          HandIcon({ name: 'target', iconSize: 11 })
                          Text('挑战')
                            .fontSize(10)
                            .fontWeight(FontWeight.Medium)
                            .fontColor($r('app.color.income_gold'))
                            .margin({ left: 2 })
                        }
                        .alignItems(VerticalAlign.Center)
                        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                        .backgroundColor($r('app.color.category_btn_bg'))
                        .borderRadius(8)
                        .margin({ left: 6 })
                      }
                      Blank()
                      Text(this.getGoalPercent(item.saved, item.target) + '%')
                        .fontSize(13)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(this.getGoalPercent(item.saved, item.target) >= 100 ?
                        $r('app.color.income_gold') : this.brandMain)
                    }
                    .width('100%')

                    Progress({
                      value: this.getGoalPercent(item.saved, item.target),
                      total: 100,
                      type: ProgressType.Linear
                    })
                      .width('100%')
                      .height(8)
                      .color(this.getGoalPercent(item.saved, item.target) >= 100 ?
                      $r('app.color.income_gold') : this.brandMain)
                      .margin({ top: 10 })

                    // 达成预测：按近3个月平均结余估算
                    Text(this.getGoalPrediction(item))
                      .fontSize(12)
                      .fontColor(this.getGoalPredictionColor(item))
                      .margin({ top: 8 })

                    Row() {
                      Column() {
                        Text('已存入')
                          .fontSize(12)
                          .fontColor($r('app.color.text_secondary'))
                        Text('¥' + this.formatAmount(item.saved))
                          .fontSize(16)
                          .fontWeight(FontWeight.Bold)
                          .fontColor($r('app.color.income_gold'))
                          .margin({ top: 2 })
                      }
                      .alignItems(HorizontalAlign.Start)
                      .layoutWeight(1)

                      Column() {
                        Text('目标总额')
                          .fontSize(12)
                          .fontColor($r('app.color.text_secondary'))
                        Text('¥' + this.formatAmount(item.target))
                          .fontSize(16)
                          .fontWeight(FontWeight.Bold)
                          .fontColor($r('app.color.text_primary'))
                          .margin({ top: 2 })
                      }
                      .alignItems(HorizontalAlign.End)

                      this.RowActionIcons(
                        () => { this.openGoalEditDialog(index); },
                        () => { this.deleteSavingGoal(index); }
                      )
                    }
                    .width('100%')
                    .margin({ top: 12 })
                    .alignItems(VerticalAlign.Top)
                  }
                  .width('100%')
                  .padding(16)
                  .backgroundColor($r('app.color.card_bg'))
                  .borderRadius(18)
                  .shadow({ radius: 20, color: $r('app.color.shadow_color'), offsetX: 0, offsetY: 8 }).border({ width: 1, color: $r('app.color.border_color') })
                  .margin({ bottom: 12 })
                  .onClick(() => { this.openGoalDetail(item); })
                }, (item: SavingGoal) =>
                item.id.toString() + '_' + item.saved.toFixed(2) + '_' + item.target.toFixed(2))
              }

              // ===== 愿望清单（30 天冷静期） =====
              Row() {
                Text('愿望清单')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                Text(`想买的先冷静 ${WISH_COOLING_DAYS} 天`)
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
                  .margin({ left: 8 })
                Blank()
                this.AddChip(() => { this.openWishAddDialog(); })
              }
              .width('100%')
              .margin({ top: 4, bottom: 12 })

              if (this.wishes.length === 0) {
                Column() {
                  Text('还没有愿望')
                    .fontSize(14)
                    .fontColor($r('app.color.text_secondary'))
                  Text('想买的大件先放这里冷静冷静，冷静期满还想买再出手')
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ top: 4 })
                }
                .width('100%')
                .alignItems(HorizontalAlign.Center)
                .padding({ top: 26, bottom: 26 })
                .backgroundColor($r('app.color.card_bg'))
                .borderRadius(18)
                .shadow({ radius: 20, color: $r('app.color.shadow_color'), offsetX: 0, offsetY: 8 }).border({ width: 1, color: $r('app.color.border_color') })
              } else {
                ForEach(this.wishes, (item: WishItem, index: number) => {
                  Column() {
                    Row() {
                      HandIcon({ name: item.status === 'cooling' ? 'ice' : 'heart', iconSize: 20 })
                      Column() {
                        Text(item.name)
                          .fontSize(15)
                          .fontWeight(FontWeight.Medium)
                          .fontColor($r('app.color.text_primary'))
                        if (item.status === 'cooling') {
                          Text(wishCoolingRemain(item) > 0 ?
                            `冷静期还剩 ${wishCoolingRemain(item)} 天` : '冷静期已满，该做决定了')
                            .fontSize(12)
                            .fontColor(wishCoolingRemain(item) > 0 ?
                            $r('app.color.text_secondary') : $r('app.color.budget_orange'))
                            .margin({ top: 3 })
                        } else {
                          Text('冷静期满，还想买 ✓')
                            .fontSize(12)
                            .fontColor($r('app.color.expense_red'))
                            .margin({ top: 3 })
                        }
                      }
                      .alignItems(HorizontalAlign.Start)
                      .layoutWeight(1)
                      .margin({ left: 10 })

                      Text('¥' + this.formatAmount(item.price))
                        .fontSize(15)
                        .fontWeight(FontWeight.Bold)
                        .fontColor($r('app.color.text_primary'))
                    }
                    .width('100%')

                    if (item.status === 'cooling') {
                      Progress({
                        value: WISH_COOLING_DAYS - wishCoolingRemain(item),
                        total: WISH_COOLING_DAYS,
                        type: ProgressType.Linear
                      })
                        .width('100%')
                        .height(5)
                        .borderRadius(3)
                        .color(wishCoolingRemain(item) > 0 ?
                        this.brandMain : $r('app.color.budget_orange'))
                        .margin({ top: 10 })

                      if (wishCoolingRemain(item) === 0) {
                        Row() {
                          Blank()
                          Text('做决定')
                            .fontSize(13)
                            .fontWeight(FontWeight.Bold)
                            .fontColor($r('app.color.text_white'))
                            .backgroundColor($r('app.color.budget_orange'))
                            .borderRadius(15)
                            .padding({ left: 16, right: 16, top: 6, bottom: 6 })
                            .margin({ top: 10 })
                            .scale({ x: this.pressedChipKey === ('decide_' + index) ? 0.9 : 1, y: this.pressedChipKey === ('decide_' + index) ? 0.9 : 1 })
                            .animation({ curve: MotionCurves.PRESS })
                            .onTouch((event: TouchEvent) => {
                              if (event.type === TouchType.Down) {
                                this.pressedChipKey = 'decide_' + index;
                              } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                                this.pressedChipKey = '';
                              }
                            })
                            .onClick(() => { this.onWishDecide(index); })
                        }
                        .width('100%')
                      }
                    } else {
                      Row() {
                        Blank()
                         Text('转存钱目标')
                           .fontSize(13)
                           .fontWeight(FontWeight.Medium)
                           .fontColor($r('app.color.income_gold'))
                           .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                           .backgroundColor($r('app.color.category_btn_bg'))
                           .borderRadius(15)
                           .scale({ x: this.pressedChipKey === ('convert_' + index) ? 0.9 : 1, y: this.pressedChipKey === ('convert_' + index) ? 0.9 : 1 })
                           .animation({ curve: MotionCurves.PRESS })
                           .onTouch((event: TouchEvent) => {
                             if (event.type === TouchType.Down) {
                               this.pressedChipKey = 'convert_' + index;
                             } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                               this.pressedChipKey = '';
                             }
                           })
                           .onClick(() => { this.dropWish(index, true); })
                         Text('移除')
                           .fontSize(13)
                           .fontColor($r('app.color.text_secondary'))
                           .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                           .margin({ left: 8 })
                           .scale({ x: this.pressedChipKey === ('remove_' + index) ? 0.9 : 1, y: this.pressedChipKey === ('remove_' + index) ? 0.9 : 1 })
                           .animation({ curve: MotionCurves.PRESS })
                           .onTouch((event: TouchEvent) => {
                             if (event.type === TouchType.Down) {
                               this.pressedChipKey = 'remove_' + index;
                             } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                               this.pressedChipKey = '';
                             }
                           })
                           .onClick(() => { this.dropWish(index, false); })
                      }
                      .width('100%')
                      .margin({ top: 10 })
                    }
                  }
                  .width('100%')
                  .padding(16)
                  .backgroundColor($r('app.color.card_bg'))
                  .borderRadius(18)
                  .shadow({ radius: 20, color: $r('app.color.shadow_color'), offsetX: 0, offsetY: 8 }).border({ width: 1, color: $r('app.color.border_color') })
                  .margin({ bottom: 12 })
                  .onClick(() => {
                    if (item.status === 'cooling' && wishCoolingRemain(item) === 0) {
                      this.onWishDecide(index);
                    }
                  })
                }, (item: WishItem) =>
                item.id.toString() + '_' + item.status + '_' + wishCoolingRemain(item).toString())
              }
            }
            .width('100%')
            // 右侧 Tab 内容：从右侧滑入/滑出（跟随滑块方向，柔和弹簧）
            .transition(TransitionEffect.translate({ x: 48 })
              .combine(TransitionEffect.OPACITY)
              .animation({ curve: AnimationConfig.SPRING_SOFT }))
          }

          // ===== 赚钱计时入口 =====
          Row() {
            Row() {
              HandIcon({ name: 'hourglass', iconSize: 22 })
            }
            .width(42)
            .height(42)
            .justifyContent(FlexAlign.Center)
            .backgroundColor(this.brandTint)
            .borderRadius(12)

            Column() {
              Text('赚钱计时')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
              Text('设定时薪开始工作，实时看钱进账')
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .margin({ top: 3 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            .margin({ left: 12 })

            Text('开始')
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_white'))
              .padding({ left: 16, right: 16, top: 7, bottom: 7 })
              .backgroundColor($r('app.color.income_gold'))
              .borderRadius(15)
            .scale({
              x: this.pressedChipKey === 'earning_go' ? 0.92 : 1,
              y: this.pressedChipKey === 'earning_go' ? 0.92 : 1
            })
            .animation({ curve: MotionCurves.PRESS })
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) {
                this.pressedChipKey = 'earning_go';
              } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                this.pressedChipKey = '';
              }
            })
          }
          .width('100%')
          .padding(14)
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius(18)
          .shadow({ radius: 20, color: $r('app.color.shadow_color'), offsetX: 0, offsetY: 8 })
          .border({ width: 1, color: $r('app.color.border_color') })
          .margin({ top: 4, bottom: 12 })
          .onClick(() => {
            this.navPathStack.pushPathByName('EarningTimerPage', undefined);
          })

          // 尾部占位：避开悬浮页签栏（栏高 56 + 底边距 navBarVp + 呼吸 12），划到底部内容不被栏体遮挡
          Column()
            .width('100%')
            .height(this.navBarVp + 68)
        }
        .width('100%')
        .padding({ bottom: 0 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .onDidScroll((scrollOffset: number, scrollState: ScrollState) => {
        // 滚动联动玻璃栏：56vp 行程内完成 透明→毛玻璃 过渡
        this.headerGlass = Math.max(0, Math.min(1, this.headerGlass + scrollOffset / 56));
      })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 20 })
    .backgroundColor(Color.Transparent)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
