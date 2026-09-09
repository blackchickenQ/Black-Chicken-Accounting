import { promptAction } from '@kit.ArkUI';
import { ConfigurationConstant } from '@kit.AbilityKit';
import dataPreferences from '@ohos.data.preferences';
import { picker } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { fileUri } from '@kit.CoreFileKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { HdsTabs, hdsMaterial } from '@kit.UIDesignKit';
import ExcelJS from '@archermind/exceljs';
import { taskpool } from '@kit.ArkTS';
import { router } from '@kit.ArkUI';
import { util } from '@kit.ArkTS';
import { window } from '@kit.ArkUI';
import notificationManager from '@ohos.notificationManager';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { uiAppearance } from '@kit.ArkUI';
import { CalendarTab } from './CalendarTab';
import { CategoryManageParams } from './CategoryManagePage';
import { BaseCalendar } from 'base_calendar';
import { curves } from '@kit.ArkUI';


// ---------- 1. 全局动画配置 ----------
export class AnimationConfig {
  static DURATION: number = 380;
  static CURVE: Curve = Curve.EaseInOut;
  static LIST_DURATION: number = 300;
  // Q弹弹簧曲线：按压回弹（阻尼小，弹跳明显）
  static SPRING: curves.ICurve = curves.springMotion(0.4, 0.6);
  // 柔和弹簧曲线：内容切换、弹窗（阻尼大，轻微回弹）
  static SPRING_SOFT: curves.ICurve = curves.springMotion(0.5, 0.8);
}

// ---------- 2. 分类定义 ----------
export const CATEGORIES: string[] = ['餐饮', '交通', '购物', '娱乐', '医疗', '教育', '其他'];
export const CATEGORY_COLORS: Record<string, string> = {
  '餐饮': '#FF6B6B',
  '交通': '#4ECDC4',
  '购物': '#45B7D1',
  '娱乐': '#FFA94D',
  '医疗': '#A29BFE',
  '教育': '#FD79A8',
  '其他': '#B2BEC3'
};

interface AssetCategory {
  name: string;
  amount: number;
}

// ---------- 3. 多账本定义 ----------
export const DEFAULT_LEDGER_ID: number = 1;

export interface LedgerItem {
  id: number;
  name: string;
  icon: string;
  color: string;
  categories: string[];
  createdAt: number;
  isDefault: boolean;
}

// 账本可选图标（sys.symbol 名称已在 SDK sysResource.js 中验证）
export const LEDGER_ICON_KEYS: string[] = [
  'book', 'house', 'airplane', 'briefcase', 'cart', 'gift', 'heart',
  'pawprint', 'gamecontroller', 'graduationcap', 'creditcard', 'wallet',
  'car', 'fork_knife', 'lightbulb', 'leaf'
];

export function getLedgerIconResource(iconKey: string): Resource {
  switch (iconKey) {
    case 'house':
      return $r('sys.symbol.house');
    case 'airplane':
      return $r('sys.symbol.airplane');
    case 'briefcase':
      return $r('sys.symbol.briefcase');
    case 'cart':
      return $r('sys.symbol.cart');
    case 'gift':
      return $r('sys.symbol.gift');
    case 'heart':
      return $r('sys.symbol.heart');
    case 'pawprint':
      return $r('sys.symbol.pawprint');
    case 'gamecontroller':
      return $r('sys.symbol.gamecontroller');
    case 'graduationcap':
      return $r('sys.symbol.graduationcap');
    case 'creditcard':
      return $r('sys.symbol.creditcard');
    case 'wallet':
      return $r('sys.symbol.wallet');
    case 'car':
      return $r('sys.symbol.car');
    case 'fork_knife':
      return $r('sys.symbol.fork_knife');
    case 'lightbulb':
      return $r('sys.symbol.lightbulb');
    case 'leaf':
      return $r('sys.symbol.leaf');
    default:
      return $r('sys.symbol.book');
  }
}

// 分类取色：内置分类用固定色，自定义分类按名称哈希取调色板颜色
export function getCategoryColor(category: string): string {
  const color = CATEGORY_COLORS[category];
  if (color !== undefined) {
    return color;
  }
  const palette: string[] = [
    '#FF6B6B', '#4ECDC4', '#45B7D1', '#FFA94D', '#A29BFE',
    '#FD79A8', '#00B894', '#E17055', '#6C5CE7', '#FDCB6E'
  ];
  let hash: number = 0;
  for (let i = 0; i < category.length; i++) {
    hash = (hash * 31 + category.charCodeAt(i)) % 1000000;
  }
  return palette[hash % palette.length];
}

// ========== 添加账单弹窗 ==========
@CustomDialog
struct AddBillDialog {
  controller: CustomDialogController = new CustomDialogController({
    builder: () => {}
  });
  @StorageLink('currentColorMode') currentColorMode: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 当前账本的分类列表（由父组件传入）
  categories: string[] = ['其他'];
  @State inputName: string = '';
  @State inputAmount: string = '';
  @State selectedType: '收入' | '支出' = '支出';
  @State selectedDate: Date = new Date();
  @State selectedCategory: string = '其他';
  @State selectedSource: string = '现金';
  @State sourceList: string[] = ['现金', '微信', '支付宝', '银行卡'];
  @State inputTags: string = '';  // 标签输入框内容
  @State selectedTags: string[] = [];  // 已选择的标签列表
  @State availableTags: string[] = [];  // 已有的标签列表


  // 第 42 行附近
  onAddBill: (name: string, amount: number, type: '收入' | '支出', date: Date, category: string, source: string, tags: string[]) => void = () => {};


  async loadTags() {
  try {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    const data = await prefs.get('all_tags', '[]') as string;
    this.availableTags = JSON.parse(data);
  } catch (e) {
    console.error('加载标签失败', e);
  }
}

  // 添加标签
  async addTag(tag: string) {
    const trimmed = tag.trim();
    if (trimmed.length === 0) return;
    if (this.selectedTags.includes(trimmed)) {
      promptAction.showToast({ message: '标签已存在', duration: 1000 });
      return;
    }
    this.selectedTags = [...this.selectedTags, trimmed];
    this.inputTags = '';

    // ✅ 如果新标签不在可用列表中，添加到可用列表并持久化
    if (!this.availableTags.includes(trimmed)) {
      this.availableTags = [...this.availableTags, trimmed];
      try {
        const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
        const prefs = await dataPreferences.getPreferences(context, 'bill_data');
        await prefs.put('all_tags', JSON.stringify(this.availableTags));
        await prefs.flush();
      } catch (e) {
        console.error('保存标签失败', e);
      }
    }
  }

  // 移除标签
  removeTag(tag: string) {
    this.selectedTags = this.selectedTags.filter(t => t !== tag);
  }

  // 在 aboutToAppear 中调用
  aboutToAppear() {
    if (this.categories.length > 0) {
      this.selectedCategory = this.categories[0];
    }
    this.loadSources();
    this.loadTags();  // ✅ 新增
  }

  async loadSources() {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');
      const data = await prefs.get('asset_categories', '[]') as string;
      const parsed = JSON.parse(data) as AssetCategory[];
      if (parsed.length > 0) {
        this.sourceList = parsed.map((item: AssetCategory) => item.name);
        if (this.sourceList.includes(this.selectedSource)) {
          this.selectedSource = this.sourceList[0];
        }
      }
    } catch (e) {
      console.error('加载来源失败', e);
    }
  }

  build() {
    Column() {
      Text('记一笔')
        .fontSize(24)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 8, bottom: 16 })
        .alignSelf(ItemAlign.Center)

      Scroll() {
        Column() {
          Row() {
            Text('日期：')
              .fontSize(16)
              .fontColor($r('app.color.text_secondary'))
            DatePicker({
              selected: this.selectedDate
            })
              .onChange((value: DatePickerResult) => {
                const year = value.year ?? new Date().getFullYear();
                const month = value.month ?? new Date().getMonth();
                const day = value.day ?? new Date().getDate();
                this.selectedDate = new Date(year, month, day);
              })
              .layoutWeight(1)
          }
          .width('100%')
          .margin({ bottom: 12 })

          TextInput({ placeholder: '用途（如：午餐）' })
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(12)
            .borderColor($r('app.color.border_color'))
            .borderWidth(1)
            .padding({ left: 16, right: 16 })
            .height(44)
            .fontSize(15)
            .onChange((val: string) => { this.inputName = val; })
            .margin({ bottom: 12 })

          TextInput({ placeholder: '金额' })
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(12)
            .borderColor($r('app.color.border_color'))
            .borderWidth(1)
            .padding({ left: 16, right: 16 })
            .height(44)
            .fontSize(15)
            .type(InputType.Number)
            .onChange((val: string) => { this.inputAmount = val; })
            .margin({ bottom: 12 })

          // 分类
          Column() {
            Text('分类')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .alignSelf(ItemAlign.Start)
              .margin({ bottom: 8 })

            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.categories, (cat: string) => {
                Button(cat)
                  .type(ButtonType.Capsule)
                  .backgroundColor(this.selectedCategory === cat ? getCategoryColor(cat) : $r('app.color.category_btn_bg'))
                  .fontColor(this.selectedCategory === cat ? $r('app.color.text_white') : $r('app.color.text_primary'))
                  .borderColor(this.selectedCategory === cat ? getCategoryColor(cat) : 'transparent')
                  .borderWidth(1)
                  .padding({ left: 14, right: 14 })
                  .height(32)
                  .fontSize(13)
                  .margin({ right: 6, bottom: 6 })
                  .onClick(() => {
                    this.selectedCategory = cat;
                  })
              }, (cat: string) => cat)
            }
            .width('100%')
          }
          .width('100%')
          .margin({ bottom: 12 })

          // 来源
          Column() {
            Text('来源')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .alignSelf(ItemAlign.Start)
              .margin({ bottom: 8 })

            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.sourceList, (source: string) => {
                Button(source)
                  .type(ButtonType.Capsule)
                  .backgroundColor(this.selectedSource === source ? $r('app.color.brand_blue') : $r('app.color.category_btn_bg'))
                  .fontColor(this.selectedSource === source ? $r('app.color.text_white') : $r('app.color.text_primary'))
                  .borderColor(this.selectedSource === source ? $r('app.color.brand_blue') : 'transparent')
                  .borderWidth(1)
                  .padding({ left: 14, right: 14 })
                  .height(32)
                  .fontSize(13)
                  .margin({ right: 6, bottom: 6 })
                  .onClick(() => {
                    this.selectedSource = source;
                  })
              }, (source: string) => source)
            }
            .width('100%')
          }
          .width('100%')
          .margin({ bottom: 12 })

          // 标签
          Column() {
            Text('标签')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .alignSelf(ItemAlign.Start)
              .margin({ bottom: 8 })

            // 标签输入框 + 添加按钮
            Row() {
              TextInput({ placeholder: '输入标签，按回车添加' })
                .fontColor($r('app.color.text_primary'))
                .backgroundColor($r('app.color.card_bg'))
                .borderRadius(12)
                .borderColor($r('app.color.border_color'))
                .borderWidth(1)
                .padding({ left: 16, right: 16 })
                .height(40)
                .fontSize(15)
                .layoutWeight(1)
                .onChange((val: string) => { this.inputTags = val; })
                .onSubmit(() => { this.addTag(this.inputTags); })

              Button('添加')
                .backgroundColor($r('app.color.brand_blue'))
                .fontColor($r('app.color.text_white'))
                .borderRadius(12)
                .height(40)
                .padding({ left: 16, right: 16 })
                .fontSize(14)
                .margin({ left: 8 })
                .onClick(() => { this.addTag(this.inputTags); })
            }
            .width('100%')
            .margin({ bottom: 8 })

            // 已选标签展示
            if (this.selectedTags.length > 0) {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.selectedTags, (tag: string) => {
                  Row() {
                    Text(tag)
                      .fontSize(13)
                      .fontColor($r('app.color.text_primary'))
                    SymbolGlyph($r('sys.symbol.xmark'))
                      .fontSize(12)
                      .fontColor([$r('app.color.text_secondary')])
                      .margin({ left: 4 })
                      .onClick(() => { this.removeTag(tag); })
                  }
                  .padding({ left: 12, right: 10, top: 4, bottom: 4 })
                  .backgroundColor($r('app.color.category_btn_bg'))
                  .borderRadius(12)
                  .margin({ right: 6, bottom: 6 })
                }, (tag: string) => tag)
              }
              .width('100%')
            }

            // 快捷标签（已有标签快速选择）
            if (this.availableTags.length > 0) {
              Text('常用标签')
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .margin({ top: 8, bottom: 4 })
                .alignSelf(ItemAlign.Start)

              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(
                  // ✅ 直接过滤掉已选的标签
                  this.availableTags.filter(tag => !this.selectedTags.includes(tag)),
                  (tag: string) => {
                    Text('#' + tag)
                      .fontSize(12)
                      .fontColor($r('app.color.text_secondary'))
                      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                      .backgroundColor($r('app.color.card_bg'))
                      .borderRadius(12)
                      .border({ width: 1, color: $r('app.color.border_color') })
                      .margin({ right: 6, bottom: 6 })
                      .onClick(() => {
                        this.addTag(tag);
                      })
                  },
                  (tag: string) => tag
                )
              }
              .width('100%')
            }
          }
          .width('100%')
          .margin({ bottom: 12 })

          Row() {
            Button('支出')
              .type(ButtonType.Capsule)
              .backgroundColor(this.selectedType === '支出' ? $r('app.color.expense_red') : Color.Transparent)
              .fontColor(this.selectedType === '支出' ? $r('app.color.text_white') : $r('app.color.expense_red'))
              .borderColor($r('app.color.expense_red'))
              .borderWidth(1.5)
              .padding({ left: 20, right: 20 })
              .height(36)
              .fontSize(14)
              .onClick(() => { this.selectedType = '支出'; })

            Blank()
              .width(24)

            Button('收入')
              .type(ButtonType.Capsule)
              .backgroundColor(this.selectedType === '收入' ? $r('app.color.income_gold') : Color.Transparent)
              .fontColor(this.selectedType === '收入' ? $r('app.color.text_white') : $r('app.color.income_gold'))
              .borderColor($r('app.color.income_gold'))
              .borderWidth(1.5)
              .padding({ left: 20, right: 20 })
              .height(36)
              .fontSize(14)
              .onClick(() => { this.selectedType = '收入'; })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .margin({ bottom: 16 })

          Row() {
            Button('取消')
              .backgroundColor('transparent')
              .fontColor($r('app.color.text_secondary'))
              .borderRadius(20)
              .height(40)
              .fontSize(15)
              .layoutWeight(1)
              .onClick(() => { this.controller.close(); })

            Blank()
              .width(16)

            Button('添加')
              .backgroundColor($r('app.color.brand_blue'))
              .fontColor($r('app.color.text_white'))
              .borderRadius(22)
              .height(44)
              .fontSize(15)
              .layoutWeight(1)
              .onClick(() => {
                this.handleAddBill();
              })
          }
          .width('100%')
        }
        .width('100%')
        .padding({ bottom: 4 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('90%')
    .margin({ top: 80, bottom: 80 })
    .padding(16)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(24)
    .shadow({
      radius: 20,
      color: 'rgba(0, 0, 0, 0.08)',
      offsetX: 0,
      offsetY: 4
    })
  }

  private handleAddBill() {
    if (this.inputName.length === 0 || this.inputAmount.length === 0) {
      promptAction.showToast({ message: '请填写完整信息！', duration: 2000 });
      return;
    }
    const amountNum = parseFloat(this.inputAmount);
    if (isNaN(amountNum) || amountNum <= 0) {
      promptAction.showToast({ message: '金额必须是大于0的数字！', duration: 2000 });
      return;
    }
    this.onAddBill(
      this.inputName,
      amountNum,
      this.selectedType,
      this.selectedDate,
      this.selectedCategory,
      this.selectedSource,
      this.selectedTags
    );
    this.controller.close();
  }
}

// ========== 编辑账单弹窗 ==========
@CustomDialog
struct EditBillDialog {
  controller: CustomDialogController = new CustomDialogController({
    builder: () => {}
  });

  billId: number = 0;
  paramName: string = '';
  paramAmount: string = '';
  paramType: '收入' | '支出' = '支出';
  paramDate: Date = new Date();
  paramCategory: string = '其他';
  paramSource: string = '现金';
  onUpdateBill: (id: number, name: string, amount: number, type: '收入' | '支出', date: Date, category: string, source: string, tags: string[]) => void = () => {};
  paramTags: string[] = [];
  // 当前账本的分类列表（由父组件传入）
  categories: string[] = ['其他'];

  @State internalName: string = '';
  @State internalAmount: string = '';
  @State internalType: '收入' | '支出' = '支出';
  @State internalDate: Date = new Date();
  @State internalCategory: string = '其他';
  @State internalSource: string = '现金';
  @State sourceList: string[] = ['现金', '微信', '支付宝', '银行卡'];
  @State inputTags: string = '';
  @State selectedTags: string[] = [];
  @State availableTags: string[] = [];

  aboutToAppear() {
    this.internalName = this.paramName;
    this.internalAmount = this.paramAmount;
    this.internalType = this.paramType;
    this.internalDate = this.paramDate;
    // 账单原分类若不在当前账本分类中，回退到第一个分类
    if (this.categories.indexOf(this.paramCategory) !== -1) {
      this.internalCategory = this.paramCategory;
    } else if (this.categories.length > 0) {
      this.internalCategory = this.categories[0];
    } else {
      this.internalCategory = '其他';
    }
    this.internalSource = this.paramSource || '现金';
    this.selectedTags = this.paramTags ? [...this.paramTags] : [];
    this.loadSources();
    this.loadTags();
  }

  async loadSources() {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');
      const data = await prefs.get('asset_categories', '[]') as string;
      const parsed = JSON.parse(data) as AssetCategory[];
      if (parsed.length > 0) {
        this.sourceList = parsed.map((item: AssetCategory) => item.name);
        if (!this.sourceList.includes(this.internalSource)) {
          this.internalSource = this.sourceList[0];
        }
      }
    } catch (e) {
      console.error('加载来源失败', e);
    }
  }

  // 在 EditBillDialog 中添加这些方法
  async loadTags() {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');
      const data = await prefs.get('all_tags', '[]') as string;
      console.info('📌 EditBillDialog 加载 all_tags:', data);
      this.availableTags = JSON.parse(data);
    } catch (e) {
      console.error('加载标签失败', e);
    }
  }

  async addTag(tag: string) {
    const trimmed = tag.trim();
    if (trimmed.length === 0) return;
    if (this.selectedTags.includes(trimmed)) {
      promptAction.showToast({ message: '标签已存在', duration: 1000 });
      return;
    }
    this.selectedTags = [...this.selectedTags, trimmed];
    this.inputTags = '';

    // ✅ 如果新标签不在可用列表中，添加到可用列表并持久化
    if (!this.availableTags.includes(trimmed)) {
      this.availableTags = [...this.availableTags, trimmed];
      try {
        const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
        const prefs = await dataPreferences.getPreferences(context, 'bill_data');
        await prefs.put('all_tags', JSON.stringify(this.availableTags));
        await prefs.flush();
      } catch (e) {
        console.error('保存标签失败', e);
      }
    }
  }

  removeTag(tag: string) {
    this.selectedTags = this.selectedTags.filter(t => t !== tag);
  }

  build() {
    Column() {
      Text('编辑账单')
        .fontSize(24)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 8, bottom: 16 })
        .alignSelf(ItemAlign.Center)

      Scroll() {
        Column() {
          Row() {
            Text('日期：')
              .fontSize(16)
              .fontColor($r('app.color.text_secondary'))
            DatePicker({
              selected: this.internalDate
            })
              .onChange((value: DatePickerResult) => {
                const year = value.year ?? new Date().getFullYear();
                const month = value.month ?? new Date().getMonth();
                const day = value.day ?? new Date().getDate();
                this.internalDate = new Date(year, month, day);
              })
              .layoutWeight(1)
          }
          .width('100%')
          .margin({ bottom: 12 })

          TextInput({ placeholder: '用途（如：午餐）', text: this.internalName })
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(12)
            .borderColor($r('app.color.border_color'))
            .borderWidth(1)
            .padding({ left: 16, right: 16 })
            .height(44)
            .fontSize(15)
            .onChange((val: string) => { this.internalName = val; })
            .margin({ bottom: 12 })

          TextInput({ placeholder: '金额', text: this.internalAmount })
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(12)
            .borderColor($r('app.color.border_color'))
            .borderWidth(1)
            .padding({ left: 16, right: 16 })
            .height(44)
            .fontSize(15)
            .type(InputType.Number)
            .onChange((val: string) => { this.internalAmount = val; })
            .margin({ bottom: 12 })

          // 分类
          Column() {
            Text('分类')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .alignSelf(ItemAlign.Start)
              .margin({ bottom: 8 })

            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.categories, (cat: string) => {
                Button(cat)
                  .type(ButtonType.Capsule)
                  .backgroundColor(this.internalCategory === cat ? getCategoryColor(cat) : $r('app.color.category_btn_bg'))
                  .fontColor(this.internalCategory === cat ? $r('app.color.text_white') : $r('app.color.text_primary'))
                  .borderColor(this.internalCategory === cat ? getCategoryColor(cat) : 'transparent')
                  .borderWidth(1)
                  .padding({ left: 14, right: 14 })
                  .height(32)
                  .fontSize(13)
                  .margin({ right: 6, bottom: 6 })
                  .onClick(() => {
                    this.internalCategory = cat;
                  })
              }, (cat: string) => cat)
            }
            .width('100%')
          }
          .width('100%')
          .margin({ bottom: 12 })

          // 来源
          Column() {
            Text('来源')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .alignSelf(ItemAlign.Start)
              .margin({ bottom: 8 })

            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.sourceList, (source: string) => {
                Button(source)
                  .type(ButtonType.Capsule)
                  .backgroundColor(this.internalSource === source ? $r('app.color.brand_blue') : $r('app.color.category_btn_bg'))
                  .fontColor(this.internalSource === source ? $r('app.color.text_white') : $r('app.color.text_primary'))
                  .borderColor(this.internalSource === source ? $r('app.color.brand_blue') : 'transparent')
                  .borderWidth(1)
                  .padding({ left: 14, right: 14 })
                  .height(32)
                  .fontSize(13)
                  .margin({ right: 6, bottom: 6 })
                  .onClick(() => {
                    this.internalSource = source;
                  })
              }, (source: string) => source)
            }
            .width('100%')
          }
          Column() {
            Text('标签')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .alignSelf(ItemAlign.Start)
              .margin({ bottom: 8 })

            // 标签输入框 + 添加按钮
            Row() {
              TextInput({ placeholder: '输入标签，按回车添加' })
                .fontColor($r('app.color.text_primary'))
                .backgroundColor($r('app.color.card_bg'))
                .borderRadius(12)
                .borderColor($r('app.color.border_color'))
                .borderWidth(1)
                .padding({ left: 16, right: 16 })
                .height(40)
                .fontSize(15)
                .layoutWeight(1)
                .onChange((val: string) => { this.inputTags = val; })
                .onSubmit(() => { this.addTag(this.inputTags); })

              Button('添加')
                .backgroundColor($r('app.color.brand_blue'))
                .fontColor($r('app.color.text_white'))
                .borderRadius(12)
                .height(40)
                .padding({ left: 16, right: 16 })
                .fontSize(14)
                .margin({ left: 8 })
                .onClick(() => { this.addTag(this.inputTags); })
            }
            .width('100%')
            .margin({ bottom: 8 })

            // 已选标签展示
            if (this.selectedTags.length > 0) {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.selectedTags, (tag: string) => {
                  Row() {
                    Text(tag)
                      .fontSize(13)
                      .fontColor($r('app.color.text_primary'))
                    SymbolGlyph($r('sys.symbol.xmark'))
                      .fontSize(12)
                      .fontColor([$r('app.color.text_secondary')])
                      .margin({ left: 4 })
                      .onClick(() => { this.removeTag(tag); })
                  }
                  .padding({ left: 12, right: 10, top: 4, bottom: 4 })
                  .backgroundColor($r('app.color.category_btn_bg'))
                  .borderRadius(12)
                  .margin({ right: 6, bottom: 6 })
                }, (tag: string) => tag)
              }
              .width('100%')
            }

            // 快捷标签
            if (this.availableTags.length > 0) {
              Text('常用标签')
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .margin({ top: 8, bottom: 4 })
                .alignSelf(ItemAlign.Start)

              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(
                  this.availableTags.filter(tag => !this.selectedTags.includes(tag)),
                  (tag: string) => {
                    Text('#' + tag)
                      .fontSize(12)
                      .fontColor($r('app.color.text_secondary'))
                      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                      .backgroundColor($r('app.color.card_bg'))
                      .borderRadius(12)
                      .border({ width: 1, color: $r('app.color.border_color') })
                      .margin({ right: 6, bottom: 6 })
                      .onClick(() => { this.addTag(tag); })
                  },
                  (tag: string) => tag
                )
              }
              .width('100%')
            }
          }
          .width('100%')
          .margin({ bottom: 12 })

          Row() {
            Button('支出')
              .type(ButtonType.Capsule)
              .backgroundColor(this.internalType === '支出' ? $r('app.color.expense_red') : Color.Transparent)
              .fontColor(this.internalType === '支出' ? $r('app.color.text_white') : $r('app.color.expense_red'))
              .borderColor($r('app.color.expense_red'))
              .borderWidth(1.5)
              .padding({ left: 20, right: 20 })
              .height(36)
              .fontSize(14)
              .onClick(() => { this.internalType = '支出'; })

            Blank()
              .width(24)

            Button('收入')
              .type(ButtonType.Capsule)
              .backgroundColor(this.internalType === '收入' ? $r('app.color.income_gold') : Color.Transparent)
              .fontColor(this.internalType === '收入' ? $r('app.color.text_white') : $r('app.color.income_gold'))
              .borderColor($r('app.color.income_gold'))
              .borderWidth(1.5)
              .padding({ left: 20, right: 20 })
              .height(36)
              .fontSize(14)
              .onClick(() => { this.internalType = '收入'; })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .margin({ bottom: 16 })

          Row() {
            Button('取消')
              .backgroundColor('transparent')
              .fontColor($r('app.color.text_secondary'))
              .borderRadius(20)
              .height(40)
              .fontSize(15)
              .layoutWeight(1)
              .onClick(() => { this.controller.close(); })

            Blank()
              .width(16)

            Button('保存')
              .backgroundColor($r('app.color.brand_blue'))
              .fontColor($r('app.color.text_white'))
              .borderRadius(22)
              .height(44)
              .fontSize(15)
              .layoutWeight(1)
              .onClick(() => {
                this.handleUpdateBill();
              })
          }
          .width('100%')
        }
        .width('100%')
        .padding({ bottom: 4 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('88%')
    .margin({ top: 80, bottom: 80 })
    .padding(16)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(20)
    .shadow({
      radius: 16,
      color: 'rgba(0, 0, 0, 0.06)',
      offsetX: 0,
      offsetY: 2
    })
  }

  private handleUpdateBill() {
    console.info('📌 handleUpdateBill selectedTags:', this.selectedTags);
    if (this.internalName.length === 0 || this.internalAmount.length === 0) {
      promptAction.showToast({ message: '请填写完整信息！', duration: 2000 });
      return;
    }
    const amountNum = parseFloat(this.internalAmount);
    if (isNaN(amountNum) || amountNum <= 0) {
      promptAction.showToast({ message: '金额必须是大于0的数字！', duration: 2000 });
      return;
    }
    this.onUpdateBill(
      this.billId,
      this.internalName,
      amountNum,
      this.internalType,
      this.internalDate,
      this.internalCategory,
      this.internalSource,
      this.selectedTags  // ✅ 传入标签
    );
    this.controller.close();
  }
}

// ========== 搜索账单弹窗 ==========
@CustomDialog
struct SearchBillDialog {
  controller: CustomDialogController = new CustomDialogController({
    builder: () => {}
  });
  @State searchText: string = '';
  bills: BillItem[] = [];
  onSelectBill?: (bill: BillItem) => void;
  onClose?: () => void;

  getFilteredBills(): BillItem[] {
    if (this.searchText.trim().length === 0) {
      return this.bills;
    }
    const keyword = this.searchText.trim().toLowerCase();
    return this.bills.filter(item =>
    item.name.toLowerCase().includes(keyword) ||
      item.category.toLowerCase().includes(keyword)
    );
  }


  build() {
    Column() {
      Row() {
        Text('搜索账单')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))

        Blank()

        Image($r('sys.media.ohos_ic_public_close'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.text_secondary'))
          .onClick(() => {
            this.controller.close();
            if (this.onClose) {
              this.onClose();
            }
          })
      }
      .width('100%')
      .margin({ top: 4, bottom: 12 })

      TextInput({ placeholder: '输入用途或分类关键词' })
        .width('100%')
        .height(44)
        .fontSize(16)
        .borderRadius(12)
        .backgroundColor($r('app.color.card_bg'))
        .borderColor($r('app.color.border_color'))
        .borderWidth(1)
        .padding({ left: 16, right: 16 })
        .onChange((val: string) => {
          this.searchText = val;
        })
        .margin({ bottom: 12 })

      Row() {
        Text(this.searchText.trim().length > 0 ?
          `共 ${this.getFilteredBills().length} 条结果` :
          `共 ${this.bills.length} 笔账单`)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .margin({ bottom: 12 })

      List() {
        ForEach(
          this.getFilteredBills(),
          (item: BillItem) => {
            ListItem() {
              Row() {
                Column() { }
                .width(8)
                .height(8)
                .borderRadius(4)
                .backgroundColor(getCategoryColor(item.category))
                .margin({ right: 12 })

                Text(item.type)
                  .fontSize(12)
                  .backgroundColor(item.type === '收入' ? $r('app.color.income_tag_bg') : $r('app.color.expense_tag_bg'))
                  .fontColor(item.type === '收入' ? $r('app.color.income_tag_text') : $r('app.color.expense_tag_text'))
                  .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                  .borderRadius(6)

                Text(item.name)
                  .fontSize(16)
                  .fontColor($r('app.color.text_primary'))
                  .layoutWeight(1)
                  .margin({ left: 10 })

                Text((item.type === '收入' ? '+' : '-') + item.amount.toFixed(2))
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(item.type === '收入' ? $r('app.color.income_gold') : $r('app.color.expense_red'))
              }
              .width('100%')
              .padding({ top: 12, left: 16, bottom: 12, right: 8 })
              .backgroundColor($r('app.color.card_bg'))
              .borderRadius(12)
              .margin({ bottom: 8 })
            }
            .onClick(() => {
              if (this.onSelectBill) {
                this.onSelectBill(item);
              }
              this.controller.close();
            })
          },
          (item: BillItem) => item.id.toString()
        )
      }
      .width('100%')
      .height('100%')
      .layoutWeight(1)
      .backgroundColor(Color.Transparent)
    }
    .width('90%')
    .margin({ top: 60, bottom: 60 })
    .padding(16)
    .backgroundColor($r('app.color.bg_main'))
    .borderRadius(20)
  }
}

// ========== 账单详情弹窗 ==========
@CustomDialog
struct BillDetailDialog {
  controller: CustomDialogController = new CustomDialogController({
    builder: () => {}
  });
  bill: BillItem = {
    id: 0,
    name: '',
    amount: 0,
    type: '支出',
    date: Date.now(),
    category: '其他',
    source: '现金'
  };
  onEdit?: (bill: BillItem) => void;

  formatDate(timestamp: number): string {
    const d = new Date(timestamp);
    return d.getFullYear() + '年' + (d.getMonth() + 1) + '月' + d.getDate() + '日';
  }

  build() {
    Column() {
      Row() {
        Text('账单详情')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))

        Blank()

        Image($r('sys.media.ohos_ic_public_close'))
          .width(22)
          .height(22)
          .fillColor($r('app.color.text_secondary'))
          .onClick(() => { this.controller.close(); })
      }
      .width('100%')
      .margin({ bottom: 16 })

      Text(this.bill.name)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .alignSelf(ItemAlign.Start)
        .margin({ bottom: 4 })

      Row() {
        Row() {
          Column()
            .width(8)
            .height(8)
            .borderRadius(4)
            .backgroundColor(getCategoryColor(this.bill.category))
            .margin({ right: 6 })
          Text(this.bill.category)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }

        Text('·')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .margin({ left: 8, right: 8 })

        Text(this.bill.type)
          .fontSize(14)
          .fontColor(this.bill.type === '收入' ? $r('app.color.income_gold') : $r('app.color.expense_red'))

        Text('·')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .margin({ left: 8, right: 8 })

        Text(this.bill.source || '未指定')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      }
      .alignSelf(ItemAlign.Start)
      .margin({ bottom: 16 })

      Text((this.bill.type === '收入' ? '+' : '-') + '¥' + this.bill.amount.toFixed(2))
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.bill.type === '收入' ? $r('app.color.income_gold') : $r('app.color.expense_red'))
        .alignSelf(ItemAlign.End)
        .margin({ bottom: 4 })

      Text(this.formatDate(this.bill.date))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .alignSelf(ItemAlign.End)
        .margin({ bottom: 20 })

      Button('编辑')
        .width('100%')
        .height(40)
        .backgroundColor($r('app.color.brand_blue'))
        .fontColor($r('app.color.text_white'))
        .borderRadius(20)
        .fontSize(15)
        .onClick(() => {
          this.controller.close();
          if (this.onEdit) {
            this.onEdit(this.bill);
          }
        })
    }
    .width('80%')
    .padding(20)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(20)
  }
}

// ========== 每日支出详情弹窗 ==========
@CustomDialog
struct DayDetailDialog {
  controller: CustomDialogController = new CustomDialogController({
    builder: () => {}
  });
  day: number = 1;
  month: number = 1;
  year: number = 2026;
  bills: BillItem[] = [];
  total: number = 0;
  onClose?: () => void;

  build() {
    Column() {
      Text(`${this.year}年${this.month}月${this.day}日 支出明细`)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .alignSelf(ItemAlign.Start)
        .margin({ bottom: 12 })

      Text(`合计：¥${this.total.toFixed(2)}`)
        .fontSize(16)
        .fontColor($r('app.color.expense_red'))
        .alignSelf(ItemAlign.Start)
        .margin({ bottom: 16 })

      List() {
        ForEach(this.bills, (item: BillItem) => {
          ListItem() {
            Row() {
              Column() { }
              .width(6)
              .height(6)
              .borderRadius(3)
              .backgroundColor(getCategoryColor(item.category))
              .margin({ right: 10 })

              Text(item.category)
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
                .margin({ right: 10 })

              Text(item.name)
                .fontSize(16)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)

              Text('¥' + item.amount.toFixed(2))
                .fontSize(16)
                .fontColor($r('app.color.expense_red'))
            }
            .width('100%')
            .padding({ top: 8, bottom: 8 })
            .borderRadius(8)
          }
        }, (item: BillItem) => item.id.toString())
      }
      .width('100%')
      .height(200)
      .backgroundColor(Color.Transparent)

      Button('关闭')
        .width('100%')
        .height(40)
        .backgroundColor($r('app.color.brand_blue'))
        .fontColor($r('app.color.text_white'))
        .borderRadius(20)
        .fontSize(15)
        .margin({ top: 12 })
        .onClick(() => {
          if (this.controller) {
            this.controller.close();
          } else if (this.onClose) {
            this.onClose();
          }
        })
    }
    .width('85%')
    .padding(20)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(20)
  }
}


// ========== 多日支出详情弹窗 ==========
@CustomDialog
struct MultiDayDetailDialog {
  controller: CustomDialogController = new CustomDialogController({
    builder: () => {}
  });
  dateRange: string = '';
  bills: BillItem[] = [];
  total: number = 0;
  onClose?: () => void;

  @State groupedDays: number[] = [];
  @State groupedBills: Record<string, BillItem[]> = {};

  aboutToAppear() {
    const grouped: Record<string, BillItem[]> = {};
    this.bills.forEach((bill: BillItem) => {
      const d = new Date(bill.date);
      const day = d.getDate().toString();
      if (!grouped[day]) {
        grouped[day] = [];
      }
      grouped[day].push(bill);
    });
    this.groupedBills = grouped;
    const keys: string[] = Object.keys(grouped);
    keys.sort((a: string, b: string) => parseInt(a) - parseInt(b));
    this.groupedDays = keys.map((k: string) => parseInt(k));
  }

  build() {
    Column() {
      Text(`${this.dateRange} 支出明细`)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .alignSelf(ItemAlign.Start)
        .margin({ bottom: 8 })

      Text(`合计：¥${this.total.toFixed(2)}`)
        .fontSize(16)
        .fontColor($r('app.color.expense_red'))
        .alignSelf(ItemAlign.Start)
        .margin({ bottom: 16 })

      List() {
        ForEach(this.groupedDays, (day: number) => {
          ListItem() {
            Column() {
              Row() {
                Text(`${day}日`)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_secondary'))
                  .margin({ bottom: 6 })
              }
              .width('100%')
              .alignSelf(ItemAlign.Start)

              ForEach(this.groupedBills[day.toString()] || [], (item: BillItem) => {
                Row() {
                  Column() { }
                  .width(6)
                  .height(6)
                  .borderRadius(3)
                  .backgroundColor(getCategoryColor(item.category))
                  .margin({ right: 10 })

                  Text(item.category)
                    .fontSize(14)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ right: 10 })

                  Text(item.name)
                    .fontSize(16)
                    .fontColor($r('app.color.text_primary'))
                    .layoutWeight(1)

                  Text('¥' + item.amount.toFixed(2))
                    .fontSize(16)
                    .fontColor($r('app.color.expense_red'))
                }
                .width('100%')
                .padding({ top: 6, bottom: 6 })
                .borderRadius(8)
              }, (item: BillItem) => item.id.toString())
            }
            .width('100%')
            .padding({ top: 8, bottom: 8 })
          }
        }, (day: number) => day.toString())
      }
      .width('100%')
      .height(220)
      .backgroundColor(Color.Transparent)

      Button('关闭')
        .width('100%')
        .height(40)
        .backgroundColor($r('app.color.brand_blue'))
        .fontColor($r('app.color.text_white'))
        .borderRadius(20)
        .fontSize(15)
        .margin({ top: 12 })
        .onClick(() => {
          try {
            if (this.controller) {
              this.controller.close();
            }
          } catch (e) {
            console.error('controller.close 失败', e);
          }
          if (this.onClose) {
            this.onClose();
          }
        })
    }
    .width('85%')
    .padding(20)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(20)
  }
}

// ========== 导出确认弹窗 ==========
@CustomDialog
struct ExportConfirmDialog {
  controller: CustomDialogController = new CustomDialogController({
    builder: () => {}
  });
  onExport: (type: 'currentMonth' | 'all') => void = () => {};

  build() {
    Column() {
      Text('导出账单')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .alignSelf(ItemAlign.Start)
        .margin({ bottom: 16 })

      Text('请选择要导出的数据范围：')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .alignSelf(ItemAlign.Start)
        .margin({ bottom: 16 })

      Row() {
        Button('导出当月账单')
          .backgroundColor($r('app.color.brand_blue'))
          .fontColor($r('app.color.text_white'))
          .borderRadius(20)
          .height(40)
          .layoutWeight(1)
          .onClick(() => {
            this.controller.close();
            this.onExport('currentMonth');
          })

        Blank()
          .width(16)

        Button('导出全部账单')
          .backgroundColor($r('app.color.category_btn_bg'))
          .fontColor($r('app.color.text_primary'))
          .borderColor($r('app.color.border_color'))
          .borderWidth(1)
          .borderRadius(20)
          .height(40)
          .layoutWeight(1)
          .onClick(() => {
            this.controller.close();
            this.onExport('all');
          })
      }
      .width('100%')

      Button('取消')
        .backgroundColor(Color.Transparent)
        .fontColor($r('app.color.text_secondary'))
        .borderRadius(20)
        .height(36)
        .width('100%')
        .margin({ top: 12 })
        .onClick(() => { this.controller.close(); })
    }
    .width('85%')
    .padding(20)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(20)
  }
}

// ========== 设置预算弹窗 ==========
@CustomDialog
struct SetBudgetDialog {
  controller: CustomDialogController = new CustomDialogController({
    builder: () => {}
  });
  @State inputAmount: string = '';
  currentBudget: number = 0;
  onConfirm: (amount: number) => void = () => {};

  build() {
    Column() {
      Text('设置月度预算')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .alignSelf(ItemAlign.Start)
        .margin({ bottom: 8 })

      Text(`当前月份：${new Date().getFullYear()}年${new Date().getMonth() + 1}月`)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .alignSelf(ItemAlign.Start)
        .margin({ bottom: 16 })

      Row() {
        Text('¥')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ right: 8 })

        TextInput({ placeholder: '输入每月预算金额' })
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius(12)
          .borderColor($r('app.color.border_color'))
          .borderWidth(1)
          .padding({ left: 16, right: 16 })
          .height(48)
          .fontSize(16)
          .type(InputType.Number)
          .onChange((val: string) => { this.inputAmount = val; })
          .layoutWeight(1)
      }
      .width('100%')
      .margin({ bottom: 24 })

      Row() {
        Button('取消')
          .backgroundColor('transparent')
          .fontColor($r('app.color.text_secondary'))
          .borderRadius(20)
          .height(40)
          .layoutWeight(1)
          .onClick(() => { this.controller.close(); })

        Blank()
          .width(16)

        Button('保存')
          .backgroundColor($r('app.color.brand_blue'))
          .fontColor($r('app.color.text_white'))
          .borderRadius(20)
          .height(40)
          .layoutWeight(1)
          .onClick(() => {
            const amount = parseFloat(this.inputAmount);
            if (isNaN(amount) || amount <= 0) {
              promptAction.showToast({ message: '请输入有效的预算金额', duration: 2000 });
              return;
            }
            this.controller.close();
            this.onConfirm(amount);
          })
      }
      .width('100%')
    }
    .width('85%')
    .padding(20)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(20)
  }
}

// ========== 加载弹窗 ==========
@CustomDialog
struct LoadingDialog {
  controller: CustomDialogController = new CustomDialogController({
    builder: () => {}
  });
  @State message: string = '正在导入...';

  build() {
    Column() {
      LoadingProgress()
        .width(48)
        .height(48)
        .color($r('app.color.text_primary'))
      Text(this.message)
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 16 })
    }
    .width('70%')
    .padding(32)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(20)
    .shadow({
      radius: 16,
      color: 'rgba(0, 0, 0, 0.08)',
      offsetX: 0,
      offsetY: 4
    })
  }
}

// ========== 记账提醒频率弹窗 ==========
@CustomDialog
struct WeekPickerDialog {
  controller: CustomDialogController = new CustomDialogController({
    builder: () => {}
  });
  selectedDays: number[] = [1, 2, 3, 4, 5, 6, 7];
  @State chosenDays: number[] = [];
  onConfirm: (days: number[]) => void = () => {};
  private dayNames: string[] = ['一', '二', '三', '四', '五', '六', '日'];

  aboutToAppear() {
    this.chosenDays = [...this.selectedDays];
  }

  isDayChosen(day: number): boolean {
    return this.chosenDays.indexOf(day) >= 0;
  }

  toggleDay(day: number) {
    const idx = this.chosenDays.indexOf(day);
    if (idx >= 0) {
      this.chosenDays.splice(idx, 1);
    } else {
      this.chosenDays.push(day);
    }
  }

  setQuickPick(days: number[]) {
    this.chosenDays = [...days];
  }

  build() {
    Column() {
      Text('提醒频率')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .alignSelf(ItemAlign.Start)
        .margin({ bottom: 16 })

      // 快捷选项
      Row({ space: 8 }) {
        Text('每天')
          .fontSize(14)
          .fontColor($r('app.color.brand_blue'))
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .borderRadius(16)
          .backgroundColor($r('app.color.card_bg'))
          .border({ width: 1, color: $r('app.color.border_color') })
          .onClick(() => { this.setQuickPick([1, 2, 3, 4, 5, 6, 7]); })

        Text('工作日')
          .fontSize(14)
          .fontColor($r('app.color.brand_blue'))
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .borderRadius(16)
          .backgroundColor($r('app.color.card_bg'))
          .border({ width: 1, color: $r('app.color.border_color') })
          .onClick(() => { this.setQuickPick([1, 2, 3, 4, 5]); })

        Text('周末')
          .fontSize(14)
          .fontColor($r('app.color.brand_blue'))
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .borderRadius(16)
          .backgroundColor($r('app.color.card_bg'))
          .border({ width: 1, color: $r('app.color.border_color') })
          .onClick(() => { this.setQuickPick([6, 7]); })
      }
      .width('100%')
      .margin({ bottom: 16 })

      // 星期选择（周一~周日 = 1~7）
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
        ForEach(this.dayNames, (name: string, index: number) => {
          Text(name)
            .fontSize(15)
            .fontWeight(this.isDayChosen(index + 1) ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.isDayChosen(index + 1) ? $r('app.color.text_white') : $r('app.color.text_secondary'))
            .width(44)
            .height(44)
            .textAlign(TextAlign.Center)
            .borderRadius(22)
            .backgroundColor(this.isDayChosen(index + 1) ? $r('app.color.brand_blue') : $r('app.color.card_bg'))
            .border({ width: 1, color: $r('app.color.border_color') })
            .margin(6)
            .onClick(() => { this.toggleDay(index + 1); })
        }, (name: string) => name)
      }
      .width('100%')
      .margin({ bottom: 24 })

      Row() {
        Button('取消')
          .backgroundColor('transparent')
          .fontColor($r('app.color.text_secondary'))
          .borderRadius(20)
          .height(40)
          .layoutWeight(1)
          .onClick(() => { this.controller.close(); })

        Blank()
          .width(16)

        Button('保存')
          .backgroundColor($r('app.color.brand_blue'))
          .fontColor($r('app.color.text_white'))
          .borderRadius(20)
          .height(40)
          .layoutWeight(1)
          .onClick(() => {
            if (this.chosenDays.length === 0) {
              promptAction.showToast({ message: '请至少选择一天', duration: 1500 });
              return;
            }
            this.controller.close();
            const sorted = [...this.chosenDays].sort((a: number, b: number) => a - b);
            this.onConfirm(sorted);
          })
      }
      .width('100%')
    }
    .width('85%')
    .padding(20)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(20)
  }
}

// ====================================================================
// 主页面
// ====================================================================
export interface BillItem {
  id: number;
  name: string;
  amount: number;
  type: '收入' | '支出';
  date: number;
  category: string;
  source: string;
  tags?: string[];
  ledgerId?: number;  // 所属账本，缺省视为默认账本
}

interface ParsedBillData {
  timeStr: string;
  transType: string;
  counterparty: string;
  name: string;
  typeStr: string;
  amount: number;
}

// 本应用导出 CSV 中的一行账单
interface CsvBillRow {
  date: number;
  type: '收入' | '支出';
  category: string;
  name: string;
  amount: number;
  ledgerName: string;
}

interface ExpenseStat {
  category: string;
  total: number;
  color: string;
}

interface DailyExpenseData {
  day: number;
  amount: number;
}

interface Padding {
  top: number;
  bottom: number;
  left: number;
  right: number;
}
interface BudgetStatus {
  monthlyExpense: number;
  usedPercentForDisplay: number;
  usedPercentForColor: number;
  isOverBudget: boolean;
  remaining: number;
}
interface CubicPoint {
  x: number;
  y: number;
  cp1x: number;
  cp1y: number;
  cp2x: number;
  cp2y: number;
}
interface Point {
  x: number;
  y: number;
}

interface BezierPoint {
  x: number;
  y: number;
  cp1x: number;
  cp1y: number;
  cp2x: number;
  cp2y: number;
}

interface DialogResult {
  index: number;
}


interface BackupData {
  version: string;
  exportTime: string;
  bills: BillItem[];
  assets: AssetCategory[];
  ledgers?: LedgerItem[];  // 旧版本备份无此字段
}

interface DialogButton {
  text: string;
  color: string;
}
// ========== 选择月份弹窗 ==========
@CustomDialog
struct MonthPickerDialog {
  controller: CustomDialogController = new CustomDialogController({
    builder: () => {}
  });
  @State selectedDate: Date = new Date();
  onConfirm?: (year: number, month: number) => void;

  build() {
    Column() {
      Text('选择月份')
        .fontSize(24)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 8, bottom: 16 })
        .alignSelf(ItemAlign.Center)

      DatePicker({
        selected: this.selectedDate,
        start: new Date('2000-1-1'),
        end: new Date('2099-12-31')
      })
        .onChange((value: DatePickerResult) => {
          const year = value.year ?? new Date().getFullYear();
          const month = value.month ?? new Date().getMonth();
          const day = value.day ?? 1;
          this.selectedDate = new Date(year, month, day);
        })
        .margin({ bottom: 16 })

      Row() {
        Button('取消')
          .backgroundColor('transparent')
          .fontColor($r('app.color.text_secondary'))
          .borderRadius(20)
          .height(40)
          .layoutWeight(1)
          .onClick(() => { this.controller.close(); })

        Blank().width(16)

        Button('确定')
          .backgroundColor($r('app.color.brand_blue'))
          .fontColor($r('app.color.text_white'))
          .borderRadius(20)
          .height(40)
          .layoutWeight(1)
          .onClick(() => {
            if (this.onConfirm) {
              const year = this.selectedDate.getFullYear();
              const month = this.selectedDate.getMonth() + 1;
              this.onConfirm(year, month);
            }
            this.controller.close();
          })
      }
      .width('100%')
    }
    .width('90%')
    .padding(16)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(24)
    .shadow({
      radius: 20,
      color: 'rgba(0, 0, 0, 0.08)',
      offsetX: 0,
      offsetY: 4
    })
  }
}

// ========== 账本切换弹层（原生半模态 bindSheet，构建器见 Index.LedgerSheetBuilder） ==========

@Entry
@Component
struct Index {
  @StorageLink('bills') @Watch('onBillsChanged') bills: BillItem[] = [];
  @State currentTabIndex: number = 0;
  // ---------- 多账本状态 ----------
  @State ledgers: LedgerItem[] = [];
  @State currentLedgerId: number = DEFAULT_LEDGER_ID;
  @State ledgerBills: BillItem[] = [];  // 当前账本过滤后的账单（供日历 Tab 绑定）
  @State currentYear: number = new Date().getFullYear();
  @State currentMonth: number = new Date().getMonth() + 1;
  @State billViewYear: number = new Date().getFullYear();
  @State billViewMonth: number = new Date().getMonth() + 1;
  @State refreshKey: number = 0;
  @State budget: number = 0;
  @State hasBudget: boolean = false;
  @State billFilterCategory: string = '全部';
  @State statYear: number = new Date().getFullYear();
  @State yearCanvasWidth: number = 400;
  @State manualBtnScale: number = 1;
  @State totalAsset: number = 0;
  @State isDarkMode: boolean = false;
  @State isReminderOn: boolean = false;
  @State reminderHour: number = 20;
  @State reminderMinute: number = 30;
  @State reminderDays: number[] = [1, 2, 3, 4, 5, 6, 7];
  @StorageLink('currentColorMode')
  @Watch('onColorModeChanged')
  currentColorMode: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @State userTheme: string = 'system';  // 'light' | 'dark' | 'system'
  @State billFilterTag: string = '';  // 筛选的标签，空字符串表示全部
  @State statContentOpacity: number = 1;
  @State statContentScale: number = 1;
  @State pressedBillId: number = -1;
  @State pressedFunc: string = '';
  @State pressedCard: string = '';
  // 账本切换半模态弹层显隐
  @State showLedgerSheet: boolean = false;

  private dialogController: CustomDialogController | null = null;
  private editDialogController: CustomDialogController | null = null;
  private searchDialogController: CustomDialogController | null = null;
  private detailDialogController: CustomDialogController | null = null;
  private exportDialogController: CustomDialogController | null = null;
  private setBudgetDialogController: CustomDialogController | null = null;
  private colorPalette: string[] = [
    '#FF6B6B', '#4ECDC4', '#45B7D1', '#FFA94D', '#A29BFE',
    '#FD79A8', '#00B894', '#E17055', '#6C5CE7', '#FDCB6E',
    '#00CEC9', '#D63031', '#0984E3', '#F368E0', '#FF9FF3'
  ];
  private canvasCtx: CanvasRenderingContext2D | null = null;
  private trendCanvasCtx: CanvasRenderingContext2D | null = null;
  private yearCanvasCtx: CanvasRenderingContext2D | null = null;
  private trendCanvasWidth: number = 400;
  private monthPickerController: CustomDialogController | null = null;
  private loadingDialogController: CustomDialogController | null = null;
  private reminderWeekDialogController: CustomDialogController | null = null;
  private reminderBusy: boolean = false;
  private isLoading: boolean = false;
  private itemTransitionEffect: TransitionEffect =
    TransitionEffect.OPACITY
      .combine(TransitionEffect.scale({ x: 0.82, y: 0.82 }))
      .animation({ curve: AnimationConfig.SPRING });
  private dialogOpenAnimation: AnimateParam = {
    duration: 400,
    curve: AnimationConfig.SPRING_SOFT,
  };
  private dialogCloseAnimation: AnimateParam = {
    duration: 280,
    curve: AnimationConfig.SPRING_SOFT,
  };
  // 账本切换弹窗：原生底部上滑动画（短时长）
  private lastRefreshFlag: number = 0;
  private lastLedgerRefreshFlag: number = 0;


  // 从 Preferences 加载账单数据
  async loadBillsFromPreferences() {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (!context) {
        console.error('❌ context 为空，无法加载账单');
        return;
      }
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');
      const data = await prefs.get('bills_key', '[]') as string;
      const parsed = JSON.parse(data) as BillItem[];
      if (parsed && parsed.length > 0) {
        this.bills = parsed;
        console.info('✅ 从 Preferences 加载了 ' + parsed.length + ' 条账单');
      } else {
        console.info('📭 Preferences 中没有账单数据');
      }
    } catch (e) {
      console.error('❌ 从 Preferences 加载失败: ' + JSON.stringify(e));
    }
  }

  // 保存账单数据到 Preferences
  async saveBillsToPreferences() {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (!context) {
        console.error('❌ context 为空，无法保存账单');
        return;
      }
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');
      await prefs.put('bills_key', JSON.stringify(this.bills));
      await prefs.flush();
      console.info('✅ 账单已保存到 Preferences，共 ' + this.bills.length + ' 条');
    } catch (e) {
      console.error('❌ 保存到 Preferences 失败: ' + JSON.stringify(e));
    }
  }

  // ---------- 多账本：数据初始化 ----------
  async initLedgerData(): Promise<void> {
    await this.loadBillsFromPreferences();
    await this.ensureLedgerMigration();
    await this.loadLedgerState();
    this.updateLedgerBills();
    await this.loadBudget();
  }

  // 账本数据迁移（幂等）：初始化默认账本 / 旧账单补 ledgerId / 旧预算键加前缀
  async ensureLedgerMigration(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (!context) {
        return;
      }
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');

      // 1. 账本列表初始化：确保存在默认账本
      const ledgersData = await prefs.get('ledgers_key', '') as string;
      let ledgers: LedgerItem[] = [];
      if (ledgersData) {
        ledgers = JSON.parse(ledgersData) as LedgerItem[];
      }
      const hasDefault = ledgers.some((item: LedgerItem) => item.isDefault);
      if (!hasDefault) {
        const defaultLedger: LedgerItem = {
          id: DEFAULT_LEDGER_ID,
          name: '默认账本',
          icon: 'book',
          color: '#45B7D1',
          categories: [...CATEGORIES],
          createdAt: Date.now(),
          isDefault: true
        };
        ledgers = [defaultLedger, ...ledgers];
        await prefs.put('ledgers_key', JSON.stringify(ledgers));
      }

      // 2. 旧账单补 ledgerId
      let billsChanged = false;
      this.bills.forEach((item: BillItem) => {
        if (item.ledgerId === undefined) {
          item.ledgerId = DEFAULT_LEDGER_ID;
          billsChanged = true;
        }
      });
      if (billsChanged) {
        await prefs.put('bills_key', JSON.stringify(this.bills));
      }

      // 3. 旧预算键迁移：'YYYY-MM' -> '1:YYYY-MM'
      const budgetData = await prefs.get('budget', '') as string;
      if (budgetData) {
        const parsed = JSON.parse(budgetData) as Record<string, number>;
        const migrated: Record<string, number> = {};
        let changed = false;
        Object.keys(parsed).forEach((key: string) => {
          if (key.indexOf(':') === -1) {
            changed = true;
            migrated[`${DEFAULT_LEDGER_ID}:${key}`] = parsed[key];
          } else {
            migrated[key] = parsed[key];
          }
        });
        if (changed) {
          await prefs.put('budget', JSON.stringify(migrated));
        }
      }
      await prefs.flush();
    } catch (e) {
      console.error('账本数据迁移失败: ' + JSON.stringify(e));
    }
  }

  // 加载账本列表与当前选中账本
  async loadLedgerState(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (!context) {
        return;
      }
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');
      const ledgersData = await prefs.get('ledgers_key', '[]') as string;
      const parsed = JSON.parse(ledgersData) as LedgerItem[];
      if (parsed.length > 0) {
        this.ledgers = parsed;
      }
      const currentIdStr = await prefs.get('current_ledger_id', '') as string;
      let targetId: number = DEFAULT_LEDGER_ID;
      if (currentIdStr) {
        const id = Number(currentIdStr);
        if (!isNaN(id) && this.ledgers.some((item: LedgerItem) => item.id === id)) {
          targetId = id;
        }
      }
      if (!this.ledgers.some((item: LedgerItem) => item.id === targetId)) {
        targetId = DEFAULT_LEDGER_ID;
      }
      this.currentLedgerId = targetId;
    } catch (e) {
      console.error('加载账本状态失败: ' + JSON.stringify(e));
    }
  }

  async saveCurrentLedgerId(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (!context) {
        return;
      }
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');
      await prefs.put('current_ledger_id', this.currentLedgerId.toString());
      await prefs.flush();
    } catch (e) {
      console.error('保存当前账本失败: ' + JSON.stringify(e));
    }
  }

  getCurrentLedger(): LedgerItem {
    const found = this.ledgers.find((item: LedgerItem) => item.id === this.currentLedgerId);
    if (found !== undefined) {
      return found;
    }
    const fallback: LedgerItem = {
      id: DEFAULT_LEDGER_ID,
      name: '默认账本',
      icon: 'book',
      color: '#45B7D1',
      categories: [...CATEGORIES],
      createdAt: 0,
      isDefault: true
    };
    return fallback;
  }

  getCurrentLedgerCategories(): string[] {
    const ledger = this.getCurrentLedger();
    if (ledger.categories.length > 0) {
      return ledger.categories;
    }
    return [...CATEGORIES];
  }

  getLedgerCategoriesById(id: number): string[] {
    const found = this.ledgers.find((item: LedgerItem) => item.id === id);
    if (found !== undefined && found.categories.length > 0) {
      return found.categories;
    }
    return [...CATEGORIES];
  }

  getLedgerNameById(id: number | undefined): string {
    const lid = id ?? DEFAULT_LEDGER_ID;
    const found = this.ledgers.find((item: LedgerItem) => item.id === lid);
    if (found !== undefined) {
      return found.name;
    }
    return '默认账本';
  }

  // 重算当前账本的账单集合
  updateLedgerBills(): void {
    this.ledgerBills = this.bills.filter((item: BillItem) =>
      (item.ledgerId ?? DEFAULT_LEDGER_ID) === this.currentLedgerId);
  }

  onBillsChanged(): void {
    this.updateLedgerBills();
  }

  switchLedger(id: number): void {
    if (id === this.currentLedgerId) {
      return;
    }
    animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
      this.currentLedgerId = id;
    });
    this.saveCurrentLedgerId();
    if (this.billFilterCategory !== '全部' &&
      this.getCurrentLedgerCategories().indexOf(this.billFilterCategory) === -1) {
      this.billFilterCategory = '全部';
    }
    this.updateLedgerBills();
    this.loadBudget();
    this.refreshKey++;
    this.updateChartIfNeeded();
  }

  openLedgerSwitchDialog() {
    // 使用原生半模态弹层（底部上滑动画）
    this.showLedgerSheet = true;
  }

  // 加载预算
  async loadBudget() {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (!context) {
        console.error('❌ context 为空，无法加载预算');
        return;
      }
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');
      const data = await prefs.get('budget', '') as string;
      if (data) {
        const parsed = JSON.parse(data) as Record<string, number>;
        const ym = `${this.currentYear}-${String(this.currentMonth).padStart(2, '0')}`;
        const key = `${this.currentLedgerId}:${ym}`;
        const legacyKey = `${ym}`;
        let value: number | undefined = parsed[key];
        if (value === undefined && this.currentLedgerId === DEFAULT_LEDGER_ID) {
          value = parsed[legacyKey];
        }
        if (value !== undefined && value > 0) {
          this.budget = value;
          this.hasBudget = true;
        } else {
          this.budget = 0;
          this.hasBudget = false;
        }
      } else {
        this.budget = 0;
        this.hasBudget = false;
      }
    } catch (e) {
      console.error('加载预算失败: ' + JSON.stringify(e));
      this.budget = 0;
      this.hasBudget = false;
    }
  }

  // 加载总资产
  async loadTotalAsset() {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');
      const data = await prefs.get('asset_categories', '[]') as string;
      const parsed = JSON.parse(data) as AssetCategory[];
      let total = 0;
      for (let item of parsed) {
        total += item.amount;
      }
      this.totalAsset = total;
    } catch (e) {
      console.error('加载总资产失败', e);
      this.totalAsset = 0;
    }
  }

  async loadUserTheme() {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');
      const theme = await prefs.get('user_theme', 'system') as string;
      this.userTheme = theme;
    } catch (e) {
      console.error('加载主题偏好失败', e);
    }
  }

  async saveUserTheme(theme: string) {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');
      await prefs.put('user_theme', theme);
      await prefs.flush();
    } catch (e) {
      console.error('保存主题偏好失败', e);
    }
  }
  onColorModeChanged(): void {
    // 应用生效颜色模式变化（系统切换或 setColorMode 生效）时，同步状态栏
    this.updateSystemBarColor(this.currentColorMode);
  }

  applyTheme(theme: string) {
    let targetMode: ConfigurationConstant.ColorMode;

    if (theme === 'system') {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      // 将 config 转为 Record<string, string> 以访问原始键值
      const config = context.config as Record<string, string> | undefined;
      const systemModeStr = config ? config['0#ohos.system.colorMode'] : '';
      targetMode = systemModeStr === 'dark'
        ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
        : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
      console.info('🌓 系统模式字符串: ' + systemModeStr + ', targetMode: ' + targetMode);
    } else if (theme === 'dark') {
      targetMode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    } else { // 'light' 或默认
      targetMode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    }

    this.updateSystemBarColor(targetMode);
  }

  switchTheme(theme: string) {
    this.userTheme = theme;
    this.saveUserTheme(theme);

    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const appContext = context.getApplicationContext();

    let mode: ConfigurationConstant.ColorMode;
    if (theme === 'dark') {
      mode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    } else if (theme === 'light') {
      mode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    } else {
      mode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    }
    appContext.setColorMode(mode);

    if (mode === ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET) {
      // 跟随系统：setColorMode 异步生效，立即读 config 会拿到旧值。
      // 延迟读取生效后的模式作为兜底；主同步依赖 onColorModeChanged（由 onConfigurationUpdate 驱动）
      setTimeout(() => {
        const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
        const targetMode = (ctx.config && ctx.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK)
          ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
          : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
        this.updateSystemBarColor(targetMode);
      }, 200);
    } else {
      this.updateSystemBarColor(mode);
    }
  }


  async updateSystemBarColor(mode: ConfigurationConstant.ColorMode) {
    const isDark = mode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const win = await window.getLastWindow(context);
      win.setWindowSystemBarProperties({
        statusBarContentColor: isDark ? '#FFFFFF' : '#000000',
        navigationBarContentColor: isDark ? '#FFFFFF' : '#000000'
      });
    } catch (e) {
      console.error('更新系统栏颜色失败', e);
    }
  }
  // 加载资产列表
  async loadAssetList(): Promise<AssetCategory[]> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');
      const data = await prefs.get('asset_categories', '[]') as string;
      const parsed = JSON.parse(data) as AssetCategory[];
      if (parsed.length === 0) {
        // ✅ 添加显式类型注解，修复 ArkTS 错误
        const defaultList: AssetCategory[] = [
          { name: '现金', amount: 0 },
          { name: '微信', amount: 0 },
          { name: '支付宝', amount: 0 },
          { name: '银行卡', amount: 0 }
        ];
        await this.saveAssetList(defaultList);
        return defaultList;
      }
      return parsed;
    } catch (e) {
      console.error('加载资产列表失败', e);
      return [];
    }
  }

  // 保存资产列表
  async saveAssetList(list: AssetCategory[]) {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');
      await prefs.put('asset_categories', JSON.stringify(list));
      await prefs.flush();
    } catch (e) {
      console.error('保存资产列表失败', e);
    }
  }

  // 更新资产余额
  async updateAsset(source: string, type: '收入' | '支出', amount: number, operation: 'add' | 'remove') {
    const list = await this.loadAssetList();
    let item = list.find(i => i.name === source);
    if (!item) {
      item = { name: source, amount: 0 };
      list.push(item);
    }
    const delta = type === '收入' ? amount : -amount;
    item.amount += (operation === 'add' ? delta : -delta);
    if (item.amount < 0) item.amount = 0;
    await this.saveAssetList(list);
    await this.loadTotalAsset();
  }

  // 数据迁移：为旧账单添加 source 字段
  migrateOldBills() {
    let needUpdate = false;
    this.bills.forEach(item => {
      if (!item.source) {
        needUpdate = true;
        item.source = '现金';
      }
    });
    if (needUpdate) {
      this.saveBillsToPreferences();
    }
  }

  // 保存预算
  async saveBudget(amount: number) {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (!context) {
        console.error('❌ context 为空，无法保存预算');
        return;
      }
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');
      const data = await prefs.get('budget', '') as string;
      let parsed: Record<string, number> = {};
      if (data) {
        parsed = JSON.parse(data);
      }
      const key = `${this.currentLedgerId}:${this.currentYear}-${String(this.currentMonth).padStart(2, '0')}`;
      parsed[key] = amount;
      await prefs.put('budget', JSON.stringify(parsed));
      await prefs.flush();
      this.budget = amount;
      this.hasBudget = true;
      console.info('✅ 预算已保存');
    } catch (e) {
      console.error('保存预算失败: ' + JSON.stringify(e));
    }
  }


  async aboutToAppear() {
    console.info('📌 aboutToAppear 开始');

    try {
      PersistentStorage.persistProp('bills', []);
    } catch (e) {
      console.error('❌ PersistentStorage 初始化失败: ' + JSON.stringify(e));
    }

    // ✅ 账本/账单/预算数据初始化（含旧数据迁移到默认账本）
    try {
      this.initLedgerData().then(() => {
        // 迁移旧账单字段（source/tags 等）
        this.migrateOldBills();
        this.migrateOldBillsForTags();
      });
    } catch (e) {
      console.error('❌ initLedgerData 失败: ' + JSON.stringify(e));
    }

    try {
      this.canvasCtx = new CanvasRenderingContext2D();
      this.trendCanvasCtx = new CanvasRenderingContext2D();
      this.yearCanvasCtx = new CanvasRenderingContext2D();
    } catch (e) {
      console.error('❌ Canvas 初始化失败: ' + JSON.stringify(e));
    }

    try {
      this.monthPickerController = new CustomDialogController({
        builder: MonthPickerDialog({
          selectedDate: new Date(this.billViewYear, this.billViewMonth - 1, 1),
          onConfirm: (year: number, month: number) => {
            this.billViewYear = year;
            this.billViewMonth = month;
          }
        }),
        autoCancel: true,
        alignment: DialogAlignment.Center,
        customStyle: true,
        maskColor: 'rgba(0, 0, 0, 0.4)',
        openAnimation: this.dialogOpenAnimation,
        closeAnimation: this.dialogCloseAnimation
      });
    } catch (e) {
      console.error('❌ monthPickerController 初始化失败: ' + JSON.stringify(e));
    }

    try {
      console.info('📌 开始初始化 loadingDialogController');
      this.loadingDialogController = new CustomDialogController({
        builder: LoadingDialog({
          message: '正在导入账单...'
        }),
        autoCancel: false,
        alignment: DialogAlignment.Center,
        customStyle: true,
        maskColor: 'rgba(0, 0, 0, 0.5)',
        openAnimation: this.dialogOpenAnimation,
        closeAnimation: this.dialogCloseAnimation
      });
      console.info('✅ loadingDialogController 初始化成功');
    } catch (e) {
      console.error('❌ loadingDialogController 初始化失败: ' + JSON.stringify(e));
    }

    // ✅ 加载总资产
    this.loadTotalAsset();

    // ✅ 加载用户主题偏好，并通过 setColorMode 应用保存的主题，
    // 保证冷启动时 UI 颜色模式与状态栏一致
    await this.loadUserTheme();
    this.switchTheme(this.userTheme);

    // ✅ 加载记账提醒设置（开关/时间/频率）
    await this.loadReminderSettings();
  }

  // ---------- 工具 ----------
  getFilteredBills(): BillItem[] {
    return this.bills.filter(item => {
      const d = new Date(item.date);
      return (item.ledgerId ?? DEFAULT_LEDGER_ID) === this.currentLedgerId &&
        d.getFullYear() === this.currentYear && (d.getMonth() + 1) === this.currentMonth;
    });
  }

  getBillViewBills(): BillItem[] {
    let filtered = this.bills.filter(item => {
      const d = new Date(item.date);
      return (item.ledgerId ?? DEFAULT_LEDGER_ID) === this.currentLedgerId &&
        d.getFullYear() === this.billViewYear && (d.getMonth() + 1) === this.billViewMonth;
    });

    // 按分类筛选
    if (this.billFilterCategory !== '全部') {
      filtered = filtered.filter(item => item.category === this.billFilterCategory);
    }

    // ✅ 按标签筛选
    if (this.billFilterTag !== '') {
      filtered = filtered.filter(item => item.tags && item.tags.includes(this.billFilterTag));
    }

    return filtered;
  }

  getAllTags(): string[] {
    const tagSet = new Set<string>();
    this.bills.forEach((bill: BillItem) => {
      if (bill.tags) {
        bill.tags.forEach((tag: string) => tagSet.add(tag));
      }
    });
    return Array.from(tagSet).sort();
  }

  getTotal(): number {
    let total = 0;
    for (let item of this.getFilteredBills()) {
      if (item.type === '收入') total += item.amount; else total -= item.amount;
    }
    return total;
  }

  getTotalAllTime(): number {
    let total = 0;
    for (let bill of this.bills) {
      if (bill.type === '收入') total += bill.amount;
      else total -= bill.amount;
    }
    return total;
  }

  getTotalExpense(): number {
    let sum = 0;
    for (let item of this.getFilteredBills()) {
      if (item.type === '支出') sum += item.amount;
    }
    return sum;
  }

  // 显示多日支出详情弹窗
  showMultiDayDetailDialog(days: number[]) {
    const year = this.currentYear;
    const month = this.currentMonth;

    const uniqueDays: number[] = [];
    days.forEach((day: number) => {
      if (uniqueDays.indexOf(day) === -1) {
        uniqueDays.push(day);
      }
    });
    uniqueDays.sort((a, b) => a - b);

    const dayBills: BillItem[] = [];
    this.bills.forEach((bill: BillItem) => {
      const d = new Date(bill.date);
      if ((bill.ledgerId ?? DEFAULT_LEDGER_ID) === this.currentLedgerId &&
        d.getFullYear() === year &&
        (d.getMonth() + 1) === month &&
        uniqueDays.indexOf(d.getDate()) !== -1 &&
        bill.type === '支出') {
        dayBills.push(bill);
      }
    });

    if (dayBills.length === 0) {
      promptAction.showToast({ message: '这些天无支出', duration: 1500 });
      return;
    }

    let total = 0;
    dayBills.forEach((bill: BillItem) => {
      total += bill.amount;
    });

    let dateRange = '';
    if (uniqueDays.length === 1) {
      dateRange = `${year}年${month}月${uniqueDays[0]}日`;
    } else {
      dateRange = `${year}年${month}月${uniqueDays[0]}日 ~ ${uniqueDays[uniqueDays.length - 1]}日`;
    }

    const dialogController = new CustomDialogController({
      builder: MultiDayDetailDialog({
        dateRange: dateRange,
        bills: dayBills,
        total: total,
        onClose: () => {
          if (dialogController) {
            dialogController.close();
          }
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true,
      maskColor: 'rgba(0, 0, 0, 0.4)'
    });
    dialogController.open();
  }

  getExpenseStats(): ExpenseStat[] {
    const map = new Map<string, number>();
    this.getFilteredBills()
      .filter(item => item.type === '支出')
      .forEach(item => {
        const cat = item.category || '其他';
        const current = map.get(cat) || 0;
        map.set(cat, current + item.amount);
      });


    const result: ExpenseStat[] = [];
    map.forEach((total, category) => {
      const color = CATEGORY_COLORS[category] || this.colorPalette[result.length % this.colorPalette.length];
      result.push({ category, total, color });
    });
    result.sort((a, b) => b.total - a.total);
    return result;
  }


  getBudgetStatus(): BudgetStatus {
    const monthlyExpense = this.getTotalExpense();
    const usedPercentForDisplay = this.budget > 0 ? Math.min((monthlyExpense / this.budget) * 100, 100) : 0;
    const usedPercentForColor = this.budget > 0 ? (monthlyExpense / this.budget) * 100 : 0;
    const isOverBudget = monthlyExpense > this.budget;
    const remaining = this.budget - monthlyExpense;
    return {
      monthlyExpense,
      usedPercentForDisplay,
      usedPercentForColor,
      isOverBudget,
      remaining
    };
  }

  getDailyExpenseData(): DailyExpenseData[] {
    const year = this.currentYear;
    const month = this.currentMonth;
    const daysInMonth = new Date(year, month, 0).getDate();

    const dailyData: number[] = new Array(daysInMonth).fill(0);

    for (let bill of this.bills) {
      const d = new Date(bill.date);
      if ((bill.ledgerId ?? DEFAULT_LEDGER_ID) === this.currentLedgerId &&
        d.getFullYear() === year && (d.getMonth() + 1) === month && bill.type === '支出') {
        const day = d.getDate();
        dailyData[day - 1] += bill.amount;
      }
    }

    return dailyData.map((amount, index): DailyExpenseData => ({
      day: index + 1,
      amount: amount
    }));
  }

  getYearlyExpenseData(): number[] {
    const monthlyData: number[] = new Array(12).fill(0);

    this.bills.forEach((bill: BillItem) => {
      const d = new Date(bill.date);
      if ((bill.ledgerId ?? DEFAULT_LEDGER_ID) === this.currentLedgerId &&
        d.getFullYear() === this.statYear && bill.type === '支出') {
        const month = d.getMonth();
        monthlyData[month] += bill.amount;
      }
    });

    return monthlyData;
  }

  // 处理趋势图点击
  handleTrendClick(x: number, y: number) {
    const data = this.getDailyExpenseData();
    const maxAmount = Math.max(...data.map(d => d.amount), 1);
    const canvasWidth = this.trendCanvasWidth || 400;
    const padding: Padding = { top: 24, bottom: 44, left: 36, right: 24 };
    const chartWidth = canvasWidth - padding.left - padding.right;
    const chartHeight = 200 - padding.top - padding.bottom;

    const hitDays: number[] = [];
    for (let i = 0; i < data.length; i++) {
      if (data[i].amount === 0) continue;
      const px = padding.left + (i / (data.length - 1 || 1)) * chartWidth;
      const py = padding.top + chartHeight - (data[i].amount / maxAmount) * chartHeight;
      const distance = Math.sqrt((x - px) ** 2 + (y - py) ** 2);
      if (distance < 45) {
        hitDays.push(i + 1);
      }
    }

    if (hitDays.length === 0) {
      promptAction.showToast({ message: '没有命中数据点', duration: 1500 });
      return;
    }

    this.showMultiDayDetailDialog(hitDays);
  }

  // 显示某天的支出详情弹窗
  showDayDetailDialog(day: number) {
    const year = this.currentYear;
    const month = this.currentMonth;

    const dayBills = this.bills.filter(bill => {
      const d = new Date(bill.date);
      return (bill.ledgerId ?? DEFAULT_LEDGER_ID) === this.currentLedgerId &&
        d.getFullYear() === year &&
        (d.getMonth() + 1) === month &&
        d.getDate() === day &&
        bill.type === '支出';
    });

    if (dayBills.length === 0) {
      promptAction.showToast({ message: '当天无支出', duration: 1500 });
      return;
    }

    const total = dayBills.reduce((sum, b) => sum + b.amount, 0);

    const detailController = new CustomDialogController({
      builder: DayDetailDialog({
        day: day,
        month: month,
        year: year,
        bills: dayBills,
        total: total,
        onClose: () => {
          if (detailController) {
            detailController.close();
          }
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true,
      maskColor: 'rgba(0, 0, 0, 0.4)',
      openAnimation: this.dialogOpenAnimation,
      closeAnimation: this.dialogCloseAnimation
    });
    detailController.open();
  }

  // ---------- 月份切换 ----------
  goPreviousMonth() {
    if (this.statContentOpacity < 0.5) return;

    animateTo({ duration: 120, curve: Curve.EaseIn }, () => {
      this.statContentOpacity = 0;
      this.statContentScale = 0.9;
    });

    setTimeout(() => {
      if (this.currentMonth === 1) {
        this.currentMonth = 12;
        this.currentYear--;
      } else {
        this.currentMonth--;
      }
      this.updateChartIfNeeded();
      this.loadBudget();
      this.refreshKey++;

      animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
        this.statContentOpacity = 1;
        this.statContentScale = 1;
      });
    }, 150);
  }

  goNextMonth() {
    if (this.statContentOpacity < 0.5) return;

    animateTo({ duration: 120, curve: Curve.EaseIn }, () => {
      this.statContentOpacity = 0;
      this.statContentScale = 0.9;
    });

    setTimeout(() => {
      if (this.currentMonth === 12) {
        this.currentMonth = 1;
        this.currentYear++;
      } else {
        this.currentMonth++;
      }
      this.updateChartIfNeeded();
      this.loadBudget();
      this.refreshKey++;

      animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
        this.statContentOpacity = 1;
        this.statContentScale = 1;
      });
    }, 150);
  }

  goBillPrevMonth() {
    if (this.billViewMonth === 1) {
      this.billViewMonth = 12;
      this.billViewYear--;
    } else {
      this.billViewMonth--;
    }
  }

  goBillNextMonth() {
    if (this.billViewMonth === 12) {
      this.billViewMonth = 1;
      this.billViewYear++;
    } else {
      this.billViewMonth++;
    }
  }

  // ---------- 增删改账单 ----------
  addBill(name: string, amount: number, type: '收入' | '支出', date: Date, category: string, source: string, tags?: string[]) {
    const newBill: BillItem = {
      id: Date.now(),
      name: name,
      amount: amount,
      type: type,
      date: date.getTime(),
      category: category || '其他',
      source: source || '现金',
      tags: tags || [],  // ✅ 使用传入的 tags
      ledgerId: this.currentLedgerId  // 记入当前选中账本
    };
    animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
      this.bills = [newBill, ...this.bills];
    });
    const d = new Date(newBill.date);
    if (d.getFullYear() !== this.currentYear || (d.getMonth() + 1) !== this.currentMonth) {
      animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
        this.currentYear = d.getFullYear();
        this.currentMonth = d.getMonth() + 1;
      });
    }
    this.updateAsset(newBill.source, newBill.type, newBill.amount, 'add');
    this.updateChartIfNeeded();
    this.saveBillsToPreferences();
    this.loadBudget();
  }

  deleteBill(id: number) {
    const billToDelete = this.bills.find(item => item.id === id);
    animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
      this.bills = this.bills.filter(item => item.id !== id);
    });
    if (billToDelete) {
      this.updateAsset(billToDelete.source, billToDelete.type, billToDelete.amount, 'remove');
    }
    this.saveBillsToPreferences();
    this.loadBudget();
  }

  async updateBill(id: number, name: string, amount: number, type: '收入' | '支出', date: Date, category: string, source: string, tags?: string[]) {
    console.info('📌 updateBill 被调用，id:', id, 'tags:', tags);
    const index = this.bills.findIndex(item => item.id === id);
    if (index === -1) return;

    const oldBill = this.bills[index];
    const updatedBill: BillItem = {
      id: id,
      name: name,
      amount: amount,
      type: type,
      date: date.getTime(),
      category: category || '其他',
      source: source || '现金',
      tags: tags || [],  // ✅ 更新标签
      ledgerId: oldBill.ledgerId  // 保留原账本归属
    };

    animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
      this.bills = [updatedBill, ...this.bills.filter(item => item.id !== id)];
    });

    await this.updateAsset(oldBill.source, oldBill.type, oldBill.amount, 'remove');
    await this.updateAsset(updatedBill.source, updatedBill.type, updatedBill.amount, 'add');

    const d = new Date(updatedBill.date);
    if (d.getFullYear() !== this.currentYear || (d.getMonth() + 1) !== this.currentMonth) {
      animateTo({ duration: AnimationConfig.DURATION, curve: AnimationConfig.CURVE }, () => {
        this.currentYear = d.getFullYear();
        this.currentMonth = d.getMonth() + 1;
      });
    }

    this.refreshKey++;
    this.updateChartIfNeeded();
    promptAction.showToast({ message: '账单已更新', duration: 1500 });
    this.saveBillsToPreferences();
    this.loadBudget();
  }

  getTotalDays(): number {
    if (this.bills.length === 0) return 0;
    const firstDate = new Date(Math.min(...this.bills.map(b => b.date)));
    const now = new Date();
    const diff = now.getTime() - firstDate.getTime();
    return Math.ceil(diff / (1000 * 60 * 60 * 24));
  }

  // 获取总收入笔数
  getTotalIncomeCount(): number {
    return this.bills.filter(b => b.type === '收入').length;
  }

  // 获取总支出笔数
  getTotalExpenseCount(): number {
    return this.bills.filter(b => b.type === '支出').length;
  }

  // 获取累计总收入
  getTotalIncomeAllTime(): number {
    let total = 0;
    for (let bill of this.bills) {
      if (bill.type === '收入') total += bill.amount;
    }
    return total;
  }

  // 获取累计总支出
  getTotalExpenseAllTime(): number {
    let total = 0;
    for (let bill of this.bills) {
      if (bill.type === '支出') total += bill.amount;
    }
    return total;
  }

  // 切换深色模式
  async toggleDarkMode(isDark: boolean) {
    const colorMode = isDark ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    AppStorage.setOrCreate('currentColorMode', colorMode);
    // 更新系统栏颜色
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const win = await window.getLastWindow(context);
      win.setWindowSystemBarProperties({
        statusBarContentColor: isDark ? '#FFFFFF' : '#000000',
        navigationBarContentColor: isDark ? '#FFFFFF' : '#000000'
      });
    } catch (e) {
      console.error('更新系统栏颜色失败', e);
    }
  }

  // ---------- 记账提醒 ----------
  formatReminderTime(): string {
    const h = String(this.reminderHour).padStart(2, '0');
    const m = String(this.reminderMinute).padStart(2, '0');
    return `${h}:${m}`;
  }

  formatReminderDays(): string {
    const days = [...this.reminderDays].sort((a: number, b: number) => a - b);
    if (days.length === 0) {
      return '未选择';
    }
    if (days.length === 7) {
      return '每天';
    }
    if (days.length === 5 && days[0] === 1 && days[4] === 5) {
      return '工作日';
    }
    if (days.length === 2 && days[0] === 6 && days[1] === 7) {
      return '周末';
    }
    const names: string[] = ['一', '二', '三', '四', '五', '六', '日'];
    let result = '';
    for (let i = 0; i < days.length; i++) {
      result += '周' + names[days[i] - 1];
      if (i < days.length - 1) {
        result += '、';
      }
    }
    return result;
  }

  async loadReminderSettings() {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (!context) {
        return;
      }
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');
      const isOn = await prefs.get('reminder_on', '0') as string;
      this.isReminderOn = isOn === '1';
      const time = await prefs.get('reminder_time', '20:30') as string;
      const parts = time.split(':');
      if (parts.length === 2) {
        const h = Number(parts[0]);
        const m = Number(parts[1]);
        if (!isNaN(h) && h >= 0 && h <= 23) {
          this.reminderHour = h;
        }
        if (!isNaN(m) && m >= 0 && m <= 59) {
          this.reminderMinute = m;
        }
      }
      const daysStr = await prefs.get('reminder_days', '[1,2,3,4,5,6,7]') as string;
      const days = JSON.parse(daysStr) as number[];
      if (Array.isArray(days) && days.length > 0) {
        this.reminderDays = days;
      }
    } catch (e) {
      console.error('加载记账提醒设置失败', e);
    }
  }

  async saveReminderSettings() {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (!context) {
        return;
      }
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');
      await prefs.put('reminder_on', this.isReminderOn ? '1' : '0');
      await prefs.put('reminder_time', this.formatReminderTime());
      await prefs.put('reminder_days', JSON.stringify(this.reminderDays));
      await prefs.flush();
    } catch (e) {
      console.error('保存记账提醒设置失败', e);
    }
  }

  async onReminderToggle(isOn: boolean) {
    // 异步发布/取消期间忽略再次点击，避免竞态
    if (this.reminderBusy) {
      this.isReminderOn = !isOn;
      return;
    }
    this.reminderBusy = true;
    try {
      if (isOn) {
        await this.enableReminder();
      } else {
        await this.disableReminder();
      }
    } finally {
      this.reminderBusy = false;
    }
  }

  async enableReminder() {
    try {
      await notificationManager.requestEnableNotification();
    } catch (e) {
      const err = e as BusinessError;
      console.error('请求通知授权失败: ' + JSON.stringify(err));
      this.isReminderOn = false;
      promptAction.showToast({ message: '需要开启通知权限才能提醒，请在设置中允许通知', duration: 2500 });
      return;
    }
    const published = await this.publishBookkeepingReminder();
    if (published) {
      await this.saveReminderSettings();
      promptAction.showToast({
        message: `记账提醒已开启，${this.formatReminderDays()} ${this.formatReminderTime()} 提醒你`,
        duration: 2500
      });
    } else {
      this.isReminderOn = false;
    }
  }

  async disableReminder() {
    try {
      await reminderAgentManager.cancelAllReminders();
    } catch (e) {
      console.error('取消记账提醒失败', e);
    }
    await this.saveReminderSettings();
    promptAction.showToast({ message: '记账提醒已关闭', duration: 1500 });
  }

  async publishBookkeepingReminder(): Promise<boolean> {
    if (this.reminderDays.length === 0) {
      promptAction.showToast({ message: '请至少选择一个提醒日', duration: 2000 });
      return false;
    }
    try {
      // 重新发布前先取消旧提醒，避免重复提醒
      await reminderAgentManager.cancelAllReminders();
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const bundleName = context && context.abilityInfo ? context.abilityInfo.bundleName : 'com.bcq.myapplication';
      // 计算从现在起最近的一次提醒时间（符合所选星期）
      const candidate = new Date();
      candidate.setHours(this.reminderHour, this.reminderMinute, 0, 0);
      if (candidate.getTime() <= Date.now()) {
        candidate.setDate(candidate.getDate() + 1);
      }
      while (this.reminderDays.indexOf(candidate.getDay() === 0 ? 7 : candidate.getDay()) === -1) {
        candidate.setDate(candidate.getDate() + 1);
      }
      // 日历类型提醒：以通知横幅/通知卡片形式提醒（非闹钟样式），支持每周重复
      const calendar: reminderAgentManager.ReminderRequestCalendar = {
        reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
        dateTime: {
          year: candidate.getFullYear(),
          month: candidate.getMonth() + 1,
          day: candidate.getDate(),
          hour: this.reminderHour,
          minute: this.reminderMinute,
          second: 0
        },
        daysOfWeek: [...this.reminderDays],
        title: '记账提醒',
        content: '别忘了记录今天的账单哦～',
        notificationId: 1001,
        slotType: notificationManager.SlotType.SERVICE_INFORMATION,
        ringDuration: 0,
        actionButton: [{
          title: '知道了',
          type: reminderAgentManager.ActionButtonType.ACTION_BUTTON_TYPE_CLOSE
        }],
        wantAgent: {
          pkgName: bundleName,
          abilityName: 'EntryAbility'
        }
      };
      const reminderId = await reminderAgentManager.publishReminder(calendar);
      console.info(`✅ 记账提醒发布成功，reminderId: ${reminderId}`);
      return true;
    } catch (e) {
      const err = e as BusinessError;
      console.error('❌ 发布记账提醒失败: ' + JSON.stringify(err));
      let msg: string;
      if (err.code === 1700002) {
        // 真机管控：未在 AppGallery Connect 申请"代理提醒"能力的应用，提醒数量上限为 0
        msg = '该设备限制未授权应用使用定时提醒，需在 AppGallery Connect 申请"代理提醒"能力后重新签名';
      } else if (err.code === 1700001) {
        msg = '发布失败：请先在系统设置中开启本应用的通知开关';
      } else {
        msg = `提醒设置失败（错误码 ${err.code}），请稍后重试`;
      }
      promptAction.showToast({ message: msg, duration: 3500 });
      return false;
    }
  }

  // 修改时间/频率后重新发布提醒并保存设置
  async applyReminderChange() {
    if (this.isReminderOn) {
      const ok = await this.publishBookkeepingReminder();
      if (!ok) {
        return;
      }
    }
    await this.saveReminderSettings();
  }

  showReminderTimePicker() {
    const selected = new Date();
    selected.setHours(this.reminderHour, this.reminderMinute, 0, 0);
    this.getUIContext().showTimePickerDialog({
      selected: selected,
      useMilitaryTime: true,
      onAccept: (value: TimePickerResult) => {
        this.reminderHour = value.hour;
        this.reminderMinute = value.minute;
        this.applyReminderChange();
      }
    });
  }

  showReminderWeekPicker() {
    this.reminderWeekDialogController = new CustomDialogController({
      builder: WeekPickerDialog({
        selectedDays: [...this.reminderDays],
        onConfirm: (days: number[]) => {
          this.reminderDays = days;
          this.applyReminderChange();
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true,
      maskColor: 'rgba(0, 0, 0, 0.4)',
      openAnimation: this.dialogOpenAnimation,
      closeAnimation: this.dialogCloseAnimation
    });
    this.reminderWeekDialogController.open();
  }

  // 关于应用弹窗
  showAboutDialog() {
    promptAction.showDialog({
      title: '关于乌鸡记账',
      message: '乌鸡记账 v1.2.0\n\n用心记录每一笔，养肥你的小金库。\n\n© 2026 乌鸡工作室',
      buttons: [
        { text: '确定', color: '#007AFF' }
      ]
    });
  }

  // 分类管理（进入当前账本的分类管理页）
  openCategoryManager() {
    router.pushUrl({
      url: 'pages/CategoryManagePage',
      params: { ledgerId: this.currentLedgerId } as CategoryManageParams
    });
  }

  private async exportBills(type: 'currentMonth' | 'all') {
    try {
      let billsToExport: BillItem[] = [];
      if (type === 'currentMonth') {
        billsToExport = this.getFilteredBills();
      } else {
        billsToExport = this.bills;
      }

      if (billsToExport.length === 0) {
        promptAction.showToast({ message: '没有账单可导出', duration: 2000 });
        return;
      }

      billsToExport.sort((a, b) => a.date - b.date);

      let csvContent = '\uFEFF日期,类型,分类,用途,金额,账本\n';
      for (let item of billsToExport) {
        const d = new Date(item.date);
        const dateStr = d.getFullYear() + '-' +
          String(d.getMonth() + 1).padStart(2, '0') + '-' +
          String(d.getDate()).padStart(2, '0');
        const typeStr = item.type === '收入' ? '收入' : '支出';
        csvContent += dateStr + ',' + typeStr + ',' + escapeCsvField(item.category) + ',' +
          escapeCsvField(item.name) + ',' + item.amount.toFixed(2) + ',' +
          escapeCsvField(this.getLedgerNameById(item.ledgerId)) + '\n';
      }

      const context = getContext(this) as common.UIAbilityContext;
      const cacheDir = context.cacheDir;
      const fileName = '账单导出_' + new Date().toISOString().slice(0, 10) + '.csv';
      const filePath = cacheDir + '/' + fileName;

      const file = fs.openSync(filePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, csvContent);
      fs.closeSync(file);

      const uri = fileUri.getUriFromPath(filePath);

      const csvUtd = utd.getUniformDataTypeByFilenameExtension('.csv');
      const shareData: systemShare.SharedData = new systemShare.SharedData({
        utd: csvUtd,
        uri: uri,
        title: fileName,
        description: '账单导出'
      });

      const shareController: systemShare.ShareController = new systemShare.ShareController(shareData);
      await shareController.show(context, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DEFAULT
      });

    } catch (e) {
      const error = e as BusinessError;
      console.error('导出失败: code=' + error.code + ', message=' + error.message);
      promptAction.showToast({ message: '导出失败，请重试', duration: 2000 });
    }
  }

  // 数据备份（导出到缓存目录，然后分享）
  private async exportData() {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');
      const billsData = await prefs.get('bills_key', '[]') as string;
      const assetData = await prefs.get('asset_categories', '[]') as string;
      const ledgersData = await prefs.get('ledgers_key', '[]') as string;

      const backupData: BackupData = {
        version: '1.1',
        exportTime: new Date().toISOString(),
        bills: JSON.parse(billsData),
        assets: JSON.parse(assetData),
        ledgers: JSON.parse(ledgersData) as LedgerItem[]
      };

      const jsonStr: string = JSON.stringify(backupData, null, 2);
      const fileName: string = `乌鸡记账_备份_${new Date().toISOString().slice(0,10)}.json`;
      const cacheDir: string = context.cacheDir;
      const filePath: string = `${cacheDir}/${fileName}`;

      const file = fs.openSync(filePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, jsonStr);
      fs.closeSync(file);

      const uri = fileUri.getUriFromPath(filePath);
      const csvUtd = utd.getUniformDataTypeByFilenameExtension('.json');
      const shareData: systemShare.SharedData = new systemShare.SharedData({
        utd: csvUtd,
        uri: uri,
        title: fileName,
        description: '乌鸡记账数据备份'
      });
      const shareController: systemShare.ShareController = new systemShare.ShareController(shareData);
      await shareController.show(context, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DEFAULT
      });

      promptAction.showToast({ message: '备份文件已分享', duration: 2000 });
    } catch (error) {
      const err = error as BusinessError;
      if (err.code === 0) {
        return;
      }
      console.error('备份数据失败', err);
      promptAction.showToast({ message: '备份失败', duration: 2000 });
    }
  }

  // 数据恢复（导入）
  private async importData() {
    try {
      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker();
      const options: picker.DocumentSelectOptions = {
        fileSuffixFilters: ['json']
      };
      const uris: Array<string> = await documentPicker.select(options);

      if (!uris || uris.length === 0) {
        return;
      }

      const uri: string = uris[0];
      const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(file.fd);
      const buffer = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buffer);
      fs.closeSync(file);

      // 安全转换 ArrayBuffer 为字符串
      const decoder: util.TextDecoder = new util.TextDecoder('utf-8');
      const content: string = decoder.decode(new Uint8Array(buffer));

      const backupData: BackupData = JSON.parse(content);

      // 校验数据
      if (!backupData.bills || !Array.isArray(backupData.bills) ||
        !backupData.assets || !Array.isArray(backupData.assets)) {
        promptAction.showToast({ message: '无效的备份文件', duration: 2000 });
        return;
      }

      // 确认恢复
      const result = await promptAction.showDialog({
        title: '确认恢复数据',
        message: `将覆盖当前所有账单（${this.bills.length} 条）和资产数据，确定吗？`,
        buttons: [
          { text: '取消', color: '#666666' },
          { text: '确定恢复', color: '#FF6B6B' }
        ]
      });

      if (result.index !== 1) {
        return;
      }

      // 写入数据（旧版本备份无 ledgers 字段时保留现有账本配置）
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');
      await prefs.put('bills_key', JSON.stringify(backupData.bills));
      await prefs.put('asset_categories', JSON.stringify(backupData.assets));
      if (backupData.ledgers !== undefined && Array.isArray(backupData.ledgers) &&
        backupData.ledgers.length > 0) {
        await prefs.put('ledgers_key', JSON.stringify(backupData.ledgers));
      }
      await prefs.flush();

      // 重新加载数据（含账本迁移：导入账单缺 ledgerId 时归入默认账本）
      await this.initLedgerData();
      await this.loadTotalAsset();
      this.refreshKey++;

      promptAction.showToast({ message: `恢复成功，共 ${backupData.bills.length} 条账单`, duration: 2000 });
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      if (err.code === 0) {
        // 用户取消选择
        return;
      }
      console.error('恢复数据失败', err);
      let msg: string = '恢复失败：' + (err.message || '未知错误');
      if (err.message && err.message.includes('JSON')) {
        msg = '备份文件格式损坏，请检查文件内容';
      }
      promptAction.showToast({ message: msg, duration: 3000 });
    }
  }

  // 导入微信账单
  async importWechatBills() {
    if (this.isLoading) {
      return;
    }
    this.isLoading = true;

    try {
      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker();
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      options.fileSuffixFilters = ['csv', 'xlsx', 'xls'];
      const uris: Array<string> = await documentPicker.select(options);

      if (!uris || uris.length === 0) {
        this.isLoading = false;
        return;
      }

      if (this.loadingDialogController) {
        this.loadingDialogController.open();
      }

      const startTime: number = Date.now();

      setTimeout(async () => {
        try {
          const uri: string = uris[0];
          const isCsv: boolean = uri.toLowerCase().endsWith('.csv');
          const file: fs.File = fs.openSync(uri, fs.OpenMode.READ_ONLY);
          const stat: fs.Stat = fs.statSync(file.fd);
          const fileContent: ArrayBuffer = new ArrayBuffer(stat.size);
          fs.readSync(file.fd, fileContent);
          fs.closeSync(file);

          let importedCount: number = 0;

          if (isCsv) {
            // 本应用导出的 CSV 账单（格式：日期,类型,分类,用途,金额,账本）
            const decoder: util.TextDecoder = new util.TextDecoder('utf-8');
            const content: string = decoder.decode(new Uint8Array(fileContent));
            const rows: CsvBillRow[] = this.parseOwnCsvBills(content);
            if (rows.length === 0) {
              throw new Error('未识别到有效的账单数据，请确认选择的是本应用导出的 CSV 文件');
            }
            for (const row of rows) {
              const exists: boolean = this.bills.some((bill: BillItem) =>
                Math.abs(bill.date - row.date) < 60000 &&
                bill.amount === row.amount &&
                bill.name === row.name);
              if (exists) {
                continue;
              }

              // 按账本名映射账本，找不到时归入默认账本
              let ledgerId: number = DEFAULT_LEDGER_ID;
              if (row.ledgerName !== '') {
                const matched = this.ledgers.find((lg: LedgerItem) => lg.name === row.ledgerName);
                if (matched !== undefined) {
                  ledgerId = matched.id;
                }
              }

              // 分类不在目标账本分类中时回退
              const ledgerCats: string[] = this.getLedgerCategoriesById(ledgerId);
              let category: string = row.category;
              if (ledgerCats.indexOf(category) === -1) {
                if (ledgerCats.indexOf('其他') !== -1) {
                  category = '其他';
                } else if (ledgerCats.length > 0) {
                  category = ledgerCats[0];
                }
              }

              this.bills.push({
                id: Date.now() + Math.random() * 1000 + importedCount,
                name: row.name,
                amount: row.amount,
                type: row.type,
                date: row.date,
                category: category,
                source: 'CSV导入',
                ledgerId: ledgerId
              });
              importedCount++;
            }
          } else {
            const task = taskpool.execute(parseExcelInWorker, fileContent);
            const parsedData = await task as Array<ParsedBillData>;

            for (const item of parsedData) {
            const date: Date = new Date(item.timeStr);
            if (isNaN(date.getTime())) continue;

            let finalName: string = '';
            if (item.counterparty && item.transType) {
              finalName = item.counterparty + ' - ' + item.transType;
            } else if (item.counterparty) {
              finalName = item.counterparty;
            } else if (item.transType) {
              finalName = item.transType;
            } else {
              finalName = item.name || '微信账单';
            }

            const finalType: '收入' | '支出' = item.typeStr === '收入' ? '收入' : '支出';

            const exists: boolean = this.bills.some((bill: BillItem) => {
              const d: Date = new Date(bill.date);
              return Math.abs(d.getTime() - date.getTime()) < 60000 &&
                bill.amount === item.amount &&
                bill.name === finalName;
            });

            if (!exists) {
              const guessed: string = this.guessCategory(
                item.name || '',
                item.transType,
                item.counterparty || ''
              );
              // 猜测分类不在当前账本分类中时回退
              const ledgerCats: string[] = this.getCurrentLedgerCategories();
              let category: string = guessed;
              if (ledgerCats.indexOf(guessed) === -1) {
                if (ledgerCats.indexOf('其他') !== -1) {
                  category = '其他';
                } else if (ledgerCats.length > 0) {
                  category = ledgerCats[0];
                }
              }
              this.bills.push({
                id: Date.now() + Math.random() * 1000 + importedCount,
                name: finalName,
                amount: item.amount,
                type: finalType,
                date: date.getTime(),
                category: category,
                source: '微信',
                ledgerId: this.currentLedgerId
              });
              importedCount++;
            }
            }
          }

          await this.saveBillsToPreferences();

          const elapsed: number = Date.now() - startTime;
          const minDisplayTime: number = 500;

          const finishImport = () => {
            if (this.loadingDialogController) {
              this.loadingDialogController.close();
            }
            this.isLoading = false;
            promptAction.showToast({
              message: `导入成功，共导入 ${importedCount} 条账单`,
              duration: 2000
            });
          };

          if (elapsed < minDisplayTime) {
            setTimeout(finishImport, minDisplayTime - elapsed);
          } else {
            finishImport();
          }

        } catch (error) {
          if (this.loadingDialogController) {
            this.loadingDialogController.close();
          }
          this.isLoading = false;
          const err: BusinessError = error as BusinessError;
          console.error('导入失败: ' + err.message);
          promptAction.showToast({ message: '导入失败: ' + err.message, duration: 2000 });
        }
      }, 50);

    } catch (error) {
      if (this.loadingDialogController) {
        this.loadingDialogController.close();
      }
      this.isLoading = false;
      const err: BusinessError = error as BusinessError;
      console.error('导入失败: ' + err.message);
      promptAction.showToast({ message: '导入失败: ' + err.message, duration: 2000 });
    }
  }

  // 解析本应用导出的 CSV 账单内容（格式：日期,类型,分类,用途,金额,账本）
  private parseOwnCsvBills(content: string): CsvBillRow[] {
    const rows: CsvBillRow[] = [];
    let text: string = content;
    if (text.length > 0 && text.charCodeAt(0) === 0xFEFF) {
      text = text.substring(1);
    }
    const lines: string[] = text.split('\n');
    for (let i: number = 0; i < lines.length; i++) {
      const line: string = lines[i].trim();
      if (line.length === 0) {
        continue;
      }
      const fields: string[] = splitCsvLine(line);
      if (fields.length < 5) {
        continue;
      }
      if (fields[0] === '日期') {
        continue;
      }
      const date: Date = new Date(fields[0]);
      if (isNaN(date.getTime())) {
        continue;
      }
      const amount: number = parseFloat(fields[4]);
      if (isNaN(amount) || amount === 0) {
        continue;
      }
      const type: '收入' | '支出' = fields[1] === '收入' ? '收入' : '支出';
      const row: CsvBillRow = {
        date: date.getTime(),
        type: type,
        category: fields[2],
        name: fields[3],
        amount: Math.abs(amount),
        ledgerName: fields.length > 5 ? fields[5] : ''
      };
      rows.push(row);
    }
    return rows;
  }

  // 显示删除确认弹窗
  showDeleteConfirmDialog() {
    const billsToDelete: BillItem[] = this.getBillViewBills();
    if (billsToDelete.length === 0) {
      promptAction.showToast({ message: '当前没有可删除的账单', duration: 1500 });
      return;
    }

    promptAction.showDialog({
      title: '确认删除',
      message: `将删除当前筛选条件下的 ${billsToDelete.length} 条账单，确定吗？`,
      buttons: [
        {
          text: '取消',
          color: '#666666'
        },
        {
          text: '删除',
          color: '#FF3B30'
        }
      ]
    }).then((result: DialogResult) => {
      if (result.index === 1) {
        const idsToDelete: Set<number> = new Set(billsToDelete.map((bill: BillItem) => bill.id));
        this.bills = this.bills.filter((bill: BillItem) => !idsToDelete.has(bill.id));
        this.saveBillsToPreferences();
        promptAction.showToast({
          message: `已删除 ${billsToDelete.length} 条账单`,
          duration: 1500
        });
      }
    }).catch(() => {});
  }

  guessCategory(name: string, transType: string, counterparty: string = ''): string {
    const combined = (counterparty + ' ' + name).toLowerCase();
    const transLower = transType.toLowerCase();

    if (transLower.includes('理财通') || transLower.includes('零钱通') ||
      transLower.includes('提现') || transLower.includes('充值') ||
      transLower.includes('转入') || transLower.includes('转出') ||
      transLower.includes('购买理财通') || transLower.includes('理财通赎回')) {
      return '其他';
    }

    if (combined.includes('电影') || combined.includes('影院') || combined.includes('ktv') ||
      combined.includes('游戏') || combined.includes('游乐') || combined.includes('公园') ||
      combined.includes('门票') || combined.includes('演出') || combined.includes('游乐园') ||
      combined.includes('密室') || combined.includes('剧本杀') || combined.includes('滑雪') ||
      combined.includes('温泉') || combined.includes('动物园') || combined.includes('博物馆') ||
      combined.includes('展览') || combined.includes('迪士尼') || combined.includes('欢乐谷') ||
      combined.includes('长隆') || combined.includes('猫眼') || combined.includes('淘票票')) {
      return '娱乐';
    }

    if (combined.includes('餐厅') || combined.includes('饭') || combined.includes('咖啡') ||
      combined.includes('奶茶') || combined.includes('茶') || combined.includes('甜') ||
      combined.includes('火锅') || combined.includes('面') || combined.includes('粉') ||
      combined.includes('外卖') || combined.includes('美团') || combined.includes('饿了么') ||
      combined.includes('快餐') || combined.includes('汉堡') || combined.includes('炸鸡') ||
      combined.includes('寿司') || combined.includes('料理') || combined.includes('烤肉') ||
      combined.includes('食堂') || combined.includes('美食') || combined.includes('甜品') ||
      combined.includes('面包') || combined.includes('早点') || combined.includes('夜宵') ||
      combined.includes('小吃') || combined.includes('煲') || combined.includes('粥') ||
      combined.includes('水饺') || combined.includes('馄饨') || combined.includes('麻辣烫') ||
      combined.includes('自助') || combined.includes('海鲜') || combined.includes('茶餐厅') ||
      combined.includes('西餐') || combined.includes('蜜雪冰城') || combined.includes('瑞幸') ||
      combined.includes('星巴克') || combined.includes('海底捞') || combined.includes('太二') ||
      combined.includes('喜茶') || combined.includes('奈雪') || combined.includes('肯德基') ||
      combined.includes('麦当劳') || combined.includes('酒')) {
      return '餐饮';
    }

    if (combined.includes('打车') || combined.includes('滴滴') || combined.includes('出租车') ||
      combined.includes('地铁') || combined.includes('公交') || combined.includes('交通') ||
      combined.includes('火车') || combined.includes('高铁') || combined.includes('中铁') ||
      combined.includes('机票') || combined.includes('航班') || combined.includes('出行') ||
      combined.includes('停车') || combined.includes('etc') || combined.includes('加油') ||
      combined.includes('骑行') || combined.includes('单车') || combined.includes('铁路') ||
      combined.includes('花小猪') || combined.includes('摆渡') || combined.includes('巴士') ||
      combined.includes('客车')) {
      return '交通';
    }

    if (combined.includes('超市') || combined.includes('便利店') || combined.includes('购物') ||
      combined.includes('淘宝') || combined.includes('京东') || combined.includes('拼多多') ||
      combined.includes('天猫') || combined.includes('商场') || combined.includes('百货') ||
      combined.includes('折扣') || combined.includes('专卖店') || combined.includes('商城') ||
      combined.includes('电商') || combined.includes('网购') || combined.includes('山姆') ||
      combined.includes('沃尔玛') || combined.includes('家乐福') || combined.includes('永旺') ||
      combined.includes('屈臣氏') || combined.includes('名创') || combined.includes('优衣库') ||
      combined.includes('nike') || combined.includes('adidas')) {
      return '购物';
    }

    if (combined.includes('医院') || combined.includes('诊所') || combined.includes('药房') ||
      combined.includes('体检') || combined.includes('医疗') || combined.includes('牙科') ||
      combined.includes('口腔') || combined.includes('疾病') || combined.includes('门诊') ||
      combined.includes('挂号') || combined.includes('医保') || combined.includes('康复')) {
      return '医疗';
    }

    if (combined.includes('学校') || combined.includes('培训') || combined.includes('教育') ||
      combined.includes('大学') || combined.includes('学院') || combined.includes('文化') ||
      combined.includes('考试') || combined.includes('课程') || combined.includes('书店') ||
      combined.includes('课外') || combined.includes('辅导') || combined.includes('文具') ||
      combined.includes('教材') || combined.includes('图书') || combined.includes('自习')) {
      return '教育';
    }

    if (transLower.includes('商户消费') || transLower.includes('扫二维码付款')) {
      if (combined.includes('水电') || combined.includes('燃气') || combined.includes('物业') ||
        combined.includes('话费') || combined.includes('宽带') || combined.includes('充值')) {
        return '其他';
      }
      return '其他';
    }

    if (transLower.includes('转账')) {
      if (combined.includes('饭') || combined.includes('餐') || combined.includes('外卖')) {
        return '餐饮';
      }
      if (combined.includes('车') || combined.includes('打车') || combined.includes('滴滴')) {
        return '交通';
      }
      return '其他';
    }

    return '其他';
  }

  // ---------- 打开弹窗 ----------
  openAddDialog() {
    // 每次打开重新构建，使用当前账本的分类列表
    this.dialogController = new CustomDialogController({
      builder: AddBillDialog({
        categories: this.getCurrentLedgerCategories(),
        onAddBill: (name, amount, type, date, category, source, tags) => {
          this.addBill(name, amount, type, date, category, source, tags);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true,
      maskColor: 'rgba(0, 0, 0, 0.4)',
      openAnimation: this.dialogOpenAnimation,
      closeAnimation: this.dialogCloseAnimation
    });
    if (this.dialogController) {
      this.dialogController.open();
    }
  }

  openEditDialog(bill: BillItem) {
    this.editDialogController = new CustomDialogController({
      builder: EditBillDialog({
        billId: bill.id,
        paramName: bill.name,
        paramAmount: bill.amount.toString(),
        paramType: bill.type,
        paramDate: new Date(bill.date),
        paramCategory: bill.category || '其他',
        paramSource: bill.source || '现金',
        paramTags: bill.tags || [],
        categories: this.getCurrentLedgerCategories(),
        onUpdateBill: (id, name, amount, type, date, category, source) => {
          this.updateBill(id, name, amount, type, date, category, source);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true,
      maskColor: 'rgba(0, 0, 0, 0.4)',
      openAnimation: this.dialogOpenAnimation,
      closeAnimation: this.dialogCloseAnimation
    });
    this.editDialogController.open();
  }

  openDetailDialog(bill: BillItem) {
    this.detailDialogController = new CustomDialogController({
      builder: BillDetailDialog({
        bill: bill,
        onEdit: (billItem: BillItem) => {
          this.openEditDialog(billItem);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true,
      maskColor: 'rgba(0, 0, 0, 0.4)',
      openAnimation: this.dialogOpenAnimation,
      closeAnimation: this.dialogCloseAnimation
    });
    this.detailDialogController.open();
  }

  openSearchDialog() {
    this.searchDialogController = new CustomDialogController({
      builder: SearchBillDialog({
        bills: this.bills,
        onSelectBill: (bill: BillItem) => {
          const d = new Date(bill.date);
          this.currentYear = d.getFullYear();
          this.currentMonth = d.getMonth() + 1;
          this.openDetailDialog(bill);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true,
      maskColor: 'rgba(0, 0, 0, 0.4)',
      openAnimation: this.dialogOpenAnimation,
      closeAnimation: this.dialogCloseAnimation
    });
    this.searchDialogController.open();
  }

  showExportDialog() {
    this.exportDialogController = new CustomDialogController({
      builder: ExportConfirmDialog({
        onExport: (type: 'currentMonth' | 'all') => {
          this.exportBills(type);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true,
      maskColor: 'rgba(0, 0, 0, 0.4)',
      openAnimation: this.dialogOpenAnimation,
      closeAnimation: this.dialogCloseAnimation
    });
    this.exportDialogController.open();
  }

  openSetBudgetDialog() {
    this.setBudgetDialogController = new CustomDialogController({
      builder: SetBudgetDialog({
        currentBudget: this.budget,
        onConfirm: (amount: number) => {
          this.saveBudget(amount);
          promptAction.showToast({ message: '预算已设置', duration: 1500 });
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true,
      maskColor: 'rgba(0, 0, 0, 0.4)',
      openAnimation: this.dialogOpenAnimation,
      closeAnimation: this.dialogCloseAnimation
    });
    this.setBudgetDialogController.open();
  }

  // ---------- 图表 ----------
  drawPieChart() {
    if (!this.canvasCtx) return;
    const ctx = this.canvasCtx;
    const data = this.getExpenseStats();
    const totalExpense = data.reduce((sum, d) => sum + d.total, 0);

    const canvasWidth = 300;
    const canvasHeight = 300;
    const centerX = canvasWidth / 2;
    const centerY = canvasHeight / 2;
    const radius = Math.min(canvasWidth, canvasHeight) / 2 - 20;

    ctx.clearRect(0, 0, canvasWidth, canvasHeight);

    if (totalExpense === 0) {
      ctx.font = '42px sans-serif';
      ctx.fillStyle = '#999';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText('本月暂无支出', centerX, centerY);
      return;
    }

    let startAngle = -Math.PI / 2;
    for (let i = 0; i < data.length; i++) {
      const item = data[i];
      const sliceAngle = (item.total / totalExpense) * 2 * Math.PI;
      ctx.beginPath();
      ctx.moveTo(centerX, centerY);
      ctx.arc(centerX, centerY, radius, startAngle, startAngle + sliceAngle);
      ctx.closePath();
      ctx.fillStyle = item.color;
      ctx.fill();
      ctx.strokeStyle = '#FFFFFF';
      ctx.lineWidth = 2;
      ctx.stroke();
      startAngle += sliceAngle;
    }
  }

  drawTrendChart() {
    if (!this.trendCanvasCtx) return;
    const ctx = this.trendCanvasCtx;
    const data = this.getDailyExpenseData();

    let canvasWidth = this.trendCanvasWidth;
    if (canvasWidth <= 0) {
      canvasWidth = 400;
    }
    const canvasHeight = 200;

    const hasData = data.some(d => d.amount > 0);
    if (!hasData) {
      ctx.clearRect(0, 0, canvasWidth, canvasHeight);
      ctx.font = '24px sans-serif';
      ctx.fillStyle = '#999';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText('本月暂无支出数据', canvasWidth / 2, canvasHeight / 2);
      return;
    }

    const maxAmount = Math.max(...data.map(d => d.amount), 1);
    const padding: Padding = { top: 20, bottom: 36, left: 32, right: 10 };
    const chartWidth = canvasWidth - padding.left - padding.right;
    const chartHeight = canvasHeight - padding.top - padding.bottom;

    const getX = (index: number) => padding.left + (index / (data.length - 1 || 1)) * chartWidth;
    const getY = (amount: number) => padding.top + chartHeight - (amount / maxAmount) * chartHeight;

    ctx.clearRect(0, 0, canvasWidth, canvasHeight);

    ctx.strokeStyle = '#EEF0F4';
    ctx.lineWidth = 1.5;
    for (let i = 0; i <= 4; i++) {
      const y = padding.top + (i / 4) * chartHeight;
      ctx.beginPath();
      ctx.moveTo(padding.left, y);
      ctx.lineTo(canvasWidth - padding.right, y);
      ctx.stroke();
    }

    for (let i = 0; i <= 4; i++) {
      const y = padding.top + (i / 4) * chartHeight;
      ctx.fillStyle = '#666';
      ctx.font = 'bold 26px sans-serif';
      ctx.textAlign = 'right';
      ctx.textBaseline = 'middle';
      const label = Math.round(maxAmount - (i / 4) * maxAmount);
      ctx.fillText('¥' + label, padding.left - 8, y);
    }

    const points: Point[] = [];
    for (let i = 0; i < data.length; i++) {
      points.push({ x: getX(i), y: getY(data[i].amount) } as Point);
    }

    if (points.length < 2) return;

    ctx.beginPath();
    ctx.moveTo(points[0].x, points[0].y);
    for (let i = 1; i < points.length; i++) {
      ctx.lineTo(points[i].x, points[i].y);
    }
    ctx.strokeStyle = '#FF6B6B';
    ctx.lineWidth = 3;
    ctx.lineJoin = 'round';
    ctx.lineCap = 'round';
    ctx.stroke();

    ctx.beginPath();
    ctx.moveTo(points[0].x, chartHeight + padding.top);
    ctx.lineTo(points[0].x, points[0].y);
    for (let i = 1; i < points.length; i++) {
      ctx.lineTo(points[i].x, points[i].y);
    }
    ctx.lineTo(points[points.length - 1].x, chartHeight + padding.top);
    ctx.closePath();

    const gradient = ctx.createLinearGradient(0, padding.top, 0, chartHeight + padding.top);
    gradient.addColorStop(0, 'rgba(255, 107, 107, 0.15)');
    gradient.addColorStop(1, 'rgba(255, 107, 107, 0.01)');
    ctx.fillStyle = gradient;
    ctx.fill();

    for (let i = 0; i < data.length; i++) {
      if (data[i].amount === 0) continue;
      const x = getX(i);
      const y = getY(data[i].amount);
      ctx.beginPath();
      ctx.arc(x, y, 6, 0, Math.PI * 2);
      ctx.fillStyle = '#FFFFFF';
      ctx.fill();
      ctx.strokeStyle = '#FF6B6B';
      ctx.lineWidth = 2.5;
      ctx.stroke();
    }

    const labelStep = Math.max(3, Math.floor(data.length / 6));
    for (let i = 0; i < data.length; i += labelStep) {
      const x = getX(i);
      ctx.fillStyle = '#666';
      ctx.font = 'bold 26px sans-serif';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'top';
      ctx.fillText(data[i].day + '日', x, chartHeight + padding.top + 8);
    }
  }

  // 绘制年度支出趋势图（柱状图）
  drawYearlyTrendChart() {
    if (!this.yearCanvasCtx) return;
    const ctx = this.yearCanvasCtx;
    const monthlyData = this.getYearlyExpenseData();
    const maxAmount = Math.max(...monthlyData, 1);

    const padding: Padding = { top: 20, bottom: 36, left: 32, right: 10 };
    const canvasWidth = this.yearCanvasWidth || 400;
    const canvasHeight = 200;
    const chartWidth = canvasWidth - padding.left - padding.right;
    const chartHeight = canvasHeight - padding.top - padding.bottom;

    ctx.clearRect(0, 0, canvasWidth, canvasHeight);

    ctx.strokeStyle = '#EEF0F4';
    ctx.lineWidth = 1.5;
    for (let i = 0; i <= 4; i++) {
      const y = padding.top + (i / 4) * chartHeight;
      ctx.beginPath();
      ctx.moveTo(padding.left, y);
      ctx.lineTo(canvasWidth - padding.right, y);
      ctx.stroke();
    }

    ctx.fillStyle = '#666';
    ctx.font = 'bold 26px sans-serif';
    ctx.textAlign = 'right';
    ctx.textBaseline = 'middle';
    for (let i = 0; i <= 4; i++) {
      const y = padding.top + (i / 4) * chartHeight;
      const label = Math.round(maxAmount - (i / 4) * maxAmount);
      ctx.fillText('¥' + label, padding.left - 8, y);
    }

    const barWidth = chartWidth / 12 * 0.6;
    for (let i = 0; i < 12; i++) {
      const x = padding.left + (i / 12) * chartWidth + (chartWidth / 12 - barWidth) / 2;
      const barHeight = (monthlyData[i] / maxAmount) * chartHeight;
      const y = padding.top + chartHeight - barHeight;

      ctx.fillStyle = monthlyData[i] > 0 ? '#FF6B6B' : '#E8ECF0';
      ctx.beginPath();
      ctx.roundRect(x, y, barWidth, barHeight, [2, 2, 0, 0]);
      ctx.fill();

      ctx.fillStyle = '#666';
      ctx.font = 'bold 26px sans-serif';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'top';
      const labelX = padding.left + (i / 12) * chartWidth + chartWidth / 12 / 2;
      ctx.fillText((i + 1) + '月', labelX, padding.top + chartHeight + 8);
    }
  }

  updateChartIfNeeded() {
    if (this.currentTabIndex === 1) {
      setTimeout(() => {
        this.drawPieChart();
        this.drawTrendChart();
      }, 50);
    }
  }

  // ---------- 数据迁移 ----------
  migrateOldData() {
    let needUpdate = false;
    this.bills.forEach(item => {
      if (item.date === undefined) {
        needUpdate = true;
        item.date = item.id;
      }
      if (item.category === undefined) {
        needUpdate = true;
        item.category = '其他';
      }
      if (!item.source) {
        needUpdate = true;
        item.source = '现金';
      }
    });
    if (needUpdate) {
      this.saveBillsToPreferences();
    }
  }

  migrateOldBillsForTags() {
    let needUpdate = false;
    this.bills.forEach(item => {
      if (!item.tags) {
        needUpdate = true;
        item.tags = [];
      }
    });
    if (needUpdate) {
      this.saveBillsToPreferences();
    }
  }

  // ---------- 预算卡片 Builder ----------
  @Builder
  BudgetCard() {
    if (this.hasBudget && this.budget > 0) {
      Column() {
        Row() {
          Text('本月预算')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Blank()
          Text(`¥${this.getBudgetStatus().monthlyExpense.toFixed(0)} / ¥${this.budget.toFixed(0)}`)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .margin({ bottom: 8 })

        Column() {
          Column() { }
          .width(this.getBudgetStatus().usedPercentForDisplay + '%')
          .height(8)
          .backgroundColor(this.getBudgetStatus().usedPercentForColor > 100 ? '#FF3B30' : this.getBudgetStatus().usedPercentForColor > 80 ? '#FF9500' : '#34C759')
          .borderRadius(4)
          .animation({ curve: AnimationConfig.SPRING_SOFT })
        }
        .width('100%')
        .height(8)
        .backgroundColor('#E8ECF0')
        .borderRadius(4)
        .alignItems(HorizontalAlign.Start)
        .margin({ bottom: 6 })

        Row() {
          Text(this.getBudgetStatus().isOverBudget ? `超支 ¥${(this.getBudgetStatus().monthlyExpense - this.budget).toFixed(0)}` : `剩余 ¥${this.getBudgetStatus().remaining.toFixed(0)}`)
            .fontSize(14)
            .fontColor(this.getBudgetStatus().isOverBudget ? '#FF3B30' : '#34C759')
          Blank()
          Text(this.getBudgetStatus().usedPercentForColor > 100 ? '已超支' : `已使用 ${this.getBudgetStatus().usedPercentForColor.toFixed(0)}%`)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
      }
      .width('100%')
      .padding({ top: 12, bottom: 12, left: 16, right: 16 })
      .backgroundColor($r('app.color.card_bg'))
      .borderRadius(12)
      .shadow({
        radius: 8,
        color: 'rgba(0, 0, 0, 0.03)',
        offsetX: 0,
        offsetY: 2
      })
      .margin({ bottom: 16 })
      .scale({ x: this.pressedCard === 'budget' ? 0.97 : 1, y: this.pressedCard === 'budget' ? 0.97 : 1 })
      .animation({ curve: AnimationConfig.SPRING })
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.pressedCard = 'budget';
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.pressedCard = '';
        }
      })
      .onClick(() => {
        this.openSetBudgetDialog();
      })
    } else {
      Column() {
        Row() {
          Text('预算管理')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Blank()
          Text('点击设置')
            .fontSize(14)
            .fontColor($r('app.color.brand_blue'))
        }
        .width('100%')
      }
      .width('100%')
      .padding({ top: 12, bottom: 12, left: 16, right: 16 })
      .backgroundColor($r('app.color.card_bg'))
      .borderRadius(12)
      .shadow({
        radius: 8,
        color: 'rgba(0, 0, 0, 0.03)',
        offsetX: 0,
        offsetY: 2
      })
      .margin({ bottom: 16 })
      .scale({ x: this.pressedCard === 'budget' ? 0.97 : 1, y: this.pressedCard === 'budget' ? 0.97 : 1 })
      .animation({ curve: AnimationConfig.SPRING })
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.pressedCard = 'budget';
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.pressedCard = '';
        }
      })
      .onClick(() => {
        this.openSetBudgetDialog();
      })
    }
  }

  onPageShow() {
    this.loadTotalAsset();

    const refreshFlag = AppStorage.get<number>('shouldRefreshBills') || 0;
    if (refreshFlag !== this.lastRefreshFlag) {
      this.lastRefreshFlag = refreshFlag;
      console.info('📌 检测到账单变更，刷新账单数据');
      this.loadBillsFromPreferences().then(() => {
        // 强制刷新列表
        this.refreshKey++;
      });
    }

    // 账本/分类变更信号（来自账本管理页/分类管理页）
    const ledgerRefreshFlag = AppStorage.get<number>('shouldRefreshLedgers') || 0;
    if (ledgerRefreshFlag !== this.lastLedgerRefreshFlag) {
      this.lastLedgerRefreshFlag = ledgerRefreshFlag;
      console.info('📌 检测到账本变更，刷新账本数据');
      this.loadLedgerState().then(() => {
        if (this.billFilterCategory !== '全部' &&
          this.getCurrentLedgerCategories().indexOf(this.billFilterCategory) === -1) {
          this.billFilterCategory = '全部';
        }
        this.updateLedgerBills();
        this.loadBudget();
        this.refreshKey++;
      });
    }
  }

  // ---------- Tab 构建器 ----------
  @Builder
  TabBuilder(title: string, index: number) {
    Column() {
      Text(title)
        .fontSize(16)
        .fontColor(this.currentTabIndex === index ? $r('app.color.brand_blue') : $r('app.color.text_secondary'))
        .fontWeight(this.currentTabIndex === index ? 600 : FontWeight.Normal)
        .margin({ top: -2 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  // ---------- 账本切换入口 ----------
  @Builder
  LedgerChip() {
    Row() {
      SymbolGlyph(getLedgerIconResource(this.getCurrentLedger().icon))
        .fontSize(12)
        .fontColor([$r('app.color.brand_blue')])
      Text(this.getCurrentLedger().name)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.brand_blue'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: 72 })
        .margin({ left: 3 })
      SymbolGlyph($r('sys.symbol.chevron_down'))
        .fontSize(10)
        .fontColor([$r('app.color.brand_blue')])
        .margin({ left: 2 })
    }
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .backgroundColor($r('app.color.category_btn_bg'))
    .borderRadius(12)
    .border({ width: 1, color: $r('app.color.border_color') })
    .onClick(() => { this.openLedgerSwitchDialog(); })
  }

  // ---------- 账本切换弹层（原生半模态内容） ----------
  @Builder
  LedgerSheetBuilder() {
    Column() {
      Text('选择账本')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 24, bottom: 16 })

      Scroll() {
        Column() {
          ForEach(this.ledgers, (item: LedgerItem) => {
            Row() {
              Column() {
                SymbolGlyph(getLedgerIconResource(item.icon))
                  .fontSize(22)
                  .fontColor([item.color])
              }
              .width(40)
              .height(40)
              .borderRadius(20)
              .backgroundColor(item.color + '1A')
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)

              Text(item.name)
                .fontSize(16)
                .fontWeight(this.currentLedgerId === item.id ? FontWeight.Medium : FontWeight.Normal)
                .fontColor($r('app.color.text_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
                .margin({ left: 12 })

              if (this.currentLedgerId === item.id) {
                SymbolGlyph($r('sys.symbol.checkmark'))
                  .fontSize(18)
                  .fontColor([$r('app.color.brand_blue')])
              }
            }
            .width('100%')
            .padding({ top: 14, bottom: 14, left: 16, right: 16 })
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(12)
            .margin({ bottom: 12 })
            .onClick(() => {
              this.showLedgerSheet = false;
              this.switchLedger(item.id);
            })
          }, (item: LedgerItem) => item.id.toString())
        }
        .width('100%')
      }
      .layoutWeight(1)
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Off)

      Divider()
        .color($r('app.color.border_color'))
        .margin({ top: 0, bottom: 10 })

      Row() {
        Button('管理账本')
          .backgroundColor($r('app.color.card_bg'))
          .fontColor($r('app.color.brand_blue'))
          .borderRadius(20)
          .border({ width: 1, color: $r('app.color.border_color') })
          .height(40)
          .layoutWeight(1)
          .fontSize(15)
          .onClick(() => {
            this.showLedgerSheet = false;
            router.pushUrl({ url: 'pages/LedgerManagePage' });
          })
      }
      .width('100%')
      .padding({ bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16 })
  }

  // ---------- 功能项构建器 ----------
  @Builder
  FunctionItem(icon: Resource, label: string, action: () => void) {
    Column() {
      SymbolGlyph(icon)
        .fontSize(26)
        .fontColor([$r('app.color.brand_blue')])
        .margin({ bottom: 6 })
      Text(label)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .backgroundColor($r('app.color.category_btn_bg'))
    .borderRadius(12)
    .scale({ x: this.pressedFunc === label ? 0.9 : 1, y: this.pressedFunc === label ? 0.9 : 1 })
    .animation({ curve: AnimationConfig.SPRING })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressedFunc = label;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressedFunc = '';
      }
    })
    .onClick(() => { action(); })
    .layoutWeight(1)
    .margin({ left: 4, right: 4 })
  }

  // ---------- 主界面 ----------
  build() {
    Column() {
      HdsTabs({ barPosition: BarPosition.End, index: this.currentTabIndex }) {
        // ============================================
        // ========== 记账页（Tab 0） ==========
        // ============================================
        TabContent() {
          Column() {
            Row()
              .width('100%')
              .height(10)
              .backgroundColor($r('app.color.bg_main'))
              .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
              .flexShrink(0)

            Row() {
              Text('乌鸡记账')
                .fontSize(28)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
              Column() {
                this.LedgerChip()
              }
              .margin({ left: 10 })
              Blank()
              Image($r('sys.media.ohos_ic_public_more'))
                .width(28)
                .height(28)
                .fillColor($r('app.color.text_primary'))
                .bindMenu([
                  {
                    value: '导出账单',
                    action: () => { this.showExportDialog(); }
                  },
                  {
                    value: '导入账单(CSV/微信Excel)',
                    action: () => {
                      this.importWechatBills();
                    }
                  },
                  {
                    value: '备份数据',
                    action: () => { this.exportData(); }
                  },
                  {
                    value: '恢复数据',
                    action: () => { this.importData(); }
                  }
                ])
            }
            .width('100%')
            .margin({ top: 10, bottom: 4 })

            Row() {
              SymbolGlyph($r('sys.symbol.chevron_left'))
                .fontSize(22)
                .fontColor([$r('app.color.brand_blue')])
                .onClick(() => { this.goPreviousMonth(); })
                .margin({ right: 12 })

              Text(`${this.currentYear}年${this.currentMonth}月`)
                .fontSize(18)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)
                .textAlign(TextAlign.Center)

              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(22)
                .fontColor([$r('app.color.brand_blue')])
                .onClick(() => { this.goNextMonth(); })
                .margin({ left: 12 })

              Blank().width(12)

              Button() {
                Image($r('sys.media.ohos_ic_public_search_filled'))
                  .width(20).height(20).fillColor($r('app.color.brand_blue'))
              }
              .width(34).height(34)
              .backgroundColor($r('app.color.category_btn_bg'))
              .borderColor($r('app.color.border_color')).borderWidth(1).borderRadius(17)
              .onClick(() => { this.openSearchDialog(); })

              Blank().width(14)

              Button('手动记账')
                .backgroundColor($r('app.color.brand_blue'))
                .fontColor($r('app.color.text_white'))
                .borderRadius(22)
                .padding({ left: 14, right: 14 })
                .height(34)
                .fontSize(13)
                .scale({ x: this.manualBtnScale, y: this.manualBtnScale })
                .onTouch((event: TouchEvent) => {
                  if (event.type === TouchType.Down) {
                    animateTo({ curve: AnimationConfig.SPRING }, () => {
                      this.manualBtnScale = 0.92;
                    });
                  } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                    animateTo({ curve: AnimationConfig.SPRING }, () => {
                      this.manualBtnScale = 1;
                    });
                  }
                })
                .onClick(() => { this.openAddDialog(); })
            }
            .width('100%')
            .padding({ top: 12, bottom: 16 })

            // ===== 我的总资产 + 当月变化 =====
            Row() {
              Column() {
                Row() {
                  Text('我的总资产')
                    .fontSize(13)
                    .fontColor($r('app.color.text_secondary'))
                  Image($r('sys.media.ohos_ic_public_arrow_right'))
                    .width(14)
                    .height(14)
                    .fillColor($r('app.color.text_secondary'))
                    .margin({ left: 4 })
                }
                Text('¥' + this.totalAsset.toFixed(2))
                  .fontSize(26)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.totalAsset >= 0 ? $r('app.color.text_primary') : $r('app.color.expense_red'))
                  .margin({ top: 2 })
              }
              .width('100%')
              .padding({ top: 12, bottom: 12 })
              .backgroundColor($r('app.color.card_bg'))
              .borderRadius(16)
              .shadow({ radius: 8, color: 'rgba(0, 0, 0, 0.04)', offsetX: 0, offsetY: 2 })
              .layoutWeight(1)
              .scale({ x: this.pressedCard === 'totalAsset' ? 0.96 : 1, y: this.pressedCard === 'totalAsset' ? 0.96 : 1 })
              .animation({ curve: AnimationConfig.SPRING })
              .onTouch((event: TouchEvent) => {
                if (event.type === TouchType.Down) {
                  this.pressedCard = 'totalAsset';
                } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                  this.pressedCard = '';
                }
              })
              .onClick(() => {
                router.pushUrl({ url: 'pages/AssetDetailPage' });
              })

              Blank().width(12)

              Column() {
                Text('当月变化')
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
                Text(
                  (this.getTotal() > 0 ? '+' : '') + '¥' + this.getTotal().toFixed(2)
                )
                  .fontSize(22)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.getTotal() > 0 ? $r('app.color.income_gold') : this.getTotal() < 0 ? $r('app.color.expense_red') : $r('app.color.text_primary'))
                  .margin({ top: 2 })
              }
              .width('100%')
              .padding({ top: 12, bottom: 12 })
              .backgroundColor($r('app.color.card_bg'))
              .borderRadius(16)
              .shadow({ radius: 8, color: 'rgba(0, 0, 0, 0.04)', offsetX: 0, offsetY: 2 })
              .layoutWeight(1)
              .scale({ x: this.pressedCard === 'monthChange' ? 0.96 : 1, y: this.pressedCard === 'monthChange' ? 0.96 : 1 })
              .animation({ curve: AnimationConfig.SPRING })
            }
            .width('100%')
            .margin({ bottom: 16 })

            this.BudgetCard()

            Column() {
              Row() {
                Text('当月账单')
                  .fontSize(18)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                Blank()
                Text('查看全部 →')
                  .fontSize(14)
                  .fontColor($r('app.color.brand_blue'))
                  .fontWeight(FontWeight.Medium)
                  .onClick(() => {
                    animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
                      this.currentTabIndex = 2;
                    });
                  })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 8 })

              List() {
                ForEach(
                  this.getFilteredBills().slice(0, 5),
                  (item: BillItem) => {
                    ListItem() {
                      Column() {
                        // ===== 第一行：原有的所有信息 =====
                        Row() {
                          Column() { }
                          .width(8)
                          .height(8)
                          .borderRadius(4)
                          .backgroundColor(getCategoryColor(item.category))
                          .margin({ right: 12 })

                          Text(item.type)
                            .fontSize(13)
                            .backgroundColor(
                              item.type === '收入' ? $r('app.color.income_tag_bg') : $r('app.color.expense_tag_bg')
                            )
                            .fontColor(
                              item.type === '收入' ? $r('app.color.income_tag_text') : $r('app.color.expense_tag_text')
                            )
                            .padding({ left: 12, right: 12, top: 4, bottom: 4 })
                            .borderRadius(8)

                          Text(item.name)
                            .fontSize(16)
                            .fontColor($r('app.color.text_primary'))
                            .layoutWeight(1)
                            .margin({ left: 12 })

                          Text((item.type === '收入' ? '+' : '-') + item.amount.toFixed(2))
                            .fontSize(17)
                            .fontWeight(FontWeight.Medium)
                            .fontColor(item.type === '收入' ? $r('app.color.income_gold') : $r('app.color.expense_red'))
                            .margin({ right: 18 })

                          Image($r('sys.media.ohos_ic_public_edit'))
                            .width(18)
                            .height(18)
                            .fillColor($r('app.color.brand_blue'))
                            .onClick(() => {
                              this.openEditDialog(item);
                            })
                            .margin({ right: 16, left: 4 })

                          Image($r('sys.media.ohos_ic_public_remove'))
                            .width(18)
                            .height(18)
                            .fillColor($r('app.color.expense_red'))
                            .onClick(() => {
                              this.deleteBill(item.id);
                            })
                            .margin({ left: 4 })
                        }
                        .width('100%')

                        // ===== 第二行：标签（如果有），带分割线 =====
                        if (item.tags && item.tags.length > 0) {
                          // 分割线
                          Row() {
                            Divider()
                              .width('100%')
                              .height(0.5)
                              .color($r('app.color.border_color'))
                          }
                          .width('100%')
                          .padding({ top: 4, bottom: 4 })

                          // 标签行
                          Row() {

                            ForEach(item.tags, (tag: string) => {
                              Text('#' + tag)
                                .fontSize(11)
                                .fontColor($r('app.color.text_secondary'))
                                .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                                .backgroundColor($r('app.color.category_btn_bg'))
                                .borderRadius(8)
                                .margin({ right: 4 })
                            }, (tag: string) => tag + '_' + item.id)
                          }
                          .width('100%')
                          .padding({ left: 32 })  // 左缩进对齐到名称位置
                        }
                      }
                      .width('100%')
                      .padding({ top: 14, left: 16, bottom: 14, right: 8 })
                      .backgroundColor($r('app.color.card_bg'))
                      .borderRadius(16)
                      .shadow({ radius: 8, color: 'rgba(0, 0, 0, 0.03)', offsetX: 0, offsetY: 2 })
                      .margin({ bottom: 10 })
                      .scale({ x: this.pressedBillId === item.id ? 0.97 : 1, y: this.pressedBillId === item.id ? 0.97 : 1 })
                      .animation({ curve: AnimationConfig.SPRING })
                      .onTouch((event: TouchEvent) => {
                        if (event.type === TouchType.Down) {
                          this.pressedBillId = item.id;
                        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                          this.pressedBillId = -1;
                        }
                      })
                    }
                    .transition(this.itemTransitionEffect)
                    .onClick(() => { this.openDetailDialog(item); })
                  },
                  (item: BillItem) => item.id + '_' + this.refreshKey
                )
                ListItem() {
                  Column()
                    .width('100%')
                    .height(80)
                }
                .backgroundColor(Color.Transparent)

              }

              .width('100%')
              .backgroundColor(Color.Transparent)
              .padding({ bottom: 0 })


            }
            .width('100%')
            .layoutWeight(1)
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(16)
            .border({ width: 1, color: $r('app.color.border_color') })
            .shadow({ radius: 8, color: 'rgba(0, 0, 0, 0.04)', offsetX: 0, offsetY: 2 })
            .margin({ bottom: 16 })
          }
          .width('100%')
          .height('100%')
          .padding({ left: 20, right: 20})
          .backgroundColor($r('app.color.bg_main'))
        }
        .tabBar(this.TabBuilder('记账', 0))

        // ============================================
        // ========== 统计页（Tab 1）==========
        // ============================================
        TabContent() {
          Column() {
            Row()
              .width('100%')
              .height(10)
              .backgroundColor($r('app.color.bg_main'))
              .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
              .flexShrink(0)

            Row() {
              Text('支出统计')
                .fontSize(28)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
              Blank()
            }
            .width('100%')
            .margin({ top: 10, bottom: 4 })

            Row() {
              SymbolGlyph($r('sys.symbol.chevron_left'))
                .fontSize(22)
                .fontColor([$r('app.color.brand_blue')])
                .onClick(() => { this.goPreviousMonth(); })
                .margin({ right: 12 })

              Text(`${this.currentYear}年${this.currentMonth}月`)
                .fontSize(18)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)
                .textAlign(TextAlign.Center)

              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(22)
                .fontColor([$r('app.color.brand_blue')])
                .onClick(() => { this.goNextMonth(); })
                .margin({ left: 12 })
            }
            .width('100%')
            .margin({ bottom: 12 })

            Text(`总支出（${this.currentYear}年${this.currentMonth}月）：¥` + this.getTotalExpense().toFixed(2))
              .fontSize(16)
              .fontColor($r('app.color.expense_red'))
              .alignSelf(ItemAlign.Start)
              .margin({ bottom: 12 })



            Scroll() {
              Column() {
                Column() {
                  Row() {
                    Text('本月支出分类')
                      .fontSize(18)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_primary'))
                    Blank()
                    Text('共 ' + this.getTotalExpense().toFixed(0) + ' 元')
                      .fontSize(14)
                      .fontColor($r('app.color.text_secondary'))
                  }
                  .width('100%')
                  .margin({ bottom: 12 })

                  Canvas(this.canvasCtx)
                    .width('100%')
                    .height(280)
                    .onReady(() => {
                      setTimeout(() => {
                        this.drawPieChart();
                      }, 100);
                    })
                    .onAreaChange(() => {
                      setTimeout(() => {
                        this.drawPieChart();
                      }, 100);
                    })
                    .margin({ bottom: 12 })

                  Divider()
                    .width('100%')
                    .height(1)
                    .color($r('app.color.border_color'))
                    .margin({ bottom: 12 })

                  Column() {
                    ForEach(this.getExpenseStats(), (item: ExpenseStat) => {
                      Row() {
                        Text(item.category)
                          .fontSize(14)
                          .fontColor($r('app.color.stat_text_color'))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .constraintSize({ maxWidth: 80 })

                        Column() {
                          Column()
                            .width(Math.max((item.total / this.getTotalExpense()) * 100, 2) + '%')
                            .height(20)
                            .backgroundColor(item.color)
                            .borderRadius(12)
                        }
                        .width('100%')
                        .height(20)
                        .backgroundColor('#E8ECF0')
                        .borderRadius(12)
                        .margin({ left: 8, right: 8 })
                        .layoutWeight(1)
                        .alignItems(HorizontalAlign.Start)
                        .clip(true)

                        Text('¥' + item.total.toFixed(2))
                          .fontSize(14)
                          .fontColor($r('app.color.stat_text_light'))
                          .textAlign(TextAlign.End)
                      }
                      .width('100%')
                      .padding({ top: 6, bottom: 6 })
                      .borderRadius(8)
                    }, (item: ExpenseStat) => item.category + item.total)
                  }
                  .width('100%')
                }
                .width('100%')
                .backgroundColor($r('app.color.card_bg'))
                .borderRadius(20)
                .padding(18)
                .shadow({
                  radius: 12,
                  color: 'rgba(0, 0, 0, 0.04)',
                  offsetX: 0,
                  offsetY: 2
                })
                .margin({ bottom: 20 })


                Column() {
                  Row() {
                    Text('每日支出趋势')
                      .fontSize(18)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_primary'))
                    Blank()
                    Text('点击数据点查看详情')
                      .fontSize(12)
                      .fontColor($r('app.color.text_secondary'))
                  }
                  .width('100%')
                  .margin({ bottom: 12 })

                  Canvas(this.trendCanvasCtx)
                    .width('100%')
                    .height(200)
                    .onAreaChange((oldArea: Area, newArea: Area) => {
                      const width = newArea.width as number;
                      if (width > 0) { this.trendCanvasWidth = width; }
                      this.drawTrendChart();
                    })
                    .onClick((event: ClickEvent) => { this.handleTrendClick(event.x, event.y); })
                    .margin({ bottom: 6 })
                }
                .width('100%')
                .backgroundColor($r('app.color.card_bg'))
                .borderRadius(20)
                .padding(18)
                .shadow({ radius: 12, color: 'rgba(0, 0, 0, 0.04)', offsetX: 0, offsetY: 2 })
                .margin({ bottom: 20 })


                Column() {
                  Row() {
                    Text('年度支出趋势')
                      .fontSize(18)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_primary'))
                    Blank()
                    Row() {
                      Button('<')
                        .fontSize(16)
                        .padding({ left: 8, right: 8 })
                        .backgroundColor(Color.Transparent)
                        .fontColor($r('app.color.brand_blue'))
                        .onClick(() => {
                          this.statYear--;
                          setTimeout(() => {
                            this.drawYearlyTrendChart();
                          }, 50);
                        })
                        .margin({ right: 4 })

                      Text(this.statYear + '年')
                        .fontSize(16)
                        .fontColor($r('app.color.text_primary'))

                      Button('>')
                        .fontSize(16)
                        .padding({ left: 8, right: 8 })
                        .backgroundColor(Color.Transparent)
                        .fontColor($r('app.color.brand_blue'))
                        .onClick(() => {
                          this.statYear++;
                          setTimeout(() => {
                            this.drawYearlyTrendChart();
                          }, 50);
                        })
                        .margin({ left: 4 })
                    }
                  }
                  .width('100%')
                  .margin({ bottom: 12 })


                  Canvas(this.yearCanvasCtx)
                    .width('100%')
                    .height(200)
                    .onReady(() => {
                      setTimeout((): void => {
                        this.drawYearlyTrendChart();
                      }, 100);
                    })
                    .onAreaChange((oldArea: Area, newArea: Area) => {
                      const width = newArea.width as number;
                      if (width > 0) {
                        this.yearCanvasWidth = width;
                      }
                      this.drawYearlyTrendChart();
                    })
                    .margin({ bottom: 6 })
                }
                .width('100%')
                .backgroundColor($r('app.color.card_bg'))
                .borderRadius(20)
                .padding(18)
                .shadow({
                  radius: 12,
                  color: 'rgba(0, 0, 0, 0.04)',
                  offsetX: 0,

                  offsetY: 2
                })
                .margin({ bottom: 20 })

                Row()
                  .width('100%')

                  .height(80)
              }
              .width('100%')
              .padding({ bottom: 0 })
            }
            .width('100%')
            .layoutWeight(1)
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
            .opacity(this.statContentOpacity)
            .scale({ x: this.statContentScale, y: this.statContentScale })
          }
          .width('100%')
          .height('100%')
          .padding({ left: 20, right: 20})
          .backgroundColor($r('app.color.bg_main'))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        }
        .tabBar(this.TabBuilder('统计',1))

        // ============================================
        // ========== 日历页（Tab 2）==========
        // ============================================
        TabContent() {
            CalendarTab({ bills: $ledgerBills })
        }
        .tabBar(this.TabBuilder('日历', 2))
        // ============================================
        // ========== 账单页（Tab 3）==========
        // ============================================
        TabContent() {
          Column() {
            Row()
              .width('100%')
              .height(10)
              .backgroundColor($r('app.color.bg_main'))
              .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
              .flexShrink(0)

            Row() {
              Text('账单')
                .fontSize(28)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
              Column() {
                this.LedgerChip()
              }
              .margin({ left: 10 })
              Blank()
              Text('共 ' + this.getBillViewBills().length + ' 笔')
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
              Blank()
                .width(12)
              Image($r('sys.media.ohos_ic_public_remove'))
                .width(24)
                .height(24)
                .fillColor($r('app.color.expense_red'))
                .onClick(() => {
                  this.showDeleteConfirmDialog();
                })
            }
            .width('100%')
            .margin({ top: 10, bottom: 4 })

            Row() {
              SymbolGlyph($r('sys.symbol.chevron_left'))
                .fontSize(22)
                .fontColor([$r('app.color.brand_blue')])
                .onClick(() => { this.goPreviousMonth(); })
                .margin({ right: 12 })

              Text(`${this.billViewYear}年${this.billViewMonth}月`)
                .fontSize(18)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)
                .textAlign(TextAlign.Center)
                .onClick(() => {
                  if (this.monthPickerController) {
                    this.monthPickerController = new CustomDialogController({
                      builder: MonthPickerDialog({
                        selectedDate: new Date(this.billViewYear, this.billViewMonth - 1, 1),
                        onConfirm: (year: number, month: number) => {
                          this.billViewYear = year;
                          this.billViewMonth = month;
                        }
                      }),
                      autoCancel: true,
                      alignment: DialogAlignment.Center,
                      customStyle: true,
                      maskColor: 'rgba(0, 0, 0, 0.4)'
                    });
                    this.monthPickerController.open();
                  }
                })

              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(22)
                .fontColor([$r('app.color.brand_blue')])
                .onClick(() => { this.goBillNextMonth(); })
                .margin({ left: 12 })
            }
            .width('100%')
            .padding({ top: 8, bottom: 16 })

            Scroll() {
              Row() {
                // 1. "全部"
                Text('全部')
                  .fontSize(14)
                  .fontColor(this.billFilterCategory === '全部' ? $r('app.color.brand_blue') : $r('app.color.text_secondary'))
                  .fontWeight(this.billFilterCategory === '全部' ? FontWeight.Bold : FontWeight.Normal)
                  .padding({ left: 12, right: 12, top: 4, bottom: 4 })
                  .borderRadius(12)
                  .backgroundColor(this.billFilterCategory === '全部' ? $r('app.color.card_bg') : Color.Transparent)
                  .onClick(() => { this.billFilterCategory = '全部'; })
                  .flexShrink(0)

                // 2. 分类列表
                ForEach(this.getCurrentLedgerCategories(), (cat: string) => {
                  Text(cat)
                    .fontSize(14)
                    .fontColor(this.billFilterCategory === cat ? $r('app.color.brand_blue') : $r('app.color.text_secondary'))
                    .fontWeight(this.billFilterCategory === cat ? FontWeight.Bold : FontWeight.Normal)
                    .padding({ left: 12, right: 12, top: 4, bottom: 4 })
                    .borderRadius(12)
                    .backgroundColor(this.billFilterCategory === cat ? $r('app.color.card_bg') : Color.Transparent)
                    .onClick(() => { this.billFilterCategory = cat; })
                    .flexShrink(0)
                }, (cat: string) => cat)

                // 3. 标签分隔符
                Divider()
                  .vertical(true)
                  .height(18)
                  .color($r('app.color.border_color'))
                  .margin({ left: 8, right: 4 })
                  .flexShrink(0)

                // 4. 标签列表
                ForEach(this.getAllTags(), (tag: string) => {
                  Text('#' + tag)
                    .fontSize(14)
                    .fontColor(this.billFilterTag === tag ? $r('app.color.brand_blue') : $r('app.color.text_secondary'))
                    .fontWeight(this.billFilterTag === tag ? FontWeight.Bold : FontWeight.Normal)
                    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                    .borderRadius(12)
                    .backgroundColor(this.billFilterTag === tag ? $r('app.color.card_bg') : Color.Transparent)
                    .onClick(() => {
                      this.billFilterTag = this.billFilterTag === tag ? '' : tag;
                    })
                    .flexShrink(0)
                }, (tag: string) => tag)
              }
              .padding({ left: 4, right: 4 })  // Row 的 padding
            }  // ← Scroll 在这里闭合
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')
            .height(40)
            .padding({ bottom: 0 })

            Row()
              .width('100%')
              .height(8)

            Column() {
              List() {
                ForEach(
                  this.getBillViewBills(),
                  (item: BillItem) => {
                    ListItem() {
                      Column() {
                        // ===== 第一行：原有的所有信息 =====
                        Row() {
                          Column() { }
                          .width(8)
                          .height(8)
                          .borderRadius(4)
                          .backgroundColor(getCategoryColor(item.category))
                          .margin({ right: 12 })

                          Text(item.type)
                            .fontSize(13)
                            .backgroundColor(
                              item.type === '收入' ? $r('app.color.income_tag_bg') : $r('app.color.expense_tag_bg')
                            )
                            .fontColor(
                              item.type === '收入' ? $r('app.color.income_tag_text') : $r('app.color.expense_tag_text')
                            )
                            .padding({ left: 12, right: 12, top: 4, bottom: 4 })
                            .borderRadius(8)

                          Text(item.name)
                            .fontSize(16)
                            .fontColor($r('app.color.text_primary'))
                            .layoutWeight(1)
                            .margin({ left: 12 })

                          Text((item.type === '收入' ? '+' : '-') + item.amount.toFixed(2))
                            .fontSize(17)
                            .fontWeight(FontWeight.Medium)
                            .fontColor(item.type === '收入' ? $r('app.color.income_gold') : $r('app.color.expense_red'))
                            .margin({ right: 18 })

                          Image($r('sys.media.ohos_ic_public_edit'))
                            .width(18)
                            .height(18)
                            .fillColor($r('app.color.brand_blue'))
                            .onClick(() => {
                              this.openEditDialog(item);
                            })
                            .margin({ right: 16, left: 4 })

                          Image($r('sys.media.ohos_ic_public_remove'))
                            .width(18)
                            .height(18)
                            .fillColor($r('app.color.expense_red'))
                            .onClick(() => {
                              this.deleteBill(item.id);
                            })
                            .margin({ left: 4 })
                        }
                        .width('100%')

                        // ===== 第二行：标签（如果有），带分割线 =====
                        if (item.tags && item.tags.length > 0) {
                          // 分割线
                          Row() {
                            Divider()
                              .width('100%')
                              .height(0.5)
                              .color($r('app.color.border_color'))
                          }
                          .width('100%')
                          .padding({ top: 4, bottom: 4 })

                          // 标签行
                          Row() {

                            ForEach(item.tags, (tag: string) => {
                              Text('#' + tag)
                                .fontSize(11)
                                .fontColor($r('app.color.text_secondary'))
                                .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                                .backgroundColor($r('app.color.category_btn_bg'))
                                .borderRadius(8)
                                .margin({ right: 4 })
                            }, (tag: string) => tag + '_' + item.id)
                          }
                          .width('100%')
                          .padding({ left: 32 })  // 左缩进对齐到名称位置
                        }
                      }
                      .width('100%')
                      .padding({ top: 14, left: 16, bottom: 14, right: 8 })
                      .backgroundColor($r('app.color.card_bg'))
                      .borderRadius(16)
                      .shadow({ radius: 8, color: 'rgba(0, 0, 0, 0.03)', offsetX: 0, offsetY: 2 })
                      .margin({ bottom: 10 })
                      .scale({ x: this.pressedBillId === item.id ? 0.97 : 1, y: this.pressedBillId === item.id ? 0.97 : 1 })
                      .animation({ curve: AnimationConfig.SPRING })
                      .onTouch((event: TouchEvent) => {
                        if (event.type === TouchType.Down) {
                          this.pressedBillId = item.id;
                        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                          this.pressedBillId = -1;
                        }
                      })
                    }
                    .transition(this.itemTransitionEffect)
                    .onClick(() => { this.openDetailDialog(item); })
                  },
                  (item: BillItem) => item.id + '_' + this.refreshKey
                )
                ListItem() {
                  Column()
                    .width('100%')
                    .height(80)
                }
                .backgroundColor(Color.Transparent)
              }
              .width('100%')
              .height('100%')
              .layoutWeight(1)
              .backgroundColor(Color.Transparent)
              .padding({ bottom: 0 })
            }
            .width('100%')
            .layoutWeight(1)
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(16)
            .border({ width: 1, color: $r('app.color.border_color') })
            .shadow({ radius: 8, color: 'rgba(0, 0, 0, 0.04)', offsetX: 0, offsetY: 2 })
            .margin({ bottom: 16 })
          }
          .width('100%')
          .height('100%')
          .padding({ left: 20, right: 20 })
          .backgroundColor($r('app.color.bg_main'))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        }
        .tabBar(this.TabBuilder('账单', 3))


        // ============================================
        // ========== 我的页面（Tab 4） ==========
        // ============================================
        TabContent() {
          Column() {
            // 状态栏占位
            Row()
              .width('100%')
              .height(10)
              .backgroundColor($r('app.color.bg_main'))
              .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
              .flexShrink(0)
            Row() {
              Text('我的')
                .fontSize(28)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
              Blank()
            }
            .width('100%')
            .margin({ top: 10, bottom: 8 })

            // 可滚动内容
            Scroll() {
              Column() {
                // ===== 1. 用户信息区 =====
                Row() {
                  // 头像
                  Column() {
                    Text('乌')
                      .fontSize(30)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.text_white'))
                      .textAlign(TextAlign.Center)
                  }
                  .width(72)
                  .height(72)
                  .backgroundColor($r('app.color.brand_blue'))
                  .borderRadius(36)
                  .shadow({
                    radius: 8,
                    color: 'rgba(0,0,0,0.06)',
                    offsetX: 0,
                    offsetY: 2
                  })
                  .justifyContent(FlexAlign.Center)
                  .margin({ right: 16 })

                  // 用户信息
                  Column() {
                    Text('乌鸡用户')
                      .fontSize(20)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.text_primary'))
                    // 第一行：记账天数
                    Text(`已记账 ${this.getTotalDays()} 天`)
                      .fontSize(14)
                      .fontColor($r('app.color.text_secondary'))
                      .margin({ top: 2 })
                    // 第二行：收入/支出笔数
                    Text(`收入 ${this.getTotalIncomeCount()} 笔  ·  支出 ${this.getTotalExpenseCount()} 笔`)
                      .fontSize(14)
                      .fontColor($r('app.color.text_secondary'))
                      .margin({ top: 2 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                }
                .width('100%')
                .padding({
                  top: 16,
                  bottom: 16,
                  left: 20,
                  right: 20
                })
                .backgroundColor($r('app.color.card_bg'))
                .borderRadius(16)
                .shadow({
                  radius: 8,
                  color: 'rgba(0,0,0,0.04)',
                  offsetX: 0,
                  offsetY: 2
                })
                .margin({ top: 12,bottom: 16 })

                // ===== 2. 总资产/收支统计卡片 =====
                Row() {
                  // 总资产
                  Column() {
                    Text('总资产')
                      .fontSize(13)
                      .fontColor($r('app.color.text_secondary'))
                    Text('¥' + this.totalAsset.toFixed(2))
                      .fontSize(16)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.text_primary'))
                      .margin({ top: 2 })
                  }
                  .width('100%')
                  .padding({ top: 12, bottom: 12 })
                  .backgroundColor($r('app.color.card_bg'))
                  .borderRadius(16)
                  .shadow({
                    radius: 4,
                    color: 'rgba(0,0,0,0.02)',
                    offsetX: 0,
                    offsetY: 1
                  })
                  .layoutWeight(1)
                  .scale({ x: this.pressedCard === 'myAsset' ? 0.96 : 1, y: this.pressedCard === 'myAsset' ? 0.96 : 1 })
                  .animation({ curve: AnimationConfig.SPRING })
                  .onTouch((event: TouchEvent) => {
                    if (event.type === TouchType.Down) {
                      this.pressedCard = 'myAsset';
                    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                      this.pressedCard = '';
                    }
                  })
                  .onClick(() => {
                    router.pushUrl({ url: 'pages/AssetDetailPage' });
                  })

                  Blank().width(10)

                  // 累计收入
                  Column() {
                    Text('累计收入')
                      .fontSize(13)
                      .fontColor($r('app.color.text_secondary'))
                    Text('¥' + this.getTotalIncomeAllTime().toFixed(2))
                      .fontSize(16)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.income_gold'))
                      .margin({ top: 2 })
                  }
                  .width('100%')
                  .padding({ top: 12, bottom: 12 })
                  .backgroundColor($r('app.color.card_bg'))
                  .borderRadius(16)
                  .shadow({
                    radius: 4,
                    color: 'rgba(0,0,0,0.02)',
                    offsetX: 0,
                    offsetY: 1
                  })
                  .layoutWeight(1)

                  Blank().width(10)

                  // 累计支出
                  Column() {
                    Text('累计支出')
                      .fontSize(13)
                      .fontColor($r('app.color.text_secondary'))
                    Text('¥' + this.getTotalExpenseAllTime().toFixed(2))
                      .fontSize(16)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.expense_red'))
                      .margin({ top: 2 })
                  }
                  .width('100%')
                  .padding({ top: 12, bottom: 12 })
                  .backgroundColor($r('app.color.card_bg'))
                  .borderRadius(16)
                  .shadow({
                    radius: 4,
                    color: 'rgba(0,0,0,0.02)',
                    offsetX: 0,
                    offsetY: 1
                  })
                  .layoutWeight(1)
                }
                .width('100%')
                .margin({ bottom: 16 })

                // ===== 3. 功能入口网格（2×3） =====
                Column() {
                  Row() {
                    this.FunctionItem($r('sys.symbol.doc_text_on_doc_text'), '数据备份', () => {
                      this.exportData();
                    })
                    this.FunctionItem($r('sys.symbol.moneybag'), '预算管理', () => {
                      this.openSetBudgetDialog();
                    })
                    this.FunctionItem($r('sys.symbol.share'), '导出账单', () => {
                      this.showExportDialog();
                    })
                  }
                  .width('100%')
                  .margin({ bottom: 12 })

                  Row() {
                    this.FunctionItem($r('sys.symbol.square_and_arrow_down'), '导入账单', () => {
                      this.importWechatBills();
                    })
                    this.FunctionItem($r('sys.symbol.square_grid_2x2'), '分类管理', () => {
                      this.openCategoryManager();
                    })
                    this.FunctionItem($r('sys.symbol.label'), '标签管理', () => {
                      router.pushUrl({ url: 'pages/TagManagePage' });
                    })
                  }
                  .width('100%')
                }
                .width('100%')
                .padding({ left: 12, right: 12, top: 16, bottom: 16 })
                .backgroundColor($r('app.color.card_bg'))
                .borderRadius(16)
                .shadow({
                  radius: 8,
                  color: 'rgba(0,0,0,0.04)',
                  offsetX: 0,
                  offsetY: 2
                })
                .margin({ bottom: 16 })

                // ===== 4. 设置列表 =====
                Column() {
                  // 标题行：左对齐，但文字稍微右移一点
                  Row() {
                    Text('设置')
                      .fontSize(20)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.text_primary'))
                      .margin({ left: 4 })   // ✅ 右移 4px
                  }
                  .width('100%')
                  .margin({ bottom: 14 })    // ✅ 改为 14，与选项间距保持一致

                  // 账本管理
                  Row() {
                    SymbolGlyph($r('sys.symbol.book'))
                      .fontSize(20)
                      .fontColor([$r('app.color.text_secondary')])
                      .margin({ right: 8 })
                    Text('账本管理')
                      .fontSize(17)
                      .fontColor($r('app.color.text_primary'))
                      .layoutWeight(1)
                    SymbolGlyph($r('sys.symbol.chevron_right'))
                      .fontSize(16)
                      .fontColor([$r('app.color.text_secondary')])
                  }
                  .width('100%')
                  .padding({ top: 14, bottom: 14 })
                  .border({ width: { bottom: 1 }, color: $r('app.color.border_color') })
                  .onClick(() => {
                    router.pushUrl({ url: 'pages/LedgerManagePage' });
                  })

                  // 深色模式
                  Row() {
                    SymbolGlyph($r('sys.symbol.moon'))
                      .fontSize(20)
                      .fontColor([$r('app.color.text_secondary')])
                      .margin({ right: 8 })
                    Text('深色模式')
                      .fontSize(17)
                      .fontColor($r('app.color.text_primary'))
                      .layoutWeight(1)

                    Row() {
                      Text('浅色')
                        .fontSize(15)
                        .fontColor(this.userTheme === 'light' ? $r('app.color.brand_blue') : $r('app.color.text_secondary'))
                        .fontWeight(this.userTheme === 'light' ? FontWeight.Medium : FontWeight.Normal)
                        .padding({ left: 12, right: 12, top: 4, bottom: 4 })
                        .borderRadius(12)
                        .backgroundColor(this.userTheme === 'light' ? $r('app.color.card_bg') : Color.Transparent)
                        .onClick(() => { this.switchTheme('light'); })

                      Text('深色')
                        .fontSize(15)
                        .fontColor(this.userTheme === 'dark' ? $r('app.color.brand_blue') : $r('app.color.text_secondary'))
                        .fontWeight(this.userTheme === 'dark' ? FontWeight.Medium : FontWeight.Normal)
                        .padding({ left: 12, right: 12, top: 4, bottom: 4 })
                        .borderRadius(12)
                        .backgroundColor(this.userTheme === 'dark' ? $r('app.color.card_bg') : Color.Transparent)
                        .onClick(() => { this.switchTheme('dark'); })

                      Text('跟随系统')
                        .fontSize(15)
                        .fontColor(this.userTheme === 'system' ? $r('app.color.brand_blue') : $r('app.color.text_secondary'))
                        .fontWeight(this.userTheme === 'system' ? FontWeight.Medium : FontWeight.Normal)
                        .padding({ left: 12, right: 12, top: 4, bottom: 4 })
                        .borderRadius(12)
                        .backgroundColor(this.userTheme === 'system' ? $r('app.color.card_bg') : Color.Transparent)
                        .onClick(() => { this.switchTheme('system'); })
                    }
                  }
                  .width('100%')
                  .padding({ top: 14, bottom: 14 })
                  .border({ width: { bottom: 1 }, color: $r('app.color.border_color') })

                  // 记账提醒
                  Column() {
                    Row() {
                      SymbolGlyph($r('sys.symbol.bell'))
                        .fontSize(20)
                        .fontColor([$r('app.color.text_secondary')])
                        .margin({ right: 8 })
                      Text('记账提醒')
                        .fontSize(17)
                        .fontColor($r('app.color.text_primary'))
                      Blank()
                      Toggle({ type: ToggleType.Switch, isOn: this.isReminderOn })
                        .onChange((isOn: boolean) => {
                          // 发布失败后开关回弹会再次触发 onChange，此处忽略与当前状态一致的重复回调
                          if (isOn === this.isReminderOn) {
                            return;
                          }
                          this.isReminderOn = isOn;
                          this.onReminderToggle(isOn);
                        })
                    }
                    .width('100%')
                    .padding({ top: 14, bottom: 14 })
                    .border({ width: { bottom: 1 }, color: $r('app.color.border_color') })

                    if (this.isReminderOn) {
                      // 提醒时间
                      Row() {
                        SymbolGlyph($r('sys.symbol.clock'))
                          .fontSize(20)
                          .fontColor([$r('app.color.text_secondary')])
                          .margin({ right: 8 })
                        Text('提醒时间')
                          .fontSize(16)
                          .fontColor($r('app.color.text_primary'))
                        Blank()
                        Text(this.formatReminderTime())
                          .fontSize(16)
                          .fontWeight(FontWeight.Medium)
                          .fontColor($r('app.color.brand_blue'))
                          .margin({ right: 8 })
                        Image($r('sys.media.ohos_ic_public_arrow_right'))
                          .width(16)
                          .height(16)
                          .fillColor($r('app.color.text_secondary'))
                      }
                      .width('100%')
                      .padding({ top: 14, bottom: 14 })
                      .border({ width: { bottom: 1 }, color: $r('app.color.border_color') })
                      .onClick(() => {
                        this.showReminderTimePicker();
                      })

                      // 提醒频率
                      Row() {
                        SymbolGlyph($r('sys.symbol.calendar'))
                          .fontSize(20)
                          .fontColor([$r('app.color.text_secondary')])
                          .margin({ right: 8 })
                        Text('提醒频率')
                          .fontSize(16)
                          .fontColor($r('app.color.text_primary'))
                        Blank()
                        Text(this.formatReminderDays())
                          .fontSize(16)
                          .fontWeight(FontWeight.Medium)
                          .fontColor($r('app.color.brand_blue'))
                          .margin({ right: 8 })
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .constraintSize({ maxWidth: '45%' })
                        Image($r('sys.media.ohos_ic_public_arrow_right'))
                          .width(16)
                          .height(16)
                          .fillColor($r('app.color.text_secondary'))
                      }
                      .width('100%')
                      .padding({ top: 14, bottom: 14 })
                      .border({ width: { bottom: 1 }, color: $r('app.color.border_color') })
                      .onClick(() => {
                        this.showReminderWeekPicker();
                      })
                    }
                  }
                  .width('100%')

                  // 关于应用
                  Row() {
                    SymbolGlyph($r('sys.symbol.info_circle'))
                      .fontSize(20)
                      .fontColor([$r('app.color.text_secondary')])
                      .margin({ right: 8 })
                    Text('关于应用')
                      .fontSize(17)
                      .fontColor($r('app.color.text_primary'))
                    Blank()
                    Text('v1.2.0')
                      .fontSize(16)
                      .fontColor($r('app.color.text_secondary'))
                      .margin({ right: 8 })
                    Image($r('sys.media.ohos_ic_public_arrow_right'))
                      .width(16)
                      .height(16)
                      .fillColor($r('app.color.text_secondary'))
                  }
                  .width('100%')
                  .padding({ top: 14, bottom: 14 })
                  .onClick(() => {
                    this.showAboutDialog();
                  })
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 16, bottom: 16 })
                .backgroundColor($r('app.color.card_bg'))
                .borderRadius(16)
                .shadow({ radius: 8, color: 'rgba(0,0,0,0.04)', offsetX: 0, offsetY: 2 })
                .margin({ bottom: 16 })

                // ===== 5. 底部版本信息 =====
                Column() {
                  Text('乌鸡记账 v1.2.0 ·')
                    .fontSize(13)
                    .fontColor($r('app.color.text_secondary'))
                  Text('用心记录每一笔，养肥你的小金库')
                    .fontSize(13)
                    .fontColor($r('app.color.text_secondary'))
                }
                  .padding({ top: 8, bottom: 30 })
                  .alignSelf(ItemAlign.Center)
              }
              .width('100%')
              .padding({ bottom: 30 })
            }
            .width('100%')
            .layoutWeight(1)
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
          }
          .width('100%')
          .height('100%')
          .padding({ left: 20, right: 20 })
          .backgroundColor($r('app.color.bg_main'))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        }
        .tabBar(this.TabBuilder('我的', 4))   // ✅ Tab 索引为 3


      }

      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg_main'))
      .barOverlap(true)
      .barFloatingStyle({
        barBottomMargin: 0,
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: hdsMaterial.MaterialLevel.EXQUISITE
        }
      })
      .barHeight(50)
      .animationDuration(AnimationConfig.DURATION)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .barBackgroundColor('rgba(255, 255, 255, 0.6)')
      .barBackgroundBlurStyle(BlurStyle.Thin)
      .onChange((index: number) => {
        this.currentTabIndex = index;
        if (index === 1) {
          setTimeout(() => {
            this.drawPieChart();
            this.drawTrendChart();
          }, 50);
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_main'))
    .bindSheet($$this.showLedgerSheet, this.LedgerSheetBuilder(), {
      height: SheetSize.MEDIUM,
      dragBar: true,
      showClose: true,
      backgroundColor: $r('app.color.bg_main')
    })
  }
}

// 按逗号拆分一行 CSV，支持双引号包裹的字段与转义引号
function splitCsvLine(line: string): string[] {
  const result: string[] = [];
  let current: string = '';
  let inQuotes: boolean = false;
  for (let i: number = 0; i < line.length; i++) {
    const ch: string = line.charAt(i);
    if (inQuotes) {
      if (ch === '"') {
        if (i + 1 < line.length && line.charAt(i + 1) === '"') {
          current += '"';
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        current += ch;
      }
    } else {
      if (ch === '"') {
        inQuotes = true;
      } else if (ch === ',') {
        result.push(current);
        current = '';
      } else {
        current += ch;
      }
    }
  }
  result.push(current);
  return result;
}

// CSV 字段转义：包含逗号/引号/换行时用双引号包裹
function escapeCsvField(value: string): string {
  if (value.indexOf(',') !== -1 || value.indexOf('"') !== -1 ||
    value.indexOf('\n') !== -1 || value.indexOf('\r') !== -1) {
    return '"' + value.split('"').join('""') + '"';
  }
  return value;
}

@Concurrent
async function parseExcelInWorker(fileContent: ArrayBuffer): Promise<Array<ParsedBillData>> {
  const ExcelJS = await import('@archermind/exceljs');
  const workbook: ExcelJS.Workbook = new ExcelJS.Workbook();
  await workbook.xlsx.read(fileContent);

  const worksheet: ExcelJS.Worksheet | undefined = workbook.getWorksheet(1);
  if (!worksheet) {
    return [];
  }

  const getCellValue = (row: ExcelJS.Row, col: number): string => {
    const cell: ExcelJS.Cell = row.getCell(col);
    if (!cell) return '';
    const value: string | number | Date | undefined = cell.value as string | number | Date | undefined;
    if (value === null || value === undefined) return '';
    return String(value).trim();
  };

  let headerRowIndex: number = -1;
  const rowCount: number = worksheet.actualRowCount;
  for (let i: number = 1; i <= rowCount; i++) {
    const row: ExcelJS.Row = worksheet.getRow(i);
    const cell1: string = getCellValue(row, 1);
    const fullRow: string = getCellValue(row, 1) + getCellValue(row, 2) + getCellValue(row, 3) + getCellValue(row, 4);
    if (cell1.includes('交易时间') ||
      fullRow.includes('交易时间交易类型交易对方') ||
      fullRow.includes('交易时间交易类型交易对方商品收/支金额(元)')) {
      headerRowIndex = i;
      break;
    }
  }

  if (headerRowIndex === -1) {
    return [];
  }

  const result: Array<ParsedBillData> = [];

  for (let i: number = headerRowIndex + 1; i <= rowCount; i++) {
    const row: ExcelJS.Row = worksheet.getRow(i);
    const timeStr: string = getCellValue(row, 1);
    const transType: string = getCellValue(row, 2);
    const counterparty: string = getCellValue(row, 3);
    const name: string = getCellValue(row, 4);
    const typeStr: string = getCellValue(row, 5);
    const amountStr: string = getCellValue(row, 6);

    if (!timeStr || !amountStr) continue;
    if (typeStr === '/' || typeStr === '') continue;

    const cleanAmountStr: string = amountStr.replace(/[^0-9.-]/g, '');
    const amount: number = parseFloat(cleanAmountStr);
    if (isNaN(amount) || amount === 0) continue;

    result.push({
      timeStr: timeStr,
      transType: transType,
      counterparty: counterparty,
      name: name,
      typeStr: typeStr,
      amount: Math.abs(amount)
    });
  }

  return result;
}