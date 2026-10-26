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
import { HdsTabs, hdsMaterial, HdsTabsFloatingStyle } from '@kit.UIDesignKit';
import ExcelJS from '@archermind/exceljs';
import { taskpool } from '@kit.ArkTS';
import { router } from '@kit.ArkUI';
import { util } from '@kit.ArkTS';
import { window } from '@kit.ArkUI';
import notificationManager from '@ohos.notificationManager';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { uiAppearance } from '@kit.ArkUI';
import { CalendarTab } from './CalendarTab';
import { WealthTab } from './WealthTab';
import { CategoryManageParams } from './CategoryManagePage';
import { ASSET_PALETTE, getChartPalette, applyBrandTheme, BRAND_THEMES, BRAND_THEME_INDEX_KEY, BrandThemePreset } from '../common/AppTheme';
import {
  getLevelInfo,
  addXp,
  loadXp,
  loadUnlocked,
  checkAndUnlock,
  buildCriteriaFromPrefs,
  AchievementDef
} from '../common/Achievements';
import { getStreakMultiplier, markDailyTask, dropCoinsIntoPiggy, boostTravel, trackFortuneBill } from '../common/Gameplay';
import { trackPlaygroundOnBill } from '../common/GameplayPlus';
import { HandIcon } from '../common/HandIcon';
import { BaseCalendar } from 'base_calendar';
import { curves } from '@kit.ArkUI';
import { updateAllWidgetCards } from '../entryformability/EntryFormAbility';
import { isPinSet, savePin, clearPin, verifyPin, saveBackupPassword, isBackupSet,
  verifyBackupPassword, saveLockHint, getLockHint, saveFingerprintUnlockEnabled,
  getFingerprintUnlockEnabled, HuaweiAccountInfo, saveHuaweiAccountInfo,
  loadHuaweiAccountInfo, clearHuaweiAccountInfo } from '../common/PrivacyLock';
import { userAuth } from '@kit.UserAuthenticationKit';
import { ReminderItem, ReminderInput, ReminderCreditAccount, ReminderSavingGoal, buildReminders } from '../common/Reminders';
import { authentication } from '@kit.AccountKit';
import { pickBillPhotos, deleteBillPhotos, clearAllBillPhotos, MAX_BILL_PHOTOS } from '../common/BillPhotos';
import { hapticTick } from '../common/Haptics';
import { MotionCurves } from '../common/Motion';


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

// 云服务能力开关：置为 false 可隐藏华为账号登录、记账提醒（代理提醒）入口（如调试签名不支持时）
export const CLOUD_FEATURES_ENABLED: boolean = true;

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

// ========== 添加账单弹层（原生半模态 bindSheet，构建器见 Index.AddSheetBuilder） ==========
@Component
struct AddBillSheetContent {
  @StorageProp('brand_main') brandMain: string = '#4E6EF2';
  onClose: () => void = () => {};
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
  @State selectedPhotos: string[] = [];  // 已选小票图片
  @State pressedChipKey: string = '';  // 按压中的胶囊按钮 key（Q弹缩放反馈）
  @State cancelBtnScale: number = 1;  // 取消按钮按压缩放
  @State confirmBtnScale: number = 1;  // 添加按钮按压缩放
  submitted: boolean = false;  // 是否已提交（取消时清理未使用的图片文件）


  // 第 42 行附近
  onAddBill: (name: string, amount: number, type: '收入' | '支出', date: Date, category: string, source: string, tags: string[], photos: string[]) => void = () => {};

  // 从相册选择小票图片（拷贝到应用沙箱）
  async choosePhotos() {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const remain = MAX_BILL_PHOTOS - this.selectedPhotos.length;
      const saved = await pickBillPhotos(context, remain);
      if (saved.length > 0) {
        this.selectedPhotos = [...this.selectedPhotos, ...saved];
      }
    } catch (e) {
      console.error('选择账单图片失败: ' + JSON.stringify(e));
    }
  }

  removePhoto(index: number) {
    this.selectedPhotos = this.selectedPhotos.filter((v: string, i: number): boolean => i !== index);
  }

  aboutToDisappear() {
    // 取消添加时清理已拷贝但未随账单保存的图片文件
    if (!this.submitted && this.selectedPhotos.length > 0) {
      deleteBillPhotos(this.selectedPhotos);
    }
  }


  async loadTags() {
  try {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const prefs = await dataPreferences.getPreferences(context, 'bill_data');
    const data = await prefs.get('all_tags', '[]') as string;
    this.availableTags = JSON.parse(data) as string[];
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
        if (!this.sourceList.includes(this.selectedSource)) {
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
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 24, bottom: 20 })
        .alignSelf(ItemAlign.Start)

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
            .type(InputType.NUMBER_DECIMAL)
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
                  .scale({ x: this.pressedChipKey === ('cat_' + cat) ? 0.9 : 1, y: this.pressedChipKey === ('cat_' + cat) ? 0.9 : 1 })
                  .animation({ curve: MotionCurves.PRESS })
                  .onTouch((event: TouchEvent) => {
                    if (event.type === TouchType.Down) {
                      this.pressedChipKey = 'cat_' + cat;
                    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                      this.pressedChipKey = '';
                    }
                  })
                  .onClick(() => {
                    hapticTick();
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
                  .backgroundColor(this.selectedSource === source ? this.brandMain : $r('app.color.category_btn_bg'))
                  .fontColor(this.selectedSource === source ? $r('app.color.text_white') : $r('app.color.text_primary'))
                  .borderColor(this.selectedSource === source ? this.brandMain : 'transparent')
                  .borderWidth(1)
                  .padding({ left: 14, right: 14 })
                  .height(32)
                  .fontSize(13)
                  .margin({ right: 6, bottom: 6 })
                  .scale({ x: this.pressedChipKey === ('src_' + source) ? 0.9 : 1, y: this.pressedChipKey === ('src_' + source) ? 0.9 : 1 })
                  .animation({ curve: MotionCurves.PRESS })
                  .onTouch((event: TouchEvent) => {
                    if (event.type === TouchType.Down) {
                      this.pressedChipKey = 'src_' + source;
                    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                      this.pressedChipKey = '';
                    }
                  })
                  .onClick(() => {
                    hapticTick();
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
                .backgroundColor(this.brandMain)
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

          // 小票图片
          Column() {
            Text(`小票图片（最多${MAX_BILL_PHOTOS}张）`)
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .alignSelf(ItemAlign.Start)
              .margin({ bottom: 8 })

            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.selectedPhotos, (uri: string, idx: number) => {
                Stack({ alignContent: Alignment.TopEnd }) {
                  Image(uri)
                    .width(64)
                    .height(64)
                    .borderRadius(12)
                    .objectFit(ImageFit.Cover)
                  Row() {
                    SymbolGlyph($r('sys.symbol.xmark'))
                      .fontSize(10)
                      .fontColor([$r('app.color.text_white')])
                  }
                  .width(18)
                  .height(18)
                  .backgroundColor('rgba(0,0,0,0.55)')
                  .borderRadius(9)
                  .justifyContent(FlexAlign.Center)
                  .margin({ top: 4, right: 4 })
                  .onClick(() => { this.removePhoto(idx); })
                }
                .margin({ right: 8, bottom: 8 })
              }, (uri: string) => uri)

              if (this.selectedPhotos.length < MAX_BILL_PHOTOS) {
                Column() {
                  SymbolGlyph($r('sys.symbol.plus'))
                    .fontSize(22)
                    .fontColor([$r('app.color.text_secondary')])
                }
                .width(64)
                .height(64)
                .borderRadius(12)
                .backgroundColor($r('app.color.card_bg'))
                .border({ width: 1, color: $r('app.color.border_color'), style: BorderStyle.Dashed })
                .justifyContent(FlexAlign.Center)
                .onClick(() => { this.choosePhotos(); })
              }
            }
            .width('100%')
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
              .scale({ x: this.pressedChipKey === 'type_支出' ? 0.92 : 1, y: this.pressedChipKey === 'type_支出' ? 0.92 : 1 })
              .animation({ curve: MotionCurves.PRESS })
              .onTouch((event: TouchEvent) => {
                if (event.type === TouchType.Down) {
                  this.pressedChipKey = 'type_支出';
                } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                  this.pressedChipKey = '';
                }
              })
              .onClick(() => { hapticTick(); this.selectedType = '支出'; })

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
              .scale({ x: this.pressedChipKey === 'type_收入' ? 0.92 : 1, y: this.pressedChipKey === 'type_收入' ? 0.92 : 1 })
              .animation({ curve: MotionCurves.PRESS })
              .onTouch((event: TouchEvent) => {
                if (event.type === TouchType.Down) {
                  this.pressedChipKey = 'type_收入';
                } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                  this.pressedChipKey = '';
                }
              })
              .onClick(() => { hapticTick(); this.selectedType = '收入'; })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .margin({ bottom: 16 })

        }
        .width('100%')
        .padding({ bottom: 12 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })

      // 操作按钮固定在弹窗底部（不随内容滚动），消除内容不足一屏时底部的大段空白
      Row() {
        Button('取消')
          .backgroundColor('transparent')
          .fontColor($r('app.color.text_secondary'))
          .borderRadius(20)
          .height(40)
          .fontSize(15)
          .layoutWeight(1)
          .scale({ x: this.cancelBtnScale, y: this.cancelBtnScale })
          .animation({ curve: MotionCurves.PRESS })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              this.cancelBtnScale = 0.94;
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.cancelBtnScale = 1;
            }
          })
          .onClick(() => { this.onClose(); })

        Blank()
          .width(16)

        Button('添加')
          .backgroundColor(this.brandMain)
          .fontColor($r('app.color.text_white'))
          .borderRadius(22)
          .height(44)
          .fontSize(15)
          .layoutWeight(1)
          .scale({ x: this.confirmBtnScale, y: this.confirmBtnScale })
          .animation({ curve: MotionCurves.PRESS })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              this.confirmBtnScale = 0.93;
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.confirmBtnScale = 1;
            }
          })
          .onClick(() => {
            this.handleAddBill();
          })
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 20, bottom: 24 })
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
      this.selectedTags,
      this.selectedPhotos
    );
    this.submitted = true;
    this.onClose();
  }
}

// ========== 编辑账单弹层（原生半模态 bindSheet，构建器见 Index.EditSheetBuilder） ==========
@Component
struct EditBillSheetContent {
  @StorageProp('brand_main') brandMain: string = '#4E6EF2';
  onClose: () => void = () => {};

  billId: number = 0;
  paramName: string = '';
  paramAmount: string = '';
  paramType: '收入' | '支出' = '支出';
  paramDate: Date = new Date();
  paramCategory: string = '其他';
  paramSource: string = '现金';
  onUpdateBill: (id: number, name: string, amount: number, type: '收入' | '支出', date: Date, category: string, source: string, tags: string[], photos: string[]) => void = () => {};
  paramTags: string[] = [];
  paramPhotoUris: string[] = [];
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
  @State internalPhotos: string[] = [];
  @State pressedChipKey: string = '';  // 按压中的胶囊按钮 key（Q弹缩放反馈）
  @State cancelBtnScale: number = 1;  // 取消按钮按压缩放
  @State confirmBtnScale: number = 1;  // 保存按钮按压缩放
  submitted: boolean = false;

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
    this.internalPhotos = this.paramPhotoUris ? [...this.paramPhotoUris] : [];
    this.loadSources();
    this.loadTags();
  }

  aboutToDisappear() {
    // 取消编辑时清理新添加但未保存的图片文件
    if (!this.submitted && this.internalPhotos.length > 0) {
      const orphans: string[] = this.internalPhotos.filter((uri: string): boolean =>
        this.paramPhotoUris.indexOf(uri) === -1);
      deleteBillPhotos(orphans);
    }
  }

  // 从相册选择小票图片（拷贝到应用沙箱）
  async choosePhotos() {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const remain = MAX_BILL_PHOTOS - this.internalPhotos.length;
      const saved = await pickBillPhotos(context, remain);
      if (saved.length > 0) {
        this.internalPhotos = [...this.internalPhotos, ...saved];
      }
    } catch (e) {
      console.error('选择账单图片失败: ' + JSON.stringify(e));
    }
  }

  removePhoto(index: number) {
    this.internalPhotos = this.internalPhotos.filter((v: string, i: number): boolean => i !== index);
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

  // 在 EditBillSheetContent 中添加这些方法
  async loadTags() {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');
      const data = await prefs.get('all_tags', '[]') as string;
      console.info('📌 EditBillSheetContent 加载 all_tags:', data);
      this.availableTags = JSON.parse(data) as string[];
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
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 24, bottom: 20 })
        .alignSelf(ItemAlign.Start)

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
            .type(InputType.NUMBER_DECIMAL)
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
                  .scale({ x: this.pressedChipKey === ('cat_' + cat) ? 0.9 : 1, y: this.pressedChipKey === ('cat_' + cat) ? 0.9 : 1 })
                  .animation({ curve: MotionCurves.PRESS })
                  .onTouch((event: TouchEvent) => {
                    if (event.type === TouchType.Down) {
                      this.pressedChipKey = 'cat_' + cat;
                    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                      this.pressedChipKey = '';
                    }
                  })
                  .onClick(() => {
                    hapticTick();
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
                  .backgroundColor(this.internalSource === source ? this.brandMain : $r('app.color.category_btn_bg'))
                  .fontColor(this.internalSource === source ? $r('app.color.text_white') : $r('app.color.text_primary'))
                  .borderColor(this.internalSource === source ? this.brandMain : 'transparent')
                  .borderWidth(1)
                  .padding({ left: 14, right: 14 })
                  .height(32)
                  .fontSize(13)
                  .margin({ right: 6, bottom: 6 })
                  .scale({ x: this.pressedChipKey === ('src_' + source) ? 0.9 : 1, y: this.pressedChipKey === ('src_' + source) ? 0.9 : 1 })
                  .animation({ curve: MotionCurves.PRESS })
                  .onTouch((event: TouchEvent) => {
                    if (event.type === TouchType.Down) {
                      this.pressedChipKey = 'src_' + source;
                    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                      this.pressedChipKey = '';
                    }
                  })
                  .onClick(() => {
                    hapticTick();
                    this.internalSource = source;
                  })
              }, (source: string) => source)
            }
            .width('100%')
          }
          .width('100%')
          .margin({ bottom: 12 })
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
                .backgroundColor(this.brandMain)
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

          // 小票图片
          Column() {
            Text(`小票图片（最多${MAX_BILL_PHOTOS}张）`)
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .alignSelf(ItemAlign.Start)
              .margin({ bottom: 8 })

            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.internalPhotos, (uri: string, idx: number) => {
                Stack({ alignContent: Alignment.TopEnd }) {
                  Image(uri)
                    .width(64)
                    .height(64)
                    .borderRadius(12)
                    .objectFit(ImageFit.Cover)
                  Row() {
                    SymbolGlyph($r('sys.symbol.xmark'))
                      .fontSize(10)
                      .fontColor([$r('app.color.text_white')])
                  }
                  .width(18)
                  .height(18)
                  .backgroundColor('rgba(0,0,0,0.55)')
                  .borderRadius(9)
                  .justifyContent(FlexAlign.Center)
                  .margin({ top: 4, right: 4 })
                  .onClick(() => { this.removePhoto(idx); })
                }
                .margin({ right: 8, bottom: 8 })
              }, (uri: string) => uri)

              if (this.internalPhotos.length < MAX_BILL_PHOTOS) {
                Column() {
                  SymbolGlyph($r('sys.symbol.plus'))
                    .fontSize(22)
                    .fontColor([$r('app.color.text_secondary')])
                }
                .width(64)
                .height(64)
                .borderRadius(12)
                .backgroundColor($r('app.color.card_bg'))
                .border({ width: 1, color: $r('app.color.border_color'), style: BorderStyle.Dashed })
                .justifyContent(FlexAlign.Center)
                .onClick(() => { this.choosePhotos(); })
              }
            }
            .width('100%')
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
              .scale({ x: this.pressedChipKey === 'type_支出' ? 0.92 : 1, y: this.pressedChipKey === 'type_支出' ? 0.92 : 1 })
              .animation({ curve: MotionCurves.PRESS })
              .onTouch((event: TouchEvent) => {
                if (event.type === TouchType.Down) {
                  this.pressedChipKey = 'type_支出';
                } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                  this.pressedChipKey = '';
                }
              })
              .onClick(() => { hapticTick(); this.internalType = '支出'; })

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
              .scale({ x: this.pressedChipKey === 'type_收入' ? 0.92 : 1, y: this.pressedChipKey === 'type_收入' ? 0.92 : 1 })
              .animation({ curve: MotionCurves.PRESS })
              .onTouch((event: TouchEvent) => {
                if (event.type === TouchType.Down) {
                  this.pressedChipKey = 'type_收入';
                } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                  this.pressedChipKey = '';
                }
              })
              .onClick(() => { hapticTick(); this.internalType = '收入'; })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .margin({ bottom: 16 })

        }
        .width('100%')
        .padding({ bottom: 12 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })

      // 操作按钮固定在弹窗底部（不随内容滚动），消除内容不足一屏时底部的大段空白
      Row() {
        Button('取消')
          .backgroundColor('transparent')
          .fontColor($r('app.color.text_secondary'))
          .borderRadius(20)
          .height(40)
          .fontSize(15)
          .layoutWeight(1)
          .scale({ x: this.cancelBtnScale, y: this.cancelBtnScale })
          .animation({ curve: MotionCurves.PRESS })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              this.cancelBtnScale = 0.94;
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.cancelBtnScale = 1;
            }
          })
          .onClick(() => { this.onClose(); })

        Blank()
          .width(16)

        Button('保存')
          .backgroundColor(this.brandMain)
          .fontColor($r('app.color.text_white'))
          .borderRadius(22)
          .height(44)
          .fontSize(15)
          .layoutWeight(1)
          .scale({ x: this.confirmBtnScale, y: this.confirmBtnScale })
          .animation({ curve: MotionCurves.PRESS })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              this.confirmBtnScale = 0.93;
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.confirmBtnScale = 1;
            }
          })
          .onClick(() => {
            this.handleUpdateBill();
          })
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 20, bottom: 24 })
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
      this.selectedTags,  // ✅ 传入标签
      this.internalPhotos  // ✅ 传入小票图片
    );
    this.submitted = true;
    this.onClose();
  }
}

// ========== 搜索账单弹层（原生半模态 bindSheet，构建器见 Index.SearchSheetBuilder） ==========
// V2 状态管理：@Local 内部搜索词状态 + @Param 父组件数据/回调
@ComponentV2
struct SearchBillSheetContent {
  @Param onClose: () => void = () => {};
  @Local searchText: string = '';
  @Param bills: BillItem[] = [];
  @Param onSelectBill: (bill: BillItem) => void = (bill: BillItem) => {};

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
      Text('搜索账单')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .alignSelf(ItemAlign.Start)
        .margin({ top: 24, bottom: 20 })

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
              this.onClose();
            })
          },
          (item: BillItem) => item.id.toString()
        )

        // 空状态：结果为空时给出提示，避免底部大片留白
        if (this.getFilteredBills().length === 0) {
          ListItem() {
            Column({ space: 10 }) {
              Text(this.searchText.trim().length > 0 ? '没有找到相关账单' : '还没有账单，去记一笔吧')
                .fontSize(15)
                .fontColor($r('app.color.text_secondary'))
              Text(this.searchText.trim().length > 0 ? '换个关键词试试' : '点右下角记一笔开始记账')
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .opacity(0.7)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
            .padding({ top: 72, bottom: 24 })
          }
        }
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor(Color.Transparent)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 20, bottom: 8 })
  }
}

// ========== 账单详情弹窗 ==========
@CustomDialog
struct BillDetailDialog {
  @StorageProp('brand_main') brandMain: string = '#4E6EF2';
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
  @State previewUri: string = '';
  // 独立显隐状态：侧滑返回关闭全屏预览时由 $$ 双向绑定自动复位，避免条件卡死无法再次打开
  @State previewShow: boolean = false;

  formatDate(timestamp: number): string {
    const d = new Date(timestamp);
    return d.getFullYear() + '年' + (d.getMonth() + 1) + '月' + d.getDate() + '日';
  }

  closePhotoPreview(): void {
    this.previewShow = false;
    this.previewUri = '';
  }

  // 全屏预览小票图片
  @Builder
  PhotoPreviewBuilder() {
    Column() {
      Image(this.previewUri)
        .objectFit(ImageFit.Contain)
        .width('100%')
        .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(0,0,0,0.92)')
    .justifyContent(FlexAlign.Center)
    .onClick(() => { this.closePhotoPreview(); })
  }

  build() {
    Column() {
      Row() {
        Text('账单详情')
          .fontSize(20)
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

      if (this.bill.refundAmount !== undefined && this.bill.refundAmount > 0) {
        Text('原支付 ¥' + (this.bill.originalAmount !== undefined ? this.bill.originalAmount : this.bill.amount + this.bill.refundAmount).toFixed(2) +
          ' · 已退款 ¥' + this.bill.refundAmount.toFixed(2))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .alignSelf(ItemAlign.End)
          .margin({ bottom: 4 })
      }

      Text(this.formatDate(this.bill.date))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .alignSelf(ItemAlign.End)
        .margin({ bottom: 20 })

      // 小票图片
      if (this.bill.photoUris && this.bill.photoUris.length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.bill.photoUris, (uri: string) => {
            Image(uri)
              .width(72)
              .height(72)
              .borderRadius(12)
              .objectFit(ImageFit.Cover)
              .margin({ right: 8, bottom: 8 })
              .onClick(() => { this.previewUri = uri; this.previewShow = true; })
          }, (uri: string) => uri)
        }
        .width('100%')
        .margin({ bottom: 12 })
      }

      Button('编辑')
        .width('100%')
        .height(44)
        .backgroundColor(this.brandMain)
        .fontColor($r('app.color.text_white'))
        .borderRadius(22)
        .fontSize(15)
        .onClick(() => {
          this.controller.close();
          if (this.onEdit) {
            this.onEdit(this.bill);
          }
        })
    }
    .width('85%')
    .padding(20)
    .backgroundColor($r('app.color.glass_bg'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .borderRadius(24)
    .bindContentCover($$this.previewShow, this.PhotoPreviewBuilder(), {
      // 侧滑返回/点击关闭后复位状态，保证可以再次点开预览
      onDisappear: () => { this.closePhotoPreview(); }
    })
  }
}

// ========== 每日支出详情弹窗 ==========
@CustomDialog
struct DayDetailDialog {
  @StorageProp('brand_main') brandMain: string = '#4E6EF2';
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
        .fontSize(20)
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
        .height(44)
        .backgroundColor(this.brandMain)
        .fontColor($r('app.color.text_white'))
        .borderRadius(22)
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
    .backgroundColor($r('app.color.glass_bg'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .borderRadius(24)
  }
}


// ========== 多日支出详情弹窗 ==========
@CustomDialog
struct MultiDayDetailDialog {
  @StorageProp('brand_main') brandMain: string = '#4E6EF2';
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
        .fontSize(20)
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
        .height(44)
        .backgroundColor(this.brandMain)
        .fontColor($r('app.color.text_white'))
        .borderRadius(22)
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
    .backgroundColor($r('app.color.glass_bg'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .borderRadius(24)
  }
}

// ========== 导出确认弹窗 ==========
@CustomDialog
struct ExportConfirmDialog {
  @StorageProp('brand_main') brandMain: string = '#4E6EF2';
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
          .backgroundColor(this.brandMain)
          .fontColor($r('app.color.text_white'))
          .borderRadius(22)
          .height(44)
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
    .backgroundColor($r('app.color.glass_bg'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .borderRadius(24)
  }
}

// ========== 隐私锁 PIN 设置弹窗（两步：输入 + 确认） ==========
@CustomDialog
struct PinSetupDialog {
  @StorageProp('brand_main') brandMain: string = '#4E6EF2';
  controller: CustomDialogController = new CustomDialogController({
    builder: () => {}
  });
  @State step: number = 1;
  @State firstPin: string = '';
  @State input: string = '';
  @State visible: boolean = false;
  @State errorText: string = '';
  @State shakeX: number = 0;
  @State pressedKey: string = '';
  @State backupInput: string = '';
  @State backupErrorText: string = '';
  @State hintInput: string = '';
  // 步骤左右切换：前进时新页从右滑入(slideInX)、旧页向左滑出(slideOutX)，后退相反
  @State slideInX: number = 96;
  @State slideOutX: number = -96;
  onDone: (pin: string, backup: string, hint: string) => void = () => {};

  private pressKey(key: string) {
    if (this.input.length >= 6) {
      return;
    }
    this.input += key;
    this.errorText = '';
    if (this.input.length === 6) {
      this.handleFull();
    }
  }

  private deleteKey() {
    if (this.input.length === 0) {
      return;
    }
    this.input = this.input.substring(0, this.input.length - 1);
    this.errorText = '';
  }

  private handleFull() {
    if (this.step === 1) {
      this.firstPin = this.input;
      this.input = '';
      this.errorText = '';
      this.goStep(2);
    } else {
      if (this.input !== this.firstPin) {
        this.errorText = '两次输入不一致，请重新设置';
        this.shake();
        // 后退回第 1 步：旧页向右滑出、新页从左滑入
        this.slideInX = -96;
        this.slideOutX = 96;
        setTimeout(() => {
          this.input = '';
          this.firstPin = '';
          animateTo({ duration: 320, curve: AnimationConfig.SPRING_SOFT }, () => {
            this.step = 1;
          });
        }, 350);
        return;
      }
      // 数字密码确认完成，进入备用密码步骤
      this.input = '';
      this.errorText = '';
      this.goStep(3);
    }
  }

  // 前进到下一步：先更新滑入/滑出方向并渲染一帧，再切换步骤触发左右滑动转场
  private goStep(next: number) {
    this.slideInX = 96;
    this.slideOutX = -96;
    setTimeout(() => {
      animateTo({ duration: 320, curve: AnimationConfig.SPRING_SOFT }, () => {
        this.step = next;
      });
    }, 40);
  }

  // 步骤页转场：出现时从 slideInX 一侧滑入，消失时向 slideOutX 一侧滑出
  private stepSlideEffect(): TransitionEffect {
    return TransitionEffect.asymmetric(
      TransitionEffect.OPACITY.animation({ duration: 320, curve: AnimationConfig.SPRING_SOFT })
        .combine(TransitionEffect.translate({ x: this.slideInX })),
      TransitionEffect.OPACITY.animation({ duration: 320, curve: AnimationConfig.SPRING_SOFT })
        .combine(TransitionEffect.translate({ x: this.slideOutX }))
    );
  }

  private finishBackup() {
    const backup = this.backupInput.trim();
    if (backup.length === 0) {
      this.backupErrorText = '请输入备用密码';
      return;
    }
    this.controller.close();
    this.onDone(this.firstPin, backup, this.hintInput.trim());
  }

  private shake() {
    animateTo({ duration: 70, curve: Curve.EaseInOut }, () => {
      this.shakeX = -12;
    });
    setTimeout(() => {
      animateTo({ duration: 70, curve: Curve.EaseInOut }, () => {
        this.shakeX = 12;
      });
    }, 70);
    setTimeout(() => {
      animateTo({ duration: 70, curve: Curve.EaseInOut }, () => {
        this.shakeX = -6;
      });
    }, 140);
    setTimeout(() => {
      animateTo({ duration: 70, curve: Curve.EaseInOut }, () => {
        this.shakeX = 0;
      });
    }, 210);
  }

  @Builder
  PinKeyBuilder(key: string) {
    Text(key)
      .fontSize(24)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_primary'))
      .width(64)
      .height(64)
      .textAlign(TextAlign.Center)
      .backgroundColor(this.pressedKey === key ? this.brandMain : $r('app.color.bg_main'))
      .fontColor(this.pressedKey === key ? $r('app.color.text_white') : $r('app.color.text_primary'))
      .borderRadius(32)
      .scale({
        x: this.pressedKey === key ? 0.88 : 1,
        y: this.pressedKey === key ? 0.88 : 1
      })
      .animation({ duration: 120, curve: Curve.Friction })
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.pressedKey = key;
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.pressedKey = '';
          if (event.type === TouchType.Up) {
            this.pressKey(key);
          }
        }
      })
  }

  @Builder
  PinKeyRow(keys: string[]) {
    Row({ space: 14 }) {
      ForEach(keys, (k: string) => {
        this.PinKeyBuilder(k)
      }, (k: string) => k)
    }
  }

  @Builder
  SetupStepHeaderBuilder(title: string, subtitle: string) {
    Column() {
      Text(title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))

      Row({ space: 6 }) {
        Row()
          .width(20)
          .height(4)
          .borderRadius(2)
          .backgroundColor(this.step === 1 ? this.brandMain : $r('app.color.border_color'))
        Row()
          .width(20)
          .height(4)
          .borderRadius(2)
          .backgroundColor(this.step === 2 ? this.brandMain : $r('app.color.border_color'))
        Row()
          .width(20)
          .height(4)
          .borderRadius(2)
          .backgroundColor(this.step === 3 ? this.brandMain : $r('app.color.border_color'))
      }
      .margin({ top: 10 })

      Text(subtitle)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 6 })
    }
  }

  // 步骤 1/2 共用的密码键盘内容
  @Builder
  PinKeypadContentBuilder() {
      Row({ space: 10 }) {
        ForEach([0, 1, 2, 3, 4, 5], (i: number) => {
          Column() {
            if (i < this.input.length) {
              Text(this.visible ? this.input.substring(i, i + 1) : '●')
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                .transition(TransitionEffect.OPACITY
                  .combine(TransitionEffect.scale({ x: 0.4, y: 0.4 }))
                  .animation({ duration: 180, curve: Curve.Friction }))
            }
          }
          .width(36)
          .height(42)
          .justifyContent(FlexAlign.Center)
          .backgroundColor($r('app.color.bg_main'))
          .borderRadius(10)
          .border({
            width: 1.5,
            color: i < this.input.length ? this.brandMain : $r('app.color.border_color')
          })
        }, (i: number) => i.toString())
      }
      .margin({ top: 20 })
      .translate({ x: this.shakeX })

      Row() {
        SymbolGlyph(this.visible ? $r('sys.symbol.eye_slash') : $r('sys.symbol.eye'))
          .fontSize(16)
          .fontColor([$r('app.color.text_secondary')])
        Text(this.visible ? '隐藏密码' : '显示密码')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .margin({ left: 4 })
      }
      .margin({ top: 14 })
      .onClick(() => {
        this.visible = !this.visible;
      })

      if (this.errorText.length > 0) {
        Text(this.errorText)
          .fontSize(13)
          .fontColor($r('app.color.expense_red'))
          .margin({ top: 10 })
          .transition(TransitionEffect.OPACITY.animation({ duration: 150 }))
      }

      Column({ space: 12 }) {
        this.PinKeyRow(['1', '2', '3'])
        this.PinKeyRow(['4', '5', '6'])
        this.PinKeyRow(['7', '8', '9'])
        Row({ space: 14 }) {
          Column() {
          }
          .width(64)
          .height(64)

          this.PinKeyBuilder('0')

          Column() {
            SymbolGlyph($r('sys.symbol.delete_left_fill'))
              .fontSize(24)
              .fontColor([$r('app.color.text_secondary')])
          }
          .width(64)
          .height(64)
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.deleteKey();
          })
        }
      }
      .margin({ top: 20 })

      Text('取消')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 14 })
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .onClick(() => {
          this.controller.close();
        })
  }

  // 步骤 3 的备用密码 + 密码提示内容
  @Builder
  BackupContentBuilder() {
        TextInput({ placeholder: '请输入备用密码', text: this.backupInput })
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .height(48)
          .fontSize(16)
          .backgroundColor($r('app.color.bg_main'))
          .borderRadius(12)
          .border({ width: 1, color: $r('app.color.border_color') })
          .padding({ left: 16, right: 16 })
          .margin({ top: 20 })
          .onChange((val: string) => {
            this.backupInput = val;
            this.backupErrorText = '';
          })
          .onSubmit(() => {
            this.finishBackup();
          })

        Text('密码提示（选填，忘记密码时显示）')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .alignSelf(ItemAlign.Start)
          .margin({ top: 16 })

        TextInput({ placeholder: '例如：我的生日', text: this.hintInput })
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .height(44)
          .fontSize(14)
          .backgroundColor($r('app.color.bg_main'))
          .borderRadius(12)
          .border({ width: 1, color: $r('app.color.border_color') })
          .padding({ left: 16, right: 16 })
          .margin({ top: 8 })
          .maxLength(30)
          .onChange((val: string) => {
            this.hintInput = val;
          })

        if (this.backupErrorText.length > 0) {
          Text(this.backupErrorText)
            .fontSize(13)
            .fontColor($r('app.color.expense_red'))
            .margin({ top: 10 })
            .transition(TransitionEffect.OPACITY.animation({ duration: 150 }))
        }

        Button('完成')
          .width('100%')
          .height(44)
          .fontSize(16)
          .backgroundColor(this.brandMain)
          .fontColor($r('app.color.text_white'))
          .borderRadius(22)
          .margin({ top: 20 })
          .onClick(() => {
            this.finishBackup();
          })

        Text('取消')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 14 })
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .onClick(() => {
            this.controller.close();
          })
  }

  build() {
    Column() {
      if (this.step === 1) {
        Column() {
          SymbolGlyph($r('sys.symbol.lock'))
            .fontSize(40)
            .fontColor([this.brandMain])
            .margin({ bottom: 10 })
          this.SetupStepHeaderBuilder('设置隐私密码', '请输入 6 位数字密码')
          this.PinKeypadContentBuilder()
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .transition(this.stepSlideEffect())
      } else if (this.step === 2) {
        Column() {
          SymbolGlyph($r('sys.symbol.lock'))
            .fontSize(40)
            .fontColor([this.brandMain])
            .margin({ bottom: 10 })
          this.SetupStepHeaderBuilder('确认隐私密码', '请再次输入刚才的密码')
          this.PinKeypadContentBuilder()
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .transition(this.stepSlideEffect())
      } else {
        Column() {
          SymbolGlyph($r('sys.symbol.key'))
            .fontSize(40)
            .fontColor([this.brandMain])
            .margin({ bottom: 10 })
          this.SetupStepHeaderBuilder('设置备用密码', '忘记数字密码时可用它解锁，无位数限制')
          this.BackupContentBuilder()
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .transition(this.stepSlideEffect())
      }
    }
    .alignItems(HorizontalAlign.Center)
    .width('88%')
    .padding({ top: 28, bottom: 18, left: 20, right: 20 })
    .backgroundColor($r('app.color.glass_bg'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .borderRadius(28)
    .clip(true)
  }
}

// ========== 验证隐私锁密码弹窗（关闭/敏感操作前验证） ==========
@CustomDialog
struct PinVerifyDialog {
  @StorageProp('brand_main') brandMain: string = '#4E6EF2';
  controller: CustomDialogController = new CustomDialogController({
    builder: () => {}
  });
  @State input: string = '';
  @State errorText: string = '';
  @State shakeX: number = 0;
  @State dotsError: boolean = false;
  @State pressedKey: string = '';
  @State mode: number = 0;
  @State backupInput: string = '';
  @State hintText: string = '';
  @State hasBackup: boolean = false;
  title: string = '验证密码';
  contextProvider: () => common.UIAbilityContext | undefined = () => undefined;
  onVerified: () => void = () => {};

  aboutToAppear() {
    this.init();
  }

  async init(): Promise<void> {
    const context = this.contextProvider();
    if (!context) {
      return;
    }
    this.hintText = await getLockHint(context);
    this.hasBackup = await isBackupSet(context);
  }

  private pressKey(key: string) {
    if (this.input.length >= 6) {
      return;
    }
    this.input += key;
    this.errorText = '';
    if (this.input.length === 6) {
      this.tryVerifyPin();
    }
  }

  private deleteKey() {
    if (this.input.length > 0) {
      this.input = this.input.substring(0, this.input.length - 1);
      this.errorText = '';
    }
  }

  private shake() {
    animateTo({ duration: 70, curve: Curve.EaseInOut }, () => {
      this.shakeX = -12;
    });
    setTimeout(() => {
      animateTo({ duration: 70, curve: Curve.EaseInOut }, () => {
        this.shakeX = 12;
      });
    }, 70);
    setTimeout(() => {
      animateTo({ duration: 70, curve: Curve.EaseInOut }, () => {
        this.shakeX = -6;
      });
    }, 140);
    setTimeout(() => {
      animateTo({ duration: 70, curve: Curve.EaseInOut }, () => {
        this.shakeX = 0;
      });
    }, 210);
  }

  async tryVerifyPin(): Promise<void> {
    const context = this.contextProvider();
    if (!context) {
      return;
    }
    const ok = await verifyPin(context, this.input);
    if (ok) {
      this.controller.close();
      this.onVerified();
    } else {
      this.input = '';
      this.errorText = '密码错误，请重试';
      this.dotsError = true;
      this.shake();
      setTimeout(() => {
        this.dotsError = false;
      }, 600);
    }
  }

  async tryVerifyBackup(): Promise<void> {
    const pwd = this.backupInput.trim();
    if (pwd.length === 0) {
      this.errorText = '请输入备用密码';
      return;
    }
    const context = this.contextProvider();
    if (!context) {
      return;
    }
    const ok = await verifyBackupPassword(context, pwd);
    if (ok) {
      this.controller.close();
      this.onVerified();
    } else {
      this.backupInput = '';
      this.errorText = '备用密码错误，请重试';
    }
  }

  @Builder
  VerifyKeyBuilder(key: string) {
    Text(key)
      .fontSize(24)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.pressedKey === key ? $r('app.color.text_white') : $r('app.color.text_primary'))
      .width(64)
      .height(64)
      .textAlign(TextAlign.Center)
      .backgroundColor(this.pressedKey === key ? this.brandMain : $r('app.color.bg_main'))
      .borderRadius(32)
      .scale({
        x: this.pressedKey === key ? 0.88 : 1,
        y: this.pressedKey === key ? 0.88 : 1
      })
      .animation({ duration: 120, curve: Curve.Friction })
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.pressedKey = key;
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.pressedKey = '';
          if (event.type === TouchType.Up) {
            this.pressKey(key);
          }
        }
      })
  }

  @Builder
  VerifyKeyRow(keys: string[]) {
    Row({ space: 14 }) {
      ForEach(keys, (k: string) => {
        this.VerifyKeyBuilder(k)
      }, (k: string) => k)
    }
  }

  build() {
    Column() {
      SymbolGlyph(this.mode === 0 ? $r('sys.symbol.lock') : $r('sys.symbol.key'))
        .fontSize(40)
        .fontColor([this.brandMain])
        .margin({ bottom: 10 })

      Text(this.title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))

      if (this.mode === 0) {
        Text('请输入数字密码以继续')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 6 })

        Row({ space: 10 }) {
          ForEach([0, 1, 2, 3, 4, 5], (i: number) => {
            Column() {
              if (i < this.input.length) {
                Column() {
                }
                .width(12)
                .height(12)
                .borderRadius(6)
                .backgroundColor(this.dotsError ? $r('app.color.expense_red') : this.brandMain)
                .transition(TransitionEffect.OPACITY
                  .combine(TransitionEffect.scale({ x: 0.2, y: 0.2 }))
                  .animation({ duration: 200, curve: AnimationConfig.SPRING }))
              }
            }
            .width(18)
            .height(18)
            .borderRadius(9)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .border({
              width: 1.5,
              color: i < this.input.length
                ? (this.dotsError ? $r('app.color.expense_red') : this.brandMain)
                : $r('app.color.border_color')
            })
          }, (i: number) => i.toString() + (this.dotsError ? '_e' : ''))
        }
        .margin({ top: 20 })
        .translate({ x: this.shakeX })

        if (this.errorText.length > 0) {
          Text(this.errorText)
            .fontSize(13)
            .fontColor($r('app.color.expense_red'))
            .margin({ top: 10 })
            .transition(TransitionEffect.OPACITY.animation({ duration: 150 }))
        }

        Column({ space: 12 }) {
          this.VerifyKeyRow(['1', '2', '3'])
          this.VerifyKeyRow(['4', '5', '6'])
          this.VerifyKeyRow(['7', '8', '9'])
          Row({ space: 14 }) {
            Column() {
            }
            .width(64)
            .height(64)

            this.VerifyKeyBuilder('0')

            Column() {
              SymbolGlyph($r('sys.symbol.delete_left_fill'))
                .fontSize(24)
                .fontColor([$r('app.color.text_secondary')])
            }
            .width(64)
            .height(64)
            .justifyContent(FlexAlign.Center)
            .onClick(() => {
              this.deleteKey();
            })
          }
        }
        .margin({ top: 20 })

        Row({ space: 28 }) {
          if (this.hasBackup) {
            Text('使用备用密码')
              .fontSize(13)
              .fontColor(this.brandMain)
              .onClick(() => {
                this.mode = 1;
                this.errorText = '';
              })
          }
          Text('取消')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .onClick(() => {
              this.controller.close();
            })
        }
        .margin({ top: 14 })
      } else {
        if (this.hintText.length > 0) {
          Text(`提示：${this.hintText}`)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .padding({ left: 14, right: 14, top: 8, bottom: 8 })
            .backgroundColor($r('app.color.bg_main'))
            .borderRadius(14)
            .margin({ top: 14 })
        } else {
          Text('请输入设置时填写的备用密码')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 14 })
        }

        TextInput({ placeholder: '请输入备用密码', text: this.backupInput })
          .type(InputType.Normal)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .height(48)
          .fontSize(16)
          .backgroundColor($r('app.color.bg_main'))
          .borderRadius(12)
          .border({ width: 1, color: $r('app.color.border_color') })
          .padding({ left: 16, right: 16 })
          .margin({ top: 20 })
          .onChange((val: string) => {
            this.backupInput = val;
            this.errorText = '';
          })
          .onSubmit(() => {
            this.tryVerifyBackup();
          })

        if (this.errorText.length > 0) {
          Text(this.errorText)
            .fontSize(13)
            .fontColor($r('app.color.expense_red'))
            .margin({ top: 10 })
            .transition(TransitionEffect.OPACITY.animation({ duration: 150 }))
        }

        Button('验证')
          .width('100%')
          .height(44)
          .fontSize(16)
          .backgroundColor(this.brandMain)
          .fontColor($r('app.color.text_white'))
          .borderRadius(22)
          .margin({ top: 20 })
          .onClick(() => {
            this.tryVerifyBackup();
          })

        Row({ space: 28 }) {
          Text('返回数字密码')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .onClick(() => {
              this.mode = 0;
              this.errorText = '';
            })
          Text('取消')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .onClick(() => {
              this.controller.close();
            })
        }
        .margin({ top: 14 })
      }
    }
    .alignItems(HorizontalAlign.Center)
    .width('88%')
    .padding({ top: 28, bottom: 18, left: 20, right: 20 })
    .backgroundColor($r('app.color.glass_bg'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .borderRadius(28)
  }
}

// ========== 设置预算弹窗 ==========
@CustomDialog
struct SetBudgetDialog {
  @StorageProp('brand_main') brandMain: string = '#4E6EF2';
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
          .type(InputType.NUMBER_DECIMAL)
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
          .backgroundColor(this.brandMain)
          .fontColor($r('app.color.text_white'))
          .borderRadius(22)
          .height(44)
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
    .backgroundColor($r('app.color.glass_bg'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .borderRadius(24)
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
    .backgroundColor($r('app.color.glass_bg'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .borderRadius({ topLeft: 26, topRight: 23, bottomLeft: 25, bottomRight: 27 })
    .shadow({ radius: 0, color: $r('app.color.ink_shadow'), offsetX: 3, offsetY: 3 }).border({ width: 1, color: $r('app.color.ink_line') })
  }
}

// ========== 记账提醒频率弹窗 ==========
@CustomDialog
struct WeekPickerDialog {
  @StorageProp('brand_main') brandMain: string = '#4E6EF2';
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
          .fontColor(this.brandMain)
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .borderRadius(16)
          .backgroundColor($r('app.color.card_bg'))
          .border({ width: 1, color: $r('app.color.border_color') })
          .onClick(() => { this.setQuickPick([1, 2, 3, 4, 5, 6, 7]); })

        Text('工作日')
          .fontSize(14)
          .fontColor(this.brandMain)
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .borderRadius(16)
          .backgroundColor($r('app.color.card_bg'))
          .border({ width: 1, color: $r('app.color.border_color') })
          .onClick(() => { this.setQuickPick([1, 2, 3, 4, 5]); })

        Text('周末')
          .fontSize(14)
          .fontColor(this.brandMain)
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
            .backgroundColor(this.isDayChosen(index + 1) ? this.brandMain : $r('app.color.card_bg'))
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
          .backgroundColor(this.brandMain)
          .fontColor($r('app.color.text_white'))
          .borderRadius(22)
          .height(44)
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
    .backgroundColor($r('app.color.glass_bg'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .borderRadius(24)
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
  recurringKey?: string;  // 周期账单生成标记（r{规则id}_{yyyy-MM-dd}），用于幂等去重
  photoUris?: string[];  // 小票/凭证图片（应用沙箱 file:// URI）
  refundAmount?: number;   // 累计退款金额（有退款抵扣时存在）
  originalAmount?: number; // 原始支付金额（有退款抵扣时存在）
  orderNo?: string;        // 商户单号/商家订单号（微信/支付宝导入时存在，用于退款精确匹配）
}

// 回收站条目：被删除的账单 + 删除时间
export interface RecycleBillItem {
  bill: BillItem;
  deletedAt: number;  // 删除时间戳
}

const RECYCLE_BIN_KEY: string = 'recycle_bills';
const RECYCLE_RETENTION_DAYS: number = 30;
const RECYCLE_RETENTION_MS: number = RECYCLE_RETENTION_DAYS * 24 * 60 * 60 * 1000;

// 周期/重复账单规则
export interface RecurringBill {
  id: number;
  name: string;
  amount: number;
  type: '收入' | '支出';
  category: string;
  source: string;
  freqType: 'weekly' | 'monthly' | 'yearly';
  dayOfWeek: number;   // 1-7（周一~周日），weekly 用
  dayOfMonth: number;  // 1-31，monthly/yearly 用
  monthOfYear: number; // 1-12，yearly 用
  startDate: number;   // 生效日（含当天）
  endDate: number;     // 0 = 无限期
  enabled: boolean;
  ledgerId: number;
  createdAt: number;
}

// 账单页：按日期分组的账单
export interface DayBillGroup {
  date: number;        // 当日零点时间戳
  dayExpense: number;  // 当日支出合计
  dayIncome: number;   // 当日收入合计
  bills: BillItem[];
}

interface ParsedBillData {
  timeStr: string;
  transType: string;
  counterparty: string;
  name: string;
  typeStr: string;
  amount: number;
  refundAmount: number; // 文件内退款已抵扣的金额
  orderNo: string; // 商户单号（用于退款按订单精确匹配）
}

// 本应用导出 CSV 中的一行账单
interface CsvBillRow {
  date: number;
  type: '收入' | '支出';
  category: string;
  name: string;
  amount: number;
  ledgerName: string;
  refundAmount: number; // 文件内退款已抵扣的金额
  orderNo: string; // 商家订单号（支付宝导入用，本应用导出为空）
  source: string;  // 资金来源账户（本应用导出列；支付宝账单无此列，留空后回退）
  tags: string[];  // 标签（本应用导出列），分号分隔
}

// 导入微信/支付宝账单时识别到的一笔退款
interface ParsedRefund {
  date: number;          // 退款交易时间
  amount: number;        // 退款金额
  counterparty: string;  // 微信交易对方（支付宝为空）
  product: string;       // 商品/商品说明
  source: string;        // '微信' | '支付宝'
  orderNo: string;       // 商户单号/商家订单号（退款行的原始订单号）
}

// 已应用的退款记录（持久化，用于重复导入幂等与原账单净额判断）
interface RefundRecord {
  refundDate: number;  // 退款交易时间
  amount: number;      // 退款金额
  key: string;         // 匹配键（来源|交易对方或商品说明）
  billDate: number;    // 被抵扣的原账单日期
  billName: string;    // 被抵扣的原账单名称
  billId: number;      // 被抵扣的原账单 id
  orderNo?: string;    // 退款行的商户单号/商家订单号（旧记录可能没有）
}

// 被退款抵扣的既有账单（主线程同步界面用）
interface ExistingBillUpdate {
  id: number;
  amount: number;          // 抵扣后的净金额
  refundAmount: number;    // 累计退款金额
  originalAmount: number;  // 原始支付金额
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

// 统计页趋势图数据点（天级或月级聚合）
interface StatTrendPoint {
  label: string;  // x 轴标签，如 "8日" / "3月" / "周一"
  amount: number;
  day: number;  // 仅天级数据有意义：几号
}

// 统计页时间范围（含首尾，零点时间戳）
interface StatDateRange {
  start: number;
  end: number;
}

// 统计页周期滑条
const STAT_PERIOD_KEYS: string[] = ['week', 'month', 'year', 'all', 'range'];
const STAT_PERIOD_LABELS: string[] = ['周', '月', '年', '全部', '范围'];

export interface Padding {
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
  dailySuggestion: number;
  remainingDays: number;
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
  recurring?: RecurringBill[];  // 旧版本备份无此字段
}

interface DialogButton {
  text: string;
  color: string;
}
// ========== 选择月份弹窗 ==========
@CustomDialog
struct MonthPickerDialog {
  @StorageProp('brand_main') brandMain: string = '#4E6EF2';
  controller: CustomDialogController = new CustomDialogController({
    builder: () => {}
  });
  @State selectedDate: Date = new Date();
  onConfirm?: (year: number, month: number) => void;

  build() {
    Column() {
      Text('选择月份')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 4, bottom: 16 })
        .alignSelf(ItemAlign.Start)

      DatePicker({
        selected: this.selectedDate,
        start: new Date(2000, 0, 1),
        end: new Date(2099, 11, 31)
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
          .backgroundColor(this.brandMain)
          .fontColor($r('app.color.text_white'))
          .borderRadius(22)
          .height(44)
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
    .width('85%')
    .padding(20)
    .backgroundColor($r('app.color.glass_bg'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .borderRadius({ topLeft: 26, topRight: 23, bottomLeft: 25, bottomRight: 27 })
    .shadow({ radius: 0, color: $r('app.color.ink_shadow'), offsetX: 3, offsetY: 3 }).border({ width: 1, color: $r('app.color.ink_line') })
  }
}

// ========== 主题颜色选择弹窗 ==========
@CustomDialog
struct BrandThemePickerDialog {
  controller: CustomDialogController = new CustomDialogController({
    builder: () => {}
  });
  @StorageProp('brand_theme_index') currentIndex: number = 0;
  @StorageProp('brand_main') brandMain: string = '#4E6EF2';
  onSelect?: (index: number) => void = () => {};

  build() {
    Column() {
      Text('主题颜色')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 4, bottom: 20 })

      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(BRAND_THEMES, (preset: BrandThemePreset, index: number) => {
          Column() {
            Column() {
              if (this.currentIndex === index) {
                Text('✓')
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Color.White)
              }
            }
            .width(44)
            .height(44)
            .borderRadius(22)
            .backgroundColor(preset.light.main)
            .border({
              width: this.currentIndex === index ? 3 : 1,
              color: this.currentIndex === index ? this.brandMain : $r('app.color.border_color')
            })
            .justifyContent(FlexAlign.Center)
            .onClick(() => {
              if (this.onSelect) {
                this.onSelect(index);
              }
            })

            Text(preset.name)
              .fontSize(12)
              .fontColor(this.currentIndex === index ? this.brandMain : $r('app.color.text_secondary'))
              .margin({ top: 8 })
          }
          .width('33.33%')
          .margin({ bottom: 16 })
        }, (preset: BrandThemePreset) => preset.name)
      }
      .width('100%')

      Button('完成')
        .width('100%')
        .height(44)
        .backgroundColor(this.brandMain)
        .fontColor($r('app.color.text_white'))
        .borderRadius(22)
        .fontSize(15)
        .margin({ top: 4 })
        .onClick(() => {
          this.controller.close();
        })
    }
    .width('85%')
    .padding(20)
    .backgroundColor($r('app.color.glass_bg'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .borderRadius(24)
  }
}

// ========== 账本切换弹层（原生半模态 bindSheet，构建器见 Index.LedgerSheetBuilder） ==========

@Entry
@Component
struct Index {
  @StorageProp('brand_main') brandMain: string = '#4E6EF2';
  @StorageProp('brand_light') brandLight: string = '#7B93FF';
  @StorageProp('brand_deep') brandDeep: string = '#3A55E0';
  @StorageProp('brand_tint') brandTint: string = '#EEF1FE';
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
  @State billSummaryMode: 'expense' | 'income' = 'expense';
  @State billViewMode: string = 'list';  // 账单页视图：'list' 列表 | 'calendar' 日历
  @State billSummaryPinned: boolean = true;  // 账单页汇总卡固定开关（true=常驻顶部，false=随账单滚动）
  // ---------- 月份切换内容过渡动画 ----------
  @State homeContentShiftX: number = 0;  // 记账页内容横移量（方向性滑动）
  @State homeContentAlpha: number = 1;   // 记账页内容透明度
  @State billContentShiftX: number = 0;  // 账单页内容横移量（方向性滑动）
  @State billContentAlpha: number = 1;   // 账单页内容透明度
  @State billSummaryOpacity: number = 1; // 账单页汇总卡弹出过渡透明度
  @State billSummaryScale: number = 1;   // 账单页汇总卡弹出过渡缩放
  private homeMonthSwitching: boolean = false;  // 记账页切月动画进行中（防重入）
  private billMonthSwitching: boolean = false;  // 账单页切月动画进行中（防重入）
  @State statYear: number = new Date().getFullYear();
  // 统计页周期：'week' | 'month' | 'year' | 'all' | 'range'
  @State statPeriod: string = 'month';
  @State statAnchorTime: number = new Date().getTime();
  @State statRangeStart: number = 0;  // 自定义范围起始日（零点），0=未设置
  @State statRangeEnd: number = 0;  // 自定义范围结束日（零点），0=未设置
  // 统计页汇总缓存（避免每次渲染全量过滤账单）
  @State statSummaryExpense: number = 0;
  @State statSummaryIncome: number = 0;
  @State statSummaryBalance: number = 0;
  @State statSummaryAvgDaily: number = 0;
  @State statRangeLabelText: string = '';
  @State statLegendStats: ExpenseStat[] = [];
  // 周期切换时下方内容的过渡动画
  @State statContentOpacity: number = 1;
  @State statContentScale: number = 1;
  @State yearCanvasWidth: number = 400;
  @State manualBtnScale: number = 1;
  @State pressedTabIdx: number = -1;  // 底部页签按压索引（Q弹缩放反馈）
  @State tabIconPop: number = 1;  // 选中页签图标弹跳比例
  @State totalAsset: number = 0;
  // 成就系统：累计经验与已解锁勋章数（我的页展示）
  @State userXp: number = 0;
  @State unlockedCount: number = 0;
  // 我的页等级进度条填充动画显示值
  @State userProgressDisplay: number = 0;
  @State isDarkMode: boolean = false;
  @State isReminderOn: boolean = false;
  @State reminderHour: number = 20;
  @State reminderMinute: number = 30;
  @State reminderDays: number[] = [1, 2, 3, 4, 5, 6, 7];
  @StorageLink('currentColorMode')
  @Watch('onColorModeChanged')
  currentColorMode: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @State userTheme: string = 'system';  // 'light' | 'dark' | 'system'
  // 自定义主题颜色：选中的品牌色预设索引（弹窗与各页通过 AppStorage 联动）
  @StorageLink('brand_theme_index') brandThemeIndex: number = 0;
  // 触感反馈开关（点击/切换时的轻微振动，各处通过 hapticTick() 读取 AppStorage）
  @StorageLink('haptic_enabled') hapticEnabled: boolean = true;
  @StorageLink('haptic_intensity') hapticIntensity: number = 100;
  // 资产明细页「资产管理」入口：返回时跳转到财富页资产界面
  @StorageLink('jump_to_wealth_asset') @Watch('onJumpToWealthAsset') jumpToWealthAsset: boolean = false;
  @State billFilterTag: string = '';  // 筛选的标签，空字符串表示全部
  @State pressedBillId: number = -1;
  @State pressedFunc: string = '';
  @State pressedCard: string = '';

  // ---------- 账单列表卡片弹性间距（滚动时间距伸缩，松手回弹） ----------
  @State billGapStretch: number = 0;
  private billListCenterIdx: number = 0;
  // 账本切换半模态弹层显隐
  @State showLedgerSheet: boolean = false;
  // 记一笔 / 搜索账单共用一个半模态弹层，按类型切换内容
  @State showActionSheet: boolean = false;
  @State actionSheetType: 'add' | 'search' = 'add';
  // 编辑账单半模态弹层（与记一笔一致的弹出效果）
  @State showEditSheet: boolean = false;
  @State editSheetBill: BillItem | null = null;
  // 应用内提醒中心（标题栏铃铛入口 + 半模态列表）
  @State showReminderSheet: boolean = false;
  @State reminderItems: ReminderItem[] = [];
  @State unreadCount: number = 0;  // 未读提醒数（铃铛角标只统计未读）
  // 提醒中心动画状态：铃铛摆动 / 角标弹跳 / 未读圆点呼吸 / 加载占位
  @State bellRotate: number = 0;
  @State badgeScale: number = 1;
  @State reminderDotPulse: number = 1;
  @State reminderLoading: boolean = false;
  private reminderBudgetMap: Record<string, number> = {};
  private reminderCredits: ReminderCreditAccount[] = [];
  private reminderGoals: ReminderSavingGoal[] = [];
  private reminderDismissed: Record<string, number> = {};
  private reminderReadMap: Record<string, number> = {};

  private detailDialogController: CustomDialogController | null = null;  private exportDialogController: CustomDialogController | null = null;
  private setBudgetDialogController: CustomDialogController | null = null;
  private colorPalette: string[] = ASSET_PALETTE;
  private canvasCtx: CanvasRenderingContext2D | null = null;
  private trendCanvasCtx: CanvasRenderingContext2D | null = null;
  private yearCanvasCtx: CanvasRenderingContext2D | null = null;
  private trendCanvasWidth: number = 400;
  private pieCanvasWidth: number = 0;
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
  private lastRecurringRefreshFlag: number = 0;
  // 已分配的最大账单 id（水位），保证新 id 始终大于历史上任何已用 id
  private billIdWatermark: number = 0;
  // 周期账单兜底补算的执行日标记（YYYY-MM-DD），避免每次页面显露都全量重扫
  private lastRecurringCheckDay: string = '';
  // 周期账单生成进行中标记，防止多处并发调用重复生成同一批账单
  private recurringGenerating: boolean = false;
  @State recurringBills: RecurringBill[] = [];

  // ---------- 隐私锁状态 ----------
  @State isPrivacyLocked: boolean = false;
  @State privacyLockEnabled: boolean = false;
  @State lockInput: string = '';
  @State lockErrorText: string = '';
  @State lockoutRemainSec: number = 0;
  @State lockUnlockSuccess: boolean = false;
  @State lockShakeX: number = 0;
  @State lockDotsError: boolean = false;
  @State pressedLockKey: string = '';
  @State lockBackupMode: boolean = false;
  @State lockBackupInput: string = '';
  @State lockBackupErrorText: string = '';
  @State lockHintText: string = '';
  privacyLockFailedCount: number = 0;
  lockoutTimer: number = -1;
  fingerprintAuthRunning: boolean = false;
  @State fingerprintAvailable: boolean = false;
  @State pressedFingerprint: boolean = false;
  @State fingerprintUnlockEnabled: boolean = false;
  // 设备是否具备指纹识别硬件（与是否已录入指纹无关；无指纹模块的设备如部分平板不显示指纹解锁开关）
  @State fingerprintSupported: boolean = true;
  fingerprintToggleBusy: boolean = false;
  @State huaweiAccount: HuaweiAccountInfo | undefined = undefined;
  pinSetupDialogController: CustomDialogController = new CustomDialogController({
    builder: PinSetupDialog({
      onDone: (pin: string, backup: string, hint: string) => { this.handlePinSaved(pin, backup, hint); }
    }),
    autoCancel: false,
    alignment: DialogAlignment.Center,
    customStyle: true,
    maskColor: 'rgba(0, 0, 0, 0.4)'
  });
  pinVerifyDialogController: CustomDialogController = new CustomDialogController({
    builder: PinVerifyDialog({
      title: '关闭隐私锁',
      contextProvider: (): common.UIAbilityContext | undefined => {
        return this.getUIContext().getHostContext() as common.UIAbilityContext;
      },
      onVerified: () => { this.doDisablePrivacyLock(); }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    customStyle: true,
    maskColor: 'rgba(0, 0, 0, 0.4)'
  });
  // 修改密码前先验证原密码
  pinVerifyForModifyController: CustomDialogController = new CustomDialogController({
    builder: PinVerifyDialog({
      title: '验证密码',
      contextProvider: (): common.UIAbilityContext | undefined => {
        return this.getUIContext().getHostContext() as common.UIAbilityContext;
      },
      onVerified: () => { this.pinSetupDialogController.open(); }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    customStyle: true,
    maskColor: 'rgba(0, 0, 0, 0.4)'
  });
  // 主题颜色选择弹窗
  brandThemeDialogController: CustomDialogController = new CustomDialogController({
    builder: BrandThemePickerDialog({
      onSelect: (index: number) => { this.switchBrandTheme(index); }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    customStyle: true,
    maskColor: 'rgba(0, 0, 0, 0.4)'
  });

  // 验证通过后执行关闭隐私锁
  async doDisablePrivacyLock(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (context) {
        await clearPin(context);
      }
      this.privacyLockEnabled = false;
      this.fingerprintUnlockEnabled = false;
      this.fingerprintAvailable = false;
      this.lockHintText = '';
      promptAction.showToast({ message: '隐私锁已关闭', duration: 1500 });
    } catch (e) {
      console.error('关闭隐私锁失败: ' + JSON.stringify(e));
      promptAction.showToast({ message: '关闭失败', duration: 1500 });
    }
  }


  // ---------- 隐私锁逻辑 ----------
  async initPrivacyLockState(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (!context) {
        return;
      }
      const enabled = await isPinSet(context);
      this.privacyLockEnabled = enabled;
      // 探测设备指纹硬件能力（无指纹模块的设备不显示设置页指纹解锁开关）
      this.checkFingerprintSupported();
      this.lockInput = '';
      this.lockErrorText = '';
      this.lockUnlockSuccess = false;
      this.lockDotsError = false;
      this.lockBackupMode = false;
      this.lockBackupInput = '';
      this.lockBackupErrorText = '';
      this.lockHintText = await getLockHint(context);
      this.fingerprintUnlockEnabled = enabled && await getFingerprintUnlockEnabled(context);
      if (enabled && this.fingerprintUnlockEnabled) {
        this.checkFingerprintAvailable();
      } else {
        this.fingerprintAvailable = false;
      }
      this.isPrivacyLocked = enabled;
      if (enabled && this.fingerprintUnlockEnabled) {
        // 锁屏出现后自动尝试指纹解锁（仅当用户开启了指纹解锁）
        setTimeout(() => {
          this.tryFingerprintUnlock();
        }, 400);
      }
      this.huaweiAccount = await loadHuaweiAccountInfo(context);
    } catch (e) {
      console.error('初始化隐私锁失败: ' + JSON.stringify(e));
    }
  }

  consumePrivacyRelockSignal() {
    const relockFlag = AppStorage.get<boolean>('privacy_should_relock') || false;
    if (relockFlag) {
      AppStorage.setOrCreate('privacy_should_relock', false);
      if (this.privacyLockEnabled) {
        this.lockInput = '';
        this.lockErrorText = '';
        this.lockUnlockSuccess = false;
        this.lockDotsError = false;
        this.lockBackupMode = false;
        this.lockBackupInput = '';
        this.lockBackupErrorText = '';
        this.isPrivacyLocked = true;
        // 锁屏出现后自动尝试指纹解锁（仅当用户开启了指纹解锁）
        if (this.fingerprintUnlockEnabled) {
          setTimeout(() => {
            this.tryFingerprintUnlock();
          }, 400);
        }
      }
    }
  }

  // 指纹能力可用性检查：设备支持且已录入指纹时返回 true
  checkFingerprintAvailable(): boolean {
    try {
      userAuth.getAvailableStatus(userAuth.UserAuthType.FINGERPRINT, userAuth.AuthTrustLevel.ATL1);
      this.fingerprintAvailable = true;
    } catch (e) {
      this.fingerprintAvailable = false;
    }
    return this.fingerprintAvailable;
  }

  // 设备指纹硬件能力检查：仅 12500005（设备不支持指纹认证，如无指纹模块的平板）视为不支持；
  // 未录入指纹（12500010）等仍视为硬件支持，保留开关引导用户去系统设置录入
  checkFingerprintSupported(): boolean {
    try {
      userAuth.getAvailableStatus(userAuth.UserAuthType.FINGERPRINT, userAuth.AuthTrustLevel.ATL1);
      // 查询通过说明已录入指纹，硬件必然支持
      this.fingerprintSupported = true;
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      this.fingerprintSupported = err.code !== 12500005;
      console.info('指纹硬件能力检查: code=' + err.code + ' supported=' + this.fingerprintSupported);
    }
    return this.fingerprintSupported;
  }

  // 指纹解锁：用户开启后，设备已录入指纹时自动拉起系统指纹认证，成功即解锁；失败/取消则停留锁屏由用户输密码
  tryFingerprintUnlock() {
    if (!this.fingerprintUnlockEnabled) {
      return;
    }
    if (!this.isPrivacyLocked || this.lockBackupMode || this.lockoutRemainSec > 0) {
      return;
    }
    if (this.fingerprintAuthRunning) {
      return;
    }
    if (!this.checkFingerprintAvailable()) {
      return;
    }
    this.fingerprintAuthRunning = true;
    this.startFingerprintAuth('验证指纹以解锁', (ok: boolean) => {
      if (ok) {
        this.performUnlockSuccess();
      }
      // 认证失败或取消：保持锁屏，由用户输入密码解锁
    });
  }

  // 发起系统指纹认证，认证结果通过回调返回
  startFingerprintAuth(title: string, onResult: (ok: boolean) => void) {
    try {
      const challenge = new Uint8Array(16);
      for (let i = 0; i < challenge.length; i++) {
        challenge[i] = Math.floor(Math.random() * 256);
      }
      const authParam: userAuth.AuthParam = {
        challenge: challenge,
        authType: [userAuth.UserAuthType.FINGERPRINT],
        authTrustLevel: userAuth.AuthTrustLevel.ATL1
      };
      const widgetParam: userAuth.WidgetParam = {
        title: title
      };
      const authInstance = userAuth.getUserAuthInstance(authParam, widgetParam);
      const resultCallback: userAuth.IAuthCallback = {
        onResult: (result: userAuth.UserAuthResult) => {
          this.fingerprintAuthRunning = false;
          onResult(result.result === userAuth.UserAuthResultCode.SUCCESS);
        }
      };
      authInstance.on('result', resultCallback);
      authInstance.start();
    } catch (e) {
      this.fingerprintAuthRunning = false;
      console.error('启动指纹认证失败: ' + JSON.stringify(e));
      onResult(false);
    }
  }

  // 设置页指纹解锁开关：开启前需先通过一次指纹验证，验证通过才保存开启
  async onFingerprintToggleChange(isOn: boolean): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (!context) {
      return;
    }
    hapticTick();
    if (!isOn) {
      this.fingerprintUnlockEnabled = false;
      await saveFingerprintUnlockEnabled(context, false);
      promptAction.showToast({ message: '已关闭指纹解锁', duration: 1500 });
      return;
    }
    if (!this.privacyLockEnabled) {
      return;
    }
    if (this.fingerprintToggleBusy) {
      return;
    }
    if (!this.checkFingerprintAvailable()) {
      this.fingerprintUnlockEnabled = false;
      promptAction.showToast({ message: '设备未录入指纹，请先在系统设置中录入', duration: 2000 });
      return;
    }
    this.fingerprintToggleBusy = true;
    this.fingerprintUnlockEnabled = true;
    this.startFingerprintAuth('验证指纹以开启指纹解锁', async (ok: boolean): Promise<void> => {
      this.fingerprintToggleBusy = false;
      if (ok) {
        await saveFingerprintUnlockEnabled(context, true);
        this.fingerprintUnlockEnabled = true;
        promptAction.showToast({ message: '指纹解锁已开启', duration: 1500 });
      } else {
        this.fingerprintUnlockEnabled = false;
        promptAction.showToast({ message: '指纹验证未通过，未开启指纹解锁', duration: 2000 });
      }
    });
  }

  onLockKeyPress(key: string) {
    if (this.lockoutRemainSec > 0) {
      return;
    }
    if (this.lockInput.length >= 6) {
      return;
    }
    this.lockInput += key;
    if (this.lockInput.length === 6) {
      this.tryPrivacyUnlock();
    }
  }

  onLockKeyDelete() {
    if (this.lockoutRemainSec > 0) {
      return;
    }
    if (this.lockInput.length > 0) {
      this.lockInput = this.lockInput.substring(0, this.lockInput.length - 1);
    }
  }

  performUnlockSuccess() {
    // 解锁成功后清除重锁信号：指纹弹窗等临时系统界面可能残留过期的后台切换信号，
    // 不清除会导致解锁后进入子页面再返回时被误要求重新输入密码
    AppStorage.setOrCreate('privacy_should_relock', false);
    this.lockErrorText = '';
    this.privacyLockFailedCount = 0;
    this.lockUnlockSuccess = true;
    setTimeout(() => {
      animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
        this.isPrivacyLocked = false;
      });
      setTimeout(() => {
        this.lockUnlockSuccess = false;
        this.lockInput = '';
        this.lockBackupInput = '';
      }, 400);
    }, 320);
  }

  async tryPrivacyUnlock(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (!context) {
      return;
    }
    const ok = await verifyPin(context, this.lockInput);
    if (ok) {
      this.performUnlockSuccess();
    } else {
      this.privacyLockFailedCount++;
      const left = 5 - this.privacyLockFailedCount;
      this.lockInput = '';
      if (left <= 0) {
        this.startPrivacyLockout(30);
      } else {
        this.lockErrorText = `密码错误，还可尝试 ${left} 次`;
        this.lockDotsError = true;
        this.shakeLock();
        setTimeout(() => {
          this.lockDotsError = false;
        }, 600);
      }
    }
  }

  // 忘记密码：有备用密码则切换到备用密码解锁，否则走重置流程
  async onForgotPinClick(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (context && await isBackupSet(context)) {
      this.lockBackupMode = true;
      this.lockBackupInput = '';
      this.lockBackupErrorText = '';
      return;
    }
    this.clearAllDataAndResetLock();
  }

  async tryBackupUnlock(): Promise<void> {
    if (this.lockoutRemainSec > 0) {
      return;
    }
    const pwd = this.lockBackupInput.trim();
    if (pwd.length === 0) {
      this.lockBackupErrorText = '请输入备用密码';
      return;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (!context) {
      return;
    }
    const ok = await verifyBackupPassword(context, pwd);
    if (ok) {
      this.lockBackupMode = false;
      this.performUnlockSuccess();
      promptAction.showToast({ message: '已通过备用密码解锁', duration: 1500 });
    } else {
      this.privacyLockFailedCount++;
      const left = 5 - this.privacyLockFailedCount;
      this.lockBackupInput = '';
      if (left <= 0) {
        this.lockBackupErrorText = '';
        this.startPrivacyLockout(30);
      } else {
        this.lockBackupErrorText = `备用密码错误，还可尝试 ${left} 次`;
      }
    }
  }

  shakeLock() {
    animateTo({ duration: 70, curve: Curve.EaseInOut }, () => {
      this.lockShakeX = -14;
    });
    setTimeout(() => {
      animateTo({ duration: 70, curve: Curve.EaseInOut }, () => {
        this.lockShakeX = 14;
      });
    }, 70);
    setTimeout(() => {
      animateTo({ duration: 70, curve: Curve.EaseInOut }, () => {
        this.lockShakeX = -8;
      });
    }, 140);
    setTimeout(() => {
      animateTo({ duration: 90, curve: Curve.EaseInOut }, () => {
        this.lockShakeX = 0;
      });
    }, 210);
  }

  startPrivacyLockout(seconds: number) {
    this.lockoutRemainSec = seconds;
    this.lockInput = '';
    this.lockErrorText = '';
    this.privacyLockFailedCount = 0;
    if (this.lockoutTimer >= 0) {
      clearInterval(this.lockoutTimer);
    }
    this.lockoutTimer = setInterval(() => {
      this.lockoutRemainSec--;
      if (this.lockoutRemainSec <= 0) {
        this.lockoutRemainSec = 0;
        if (this.lockoutTimer >= 0) {
          clearInterval(this.lockoutTimer);
          this.lockoutTimer = -1;
        }
      }
    }, 1000);
  }

  // 密码与备用密码均忘记：清除应用内全部数据并关闭隐私锁
  async clearAllDataAndResetLock(): Promise<void> {
    const result = await promptAction.showDialog({
      title: '清除数据',
      message: '密码与备用密码均无法找回。为关闭隐私锁，将清除应用内所有数据（账单、账本、预算、资产、标签等），清除后无法恢复。确定清除吗？',
      buttons: [
        { text: '取消', color: $r('app.color.text_secondary') },
        { text: '清除数据', color: $r('app.color.expense_red') }
      ]
    });
    if (result.index !== 1) {
      return;
    }
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (context) {
        const prefs = await dataPreferences.getPreferences(context, 'bill_data');
        await prefs.clear();
        await prefs.flush();
        clearAllBillPhotos(context);
      }
      // 清空持久化存储与内存中的账单/账本等数据
      this.bills = [];
      this.ledgers = [];
      this.ledgerBills = [];
      this.recurringBills = [];
      this.currentLedgerId = DEFAULT_LEDGER_ID;
      this.budget = 0;
      this.hasBudget = false;
      this.userXp = 0;
      // 关闭隐私锁并复位锁屏状态
      this.privacyLockEnabled = false;
      this.isPrivacyLocked = false;
      this.fingerprintUnlockEnabled = false;
      this.fingerprintAvailable = false;
      this.huaweiAccount = undefined;
      this.lockBackupMode = false;
      this.lockBackupInput = '';
      this.lockBackupErrorText = '';
      this.lockHintText = '';
      this.lockInput = '';
      this.lockErrorText = '';
      this.privacyLockFailedCount = 0;
      // 重建默认账本并刷新各页汇总
      await this.initLedgerData();
      await this.loadLedgerState();
      await this.loadUserProgress();
      await this.loadTotalAsset();
      this.updateLedgerBills();
      this.updateStatSummary();
      this.refreshWidgetCards();
      promptAction.showToast({ message: '数据已清除，隐私锁已关闭', duration: 1500 });
    } catch (e) {
      console.error('清除数据失败: ' + JSON.stringify(e));
      promptAction.showToast({ message: '清除失败', duration: 1500 });
    }
  }

  async handlePinSaved(pin: string, backup: string, hint: string): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (!context) {
        return;
      }
      await savePin(context, pin);
      await saveBackupPassword(context, backup);
      await saveLockHint(context, hint);
      this.privacyLockEnabled = true;
      this.lockHintText = hint;
      promptAction.showToast({ message: '隐私锁已开启', duration: 1500 });
    } catch (e) {
      console.error('保存隐私锁密码失败: ' + JSON.stringify(e));
      promptAction.showToast({ message: '设置失败', duration: 1500 });
    }
  }

  async onPrivacyLockRowClick(): Promise<void> {
    if (!this.privacyLockEnabled) {
      this.pinSetupDialogController.open();
      return;
    }
    const result = await promptAction.showDialog({
      title: '隐私锁',
      message: '隐私锁已开启，可选择修改密码或关闭。',
      buttons: [
        { text: '修改密码', color: this.brandMain },
        { text: '关闭', color: $r('app.color.expense_red') },
        { text: '取消', color: $r('app.color.text_secondary') }
      ]
    });
    if (result.index === 0) {
      // 修改密码前需先验证原密码
      this.pinVerifyForModifyController.open();
    } else if (result.index === 1) {
      // 关闭前需先验证密码
      this.pinVerifyDialogController.open();
    }
  }

  // ---------- 华为账号登录（仅本地标识 + 头像昵称展示，无后端） ----------
  // 用户卡片头像文字：已登录取昵称首字，未登录显示默认"乌"
  getAvatarChar(): string {
    if (this.huaweiAccount && this.huaweiAccount.nickname.length > 0) {
      return this.huaweiAccount.nickname.substring(0, 1);
    }
    return '乌';
  }

  async onHuaweiAccountRowClick(): Promise<void> {
    if (!this.huaweiAccount) {
      await this.startHuaweiLogin();
      return;
    }
    const displayName = this.huaweiAccount.nickname.length > 0 ? this.huaweiAccount.nickname : '已登录';
    const result = await promptAction.showDialog({
      title: '华为账号',
      message: `当前登录：${displayName}`,
      buttons: [
        { text: '退出登录', color: $r('app.color.expense_red') },
        { text: '取消', color: $r('app.color.text_secondary') }
      ]
    });
    if (result.index === 0) {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (context) {
        await clearHuaweiAccountInfo(context);
      }
      this.huaweiAccount = undefined;
      promptAction.showToast({ message: '已退出华为账号', duration: 1500 });
    }
  }

  async startHuaweiLogin(): Promise<void> {
    const authRequest = new authentication.HuaweiIDProvider().createAuthorizationWithHuaweiIDRequest();
    // openid 用于获取用户标识，profile 用于获取头像昵称（该场景无需申请账号权限）
    authRequest.scopes = ['openid', 'profile'];
    authRequest.forceAuthorization = true;
    // state 一致性比对，防跨站攻击
    authRequest.state = util.generateRandomUUID();
    try {
      const controller = new authentication.AuthenticationController(this.getUIContext().getHostContext());
      const data = await controller.executeRequest(authRequest);
      const resp = data as authentication.AuthorizationWithHuaweiIDResponse;
      const respState = resp.state ?? '';
      if (respState !== authRequest.state) {
        promptAction.showToast({ message: '登录异常，请重试', duration: 1500 });
        return;
      }
      const credential = resp.data;
      const info = new HuaweiAccountInfo();
      info.openId = credential?.openID ?? '';
      info.unionId = credential?.unionID ?? '';
      info.nickname = credential?.nickName ?? '';
      info.avatarUri = credential?.avatarUri ?? '';
      if (info.openId.length === 0) {
        promptAction.showToast({ message: '登录失败，未获取到账号标识', duration: 1500 });
        return;
      }
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (context) {
        await saveHuaweiAccountInfo(context, info);
      }
      this.huaweiAccount = info;
      promptAction.showToast({ message: '华为账号登录成功', duration: 1500 });
    } catch (e) {
      const err = e as BusinessError;
      console.error('华为账号登录失败: ' + JSON.stringify(err));
      if (err.code === 1001502001) {
        promptAction.showToast({ message: '未登录华为账号，请先在系统设置中登录华为账号后重试', duration: 2000 });
      } else if (err.code === 1001502005) {
        promptAction.showToast({ message: '网络异常，请检查网络后重试', duration: 2000 });
      } else if (err.code === 1001502012) {
        // 用户取消授权，无需提示
      } else {
        promptAction.showToast({ message: '登录失败，请稍后重试', duration: 1500 });
      }
    }
  }

  aboutToDisappear() {
    if (this.lockoutTimer >= 0) {
      clearInterval(this.lockoutTimer);
      this.lockoutTimer = -1;
    }
  }

  // 桌面卡片数据有变时刷新所有已添加的卡片
  refreshWidgetCards() {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (context) {
      updateAllWidgetCards(context);
    }
  }

  // ---------- 账单主键 ----------
  // 账单 id 必须全局唯一：删除、批量删除、退款抵扣都靠 id 精确定位某一笔。
  // 原先直接用 Date.now()，同一毫秒内连续记账会重号，删一笔会连带删掉同号的另一笔；
  // 而回收站恢复是原样把旧账单 push 回去，旧号一旦被新账单占用又会冲突。
  // 这里改成「严格递增水位」：新号永远大于历史上任何一个已用过的 id。
  refreshBillIdWatermark(): void {
    let maxId: number = 0;
    for (const bill of this.bills) {
      if (bill.id > maxId) {
        maxId = bill.id;
      }
    }
    if (maxId > this.billIdWatermark) {
      this.billIdWatermark = maxId;
    }
  }

  nextBillId(): number {
    const next: number = Math.max(this.billIdWatermark, Date.now()) + 1;
    this.billIdWatermark = next;
    return next;
  }

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
      this.refreshBillIdWatermark();
      this.updateLedgerBills();
      this.updateStatSummary();
      this.refreshWidgetCards();
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
      this.updateStatSummary();
      this.refreshWidgetCards();
      console.info('✅ 账单已保存到 Preferences，共 ' + this.bills.length + ' 条');
    } catch (e) {
      console.error('❌ 保存到 Preferences 失败: ' + JSON.stringify(e));
    }
  }

  // ---------- 周期账单：加载规则 ----------
  async loadRecurringBills(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (!context) {
        return;
      }
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');
      const data = await prefs.get('recurring_bills', '[]') as string;
      this.recurringBills = JSON.parse(data) as RecurringBill[];
    } catch (e) {
      console.error('加载周期账单规则失败: ' + JSON.stringify(e));
    }
  }

  // 重新加载周期账单规则并补生成：必须串行 awaited，
  // 否则刚改完规则立刻返回首页时，生成的还是旧规则下的账单
  private async reloadRecurringBills(): Promise<void> {
    await this.loadRecurringBills();
    await this.generateRecurringBills();
  }

  // ---------- 周期账单：幂等生成引擎 ----------
  async generateRecurringBills(): Promise<void> {
    // 防重入：aboutToAppear 与 onPageShow 可能在短时间内各触发一次，
    // 两次调用会各自基于同一份账单快照判断"还未生成"，从而插入重复账单
    if (this.recurringGenerating) {
      return;
    }
    this.recurringGenerating = true;
    try {
      if (this.recurringBills.length === 0) {
        return;
      }
      const today = new Date();
      // 记录本次扫描所属日期，供 onPageShow 判断是否需要再次兜底补算
      this.lastRecurringCheckDay = `${today.getFullYear()}-${today.getMonth() + 1}-${today.getDate()}`;
      const todayStart = new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime();

      // 已生成的周期账单键集合（幂等去重）
      const existingKeys = new Set<string>();
      this.bills.forEach((item: BillItem) => {
        if (item.recurringKey !== undefined && item.recurringKey.length > 0) {
          existingKeys.add(item.recurringKey);
        }
      });

      const newBills: BillItem[] = [];

      this.recurringBills.forEach((rule: RecurringBill) => {
        if (!rule.enabled) {
          return;
        }
        // 回填起点：max(生效日, 今天-366天)
        const earliest = todayStart - 366 * 24 * 60 * 60 * 1000;
        let cursor = rule.startDate < earliest ? earliest : rule.startDate;
        const start = new Date(cursor);
        let d = new Date(start.getFullYear(), start.getMonth(), start.getDate());
        // 起点对齐到本地零点后，若提前于规则生效日的零点则推进
        const ruleStart = new Date(rule.startDate);
        const ruleStartDay = new Date(ruleStart.getFullYear(), ruleStart.getMonth(), ruleStart.getDate()).getTime();

        while (d.getTime() <= todayStart) {
          const t = d.getTime();
          if (t >= ruleStartDay && (rule.endDate === 0 || t <= rule.endDate)) {
            let matched = false;
            if (rule.freqType === 'weekly') {
              // JS getDay(): 0=周日..6=周六 → 转为 1=周一..7=周日
              const dow = d.getDay() === 0 ? 7 : d.getDay();
              matched = dow === rule.dayOfWeek;
            } else if (rule.freqType === 'monthly') {
              const daysInMonth = new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate();
              const target = rule.dayOfMonth > daysInMonth ? daysInMonth : rule.dayOfMonth;
              matched = d.getDate() === target;
            } else {
              const daysInMonth = new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate();
              const target = rule.dayOfMonth > daysInMonth ? daysInMonth : rule.dayOfMonth;
              matched = (d.getMonth() + 1) === rule.monthOfYear && d.getDate() === target;
            }
            if (matched) {
              const mm = String(d.getMonth() + 1).padStart(2, '0');
              const dd = String(d.getDate()).padStart(2, '0');
              const key = `r${rule.id}_${d.getFullYear()}-${mm}-${dd}`;
              if (!existingKeys.has(key)) {
                existingKeys.add(key);
                newBills.push({
                  id: this.nextBillId(),
                  name: rule.name,
                  amount: rule.amount,
                  type: rule.type,
                  date: t,
                  category: rule.category,
                  source: rule.source,
                  ledgerId: rule.ledgerId,
                  recurringKey: key
                });
              }
            }
          }
          d.setDate(d.getDate() + 1);
        }
      });

      if (newBills.length > 0) {
        this.bills = [...this.bills, ...newBills];
        await this.saveBillsToPreferences();
        AppStorage.setOrCreate('bills', this.bills);
        this.updateLedgerBills();
        this.refreshKey++;
        console.info('✅ 周期账单生成了 ' + newBills.length + ' 条');
      }
      // 周期生成的账单与手动记账同等对待：同步增减资金账户余额。
      // 这些账单是本次新插入的记录、此前从未计入过余额，不同步的话
      // 资产页会和账单流水对不上（典型场景：设了按月自动扣房租）
      await this.applyAssetsBatch(newBills, 'add');
    } catch (e) {
      console.error('生成周期账单失败: ' + JSON.stringify(e));
    } finally {
      this.recurringGenerating = false;
    }
  }

  // ---------- 多账本：数据初始化 ----------
  async initLedgerData(): Promise<void> {
    await this.loadBillsFromPreferences();
    await this.loadRecurringBills();
    await this.generateRecurringBills();
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
      this.refreshWidgetCards();
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
    this.computeReminderItems();
  }

  // ---------- 应用内提醒中心 ----------
  // 已删除/已读记录的保留期：30天内同一条不重复出现（下月/下一个还款日为新提醒，会正常出现）
  static readonly REMINDER_DISMISS_MS: number = 30 * 24 * 60 * 60 * 1000;

  // 加载提醒所需的预算/信用账户/存钱目标数据并重算提醒
  async loadReminderData(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (!context) {
        return;
      }
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');
      const budgetRaw = await prefs.get('budget', '') as string;
      this.reminderBudgetMap = budgetRaw.length > 0 ? JSON.parse(budgetRaw) as Record<string, number> : {};
      const creditRaw = await prefs.get('credit_accounts', '[]') as string;
      this.reminderCredits = JSON.parse(creditRaw) as ReminderCreditAccount[];
      const goalRaw = await prefs.get('saving_goals', '[]') as string;
      const parsedGoals = JSON.parse(goalRaw) as ReminderSavingGoal[];
      // 旧数据无 deadline / 挑战字段，解析时补默认值
      this.reminderGoals = parsedGoals.map((g: ReminderSavingGoal): ReminderSavingGoal => {
        return {
          id: g.id,
          name: g.name,
          target: g.target,
          saved: g.saved,
          deadline: g.deadline ? g.deadline : 0,
          challengeType: g.challengeType ? g.challengeType : undefined,
          challengeStart: g.challengeStart ? g.challengeStart : undefined,
          remindChallenge: g.remindChallenge ? g.remindChallenge : undefined
        };
      });
      // 加载已删除/已读记录并清理过期条目
      const nowMs = Date.now();
      const dismissedRaw = await prefs.get('dismissed_reminders', '{}') as string;
      let dismissed: Record<string, number> = {};
      if (dismissedRaw.length > 0) {
        dismissed = JSON.parse(dismissedRaw) as Record<string, number>;
      }
      const readRaw = await prefs.get('read_reminders', '{}') as string;
      let readMap: Record<string, number> = {};
      if (readRaw.length > 0) {
        readMap = JSON.parse(readRaw) as Record<string, number>;
      }
      const cleanedDismissed: Record<string, number> = {};
      let dismissedChanged = false;
      const dismissedKeys = Object.keys(dismissed);
      for (const k of dismissedKeys) {
        const exp = dismissed[k];
        if (exp !== undefined && exp > nowMs) {
          cleanedDismissed[k] = exp;
        } else {
          dismissedChanged = true;
        }
      }
      const cleanedRead: Record<string, number> = {};
      let readChanged = false;
      const readKeys = Object.keys(readMap);
      for (const k of readKeys) {
        const exp = readMap[k];
        if (exp !== undefined && exp > nowMs) {
          cleanedRead[k] = exp;
        } else {
          readChanged = true;
        }
      }
      this.reminderDismissed = cleanedDismissed;
      this.reminderReadMap = cleanedRead;
      if (dismissedChanged || readChanged) {
        await prefs.put('dismissed_reminders', JSON.stringify(cleanedDismissed));
        await prefs.put('read_reminders', JSON.stringify(cleanedRead));
        await prefs.flush();
      }
    } catch (e) {
      console.error('加载提醒数据失败: ' + JSON.stringify(e));
    }
    this.computeReminderItems();
  }

  // 从当前账单汇总本月各账本支出、近3个月结余，生成提醒列表
  computeReminderItems(): void {
    const now = new Date();
    const monthExpense: Record<string, number> = {};
    let income3 = 0;
    let expense3 = 0;
    for (let i = 0; i < 3; i++) {
      const m = new Date(now.getFullYear(), now.getMonth() - i, 1);
      for (const b of this.bills) {
        const d = new Date(b.date);
        if (d.getFullYear() !== m.getFullYear() || d.getMonth() !== m.getMonth()) {
          continue;
        }
        if (b.type === '支出') {
          const lid = (b.ledgerId ?? DEFAULT_LEDGER_ID).toString();
          if (i === 0) {
            const cur = monthExpense[lid];
            monthExpense[lid] = (cur !== undefined ? cur : 0) + b.amount;
          }
          expense3 += b.amount;
        } else if (b.type === '收入') {
          income3 += b.amount;
        }
      }
    }
    const input: ReminderInput = {
      monthExpenseByLedger: monthExpense,
      ledgerNames: this.getReminderLedgerNames(),
      budgetMap: this.reminderBudgetMap,
      defaultLedgerId: DEFAULT_LEDGER_ID,
      creditAccounts: this.reminderCredits,
      savingGoals: this.reminderGoals,
      recentMonthlyBalance: (income3 - expense3) / 3,
      dismissedKeys: this.reminderDismissed,
      readKeys: this.reminderReadMap,
      now: now
    };
    this.reminderItems = buildReminders(input);
    this.updateUnreadReminderCount();
  }

  // 未读数：已读的提醒不再计入铃铛角标；新增未读时铃铛摆动 + 角标弹跳
  updateUnreadReminderCount(): void {
    let n = 0;
    for (const r of this.reminderItems) {
      if (r.read !== true) {
        n++;
      }
    }
    if (n > this.unreadCount) {
      this.playBellSwing();
      this.bounceBadge();
    }
    this.unreadCount = n;
  }

  // 铃铛摆动：左右衰减摇摆后回正（旋转轴在顶部，模拟真实铃铛）
  playBellSwing(): void {
    animateTo({ duration: 130, curve: Curve.EaseInOut }, () => { this.bellRotate = -16; });
    setTimeout(() => {
      animateTo({ duration: 130, curve: Curve.EaseInOut }, () => { this.bellRotate = 15; });
    }, 140);
    setTimeout(() => {
      animateTo({ duration: 130, curve: Curve.EaseInOut }, () => { this.bellRotate = -8; });
    }, 280);
    setTimeout(() => {
      animateTo({ duration: 260, curve: AnimationConfig.SPRING }, () => { this.bellRotate = 0; });
    }, 420);
  }

  // 角标弹跳：放大后弹簧回缩
  bounceBadge(): void {
    animateTo({ duration: 180, curve: AnimationConfig.SPRING }, () => { this.badgeScale = 1.45; });
    setTimeout(() => {
      animateTo({ duration: 300, curve: AnimationConfig.SPRING }, () => { this.badgeScale = 1; });
    }, 160);
  }

  getReminderLedgerNames(): Record<string, string> {
    const names: Record<string, string> = {};
    if (this.ledgers.length === 0) {
      names[DEFAULT_LEDGER_ID.toString()] = '默认账本';
      return names;
    }
    for (const l of this.ledgers) {
      names[l.id.toString()] = l.name;
    }
    return names;
  }

  // 打开提醒中心前先刷新数据（信用账户/存钱目标可能在财富页刚被修改）
  // 先清空并显示加载占位，待数据就绪后条目重新插入，触发逐条交错入场动画
  async openReminderCenter(): Promise<void> {
    this.reminderItems = [];
    this.reminderLoading = true;
    this.showReminderSheet = true;
    await this.loadReminderData();
    this.reminderLoading = false;
  }

  // 删除单条提醒：30天内同一条不再出现
  async dismissReminder(item: ReminderItem): Promise<void> {
    this.reminderItems = this.reminderItems.filter((r: ReminderItem): boolean => r.key !== item.key);
    this.reminderDismissed[item.key] = Date.now() + Index.REMINDER_DISMISS_MS;
    this.updateUnreadReminderCount();
    hapticTick();
    await this.persistReminderDismissed();
  }

  // 清空全部提醒
  async clearAllReminders(): Promise<void> {
    const nowMs = Date.now();
    for (const item of this.reminderItems) {
      this.reminderDismissed[item.key] = nowMs + Index.REMINDER_DISMISS_MS;
    }
    this.reminderItems = [];
    this.updateUnreadReminderCount();
    hapticTick();
    await this.persistReminderDismissed();
  }

  // 左滑/点击操作区标记为已读（已读后铃铛角标不再计入该条）
  markReminderRead(item: ReminderItem): void {
    if (item.read === true) {
      return;
    }
    this.reminderReadMap[item.key] = Date.now() + Index.REMINDER_DISMISS_MS;
    this.reminderItems = this.reminderItems.map((r: ReminderItem): ReminderItem => {
      if (r.key === item.key) {
        return { key: r.key, kind: r.kind, title: r.title, detail: r.detail, level: r.level, read: true };
      }
      return r;
    });
    this.updateUnreadReminderCount();
    hapticTick();
    this.persistReminderRead();
  }

  async persistReminderRead(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (!context) {
        return;
      }
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');
      await prefs.put('read_reminders', JSON.stringify(this.reminderReadMap));
      await prefs.flush();
    } catch (e) {
      console.error('保存已读提醒失败: ' + JSON.stringify(e));
    }
  }

  // 点击提醒条目：标记已读并跳转对应页面
  // 还款日 → 财富页资产模式；存钱目标 → 财富页存钱模式；预算 → 切到对应账本并打开账单页
  handleReminderTap(item: ReminderItem): void {
    this.markReminderRead(item);
    this.showReminderSheet = false;
    hapticTick();
    setTimeout(() => {
      if (item.kind === 'credit') {
        AppStorage.setOrCreate('wealth_mode', 'asset');
        animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
          this.currentTabIndex = 3;
        });
      } else if (item.kind === 'goal') {
        AppStorage.setOrCreate('wealth_mode', 'saving');
        animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
          this.currentTabIndex = 3;
        });
      } else {
        if (item.targetLedgerId !== undefined && item.targetLedgerId > 0) {
          this.switchLedger(item.targetLedgerId);
        }
        animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
          this.currentTabIndex = 2;
        });
      }
    }, 250);
  }

  async persistReminderDismissed(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (!context) {
        return;
      }
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');
      await prefs.put('dismissed_reminders', JSON.stringify(this.reminderDismissed));
      await prefs.flush();
    } catch (e) {
      console.error('保存已删除提醒失败: ' + JSON.stringify(e));
    }
  }

  @Builder
  ReminderSheetBuilder() {
    Column() {
      Text('提醒中心')
        .fontSize(19)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 40, bottom: 6 })

      Text('基于还款日、预算执行与存钱目标自动生成，点击可跳转')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .margin({ bottom: 16 })

      if (this.reminderLoading) {
        // 加载占位：数据就绪后淡出，让位于逐条入场的提醒列表
        Column() {
          LoadingProgress()
            .width(30)
            .height(30)
            .color(this.brandMain)
        }
        .width('100%')
        .padding({ top: 44, bottom: 44 })
        .justifyContent(FlexAlign.Center)
        .transition(TransitionEffect.OPACITY.animation({ duration: 180 }))
      } else if (this.reminderItems.length === 0) {
        Column() {
          SymbolGlyph($r('sys.symbol.bell'))
            .fontSize(40)
            .fontColor([$r('app.color.text_secondary')])
            .margin({ bottom: 10 })
          Text('暂无提醒，收支都在掌控中')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .padding({ top: 44, bottom: 44 })
        .justifyContent(FlexAlign.Center)
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.scale({ x: 0.9, y: 0.9 }))
          .animation({ curve: AnimationConfig.SPRING_SOFT }))
      } else {
        List({ space: 0 }) {
          ForEach(this.reminderItems, (item: ReminderItem, index: number) => {
            ListItem() {
              this.ReminderRow(item)
            }
            .transition(TransitionEffect.asymmetric(
              // 入场：上滑淡入，按序号交错
              TransitionEffect.OPACITY
                .combine(TransitionEffect.translate({ y: 18 }))
                .animation({ delay: index * 55, curve: AnimationConfig.SPRING_SOFT }),
              // 退场（删除/清空）：右滑淡出
              TransitionEffect.OPACITY
                .combine(TransitionEffect.translate({ x: 90 }))
                .animation({ duration: 220, curve: Curve.EaseIn })
            ))
            .swipeAction({
              // 左滑仅展开「已读」按钮，不自动标记；点击按钮后才确认已读
              end: {
                builder: () => { this.ReminderReadSwipeAction(item); }
              }
            })
          }, (item: ReminderItem) => item.key + (item.read === true ? '_r' : '_u'))
        }
        .scrollBar(BarState.Off)
        .width('100%')

        // 操作按钮放底部，避开半模态弹窗右上角的关闭按钮；颜色跟随自定义品牌主题
        Row() {
          Text('点击跳转 · 左滑后点击「已读」确认')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
          Blank()
          Text('清空全部')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.brandMain)
            .padding({ top: 6, bottom: 6, left: 10, right: 10 })
            .onClick(() => { this.clearAllReminders(); })
        }
        .width('100%')
        .margin({ top: 4 })
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, bottom: 30 })
  }

  // 左滑露出的“已读”操作区：仅展示不自动触发，点击按钮确认已读
  @Builder
  ReminderReadSwipeAction(item: ReminderItem) {
    if (item.read !== true) {
      Row() {
        Text('已读')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_white'))
      }
      .width(72)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.brandMain)
      .borderRadius(14)
      .onClick(() => { this.markReminderRead(item); })
    }
  }

  @Builder
  ReminderRow(item: ReminderItem) {
    Row() {
      // 未读：红色圆点呼吸放大突出待处理；已读：灰色圆点静止
      Circle({ width: 8, height: 8 })
        .fill(item.read === true ? $r('app.color.border_color') : $r('app.color.expense_red'))
        .scale({
          x: item.read === true ? 1 : this.reminderDotPulse,
          y: item.read === true ? 1 : this.reminderDotPulse
        })
        .margin({ right: 10 })
      Column() {
        Text(item.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text(item.detail)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 3 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text(item.kind === 'credit' ? '还款日' : (item.kind === 'budget' ? '预算' : '存钱'))
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .backgroundColor($r('app.color.category_btn_bg'))
        .borderRadius(10)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(12)
        .fontColor([$r('app.color.border_color')])
        .margin({ left: 4 })

      SymbolGlyph($r('sys.symbol.xmark'))
        .fontSize(13)
        .fontColor([$r('app.color.text_secondary')])
        .padding(8)
        .margin({ right: -8 })
        .onClick(() => { this.dismissReminder(item); })
    }
    .width('100%')
    .padding(14)
    .borderRadius(14)
    .backgroundColor($r('app.color.card_bg'))
    .margin({ bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => { this.handleReminderTap(item); })
  }

  switchLedger(id: number): void {
    if (id === this.currentLedgerId) {
      return;
    }
    animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
      this.currentLedgerId = id;
    });
    hapticTick();
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

  // 加载成就进度（经验值 + 已解锁勋章数）
  async loadUserProgress() {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (!context) {
        return;
      }
      this.userXp = await loadXp(context);
      const unlocked = await loadUnlocked(context);
      this.unlockedCount = unlocked.length;
      // 等级进度条平滑填充到最新进度
      animateTo({ duration: 800, curve: Curve.EaseOut }, () => {
        this.userProgressDisplay = this.getUserLevelProgress();
      });
    } catch (e) {
      console.error('加载成就进度失败', e);
    }
  }

  // ---------- 等级展示辅助 ----------
  getUserLevel(): number {
    return getLevelInfo(this.userXp).level;
  }

  isUserMaxLevel(): boolean {
    return getLevelInfo(this.userXp).maxed;
  }

  getUserLevelProgress(): number {
    const info = getLevelInfo(this.userXp);
    if (info.maxed) {
      return 100;
    }
    const span = info.nextLevelXp - info.curLevelXp;
    if (span <= 0) {
      return 0;
    }
    return Math.min(100, Math.max(0, (info.totalXp - info.curLevelXp) / span * 100));
  }

  // 记账 +5 经验（连续记账有连击加成），并检查成就解锁（含解锁提示）
  async grantBillXpAndCheck(bill?: BillItem) {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (!context) {
        return;
      }
      // 连击加成：按连续记账天数放大本笔经验
      const criteria = await buildCriteriaFromPrefs(context);
      const multiplier = getStreakMultiplier(criteria.streakDays);
      const gained = Math.round(5 * multiplier);
      await addXp(context, gained);
      // 记一笔账 = 完成今日任务
      await markDailyTask(context, 'bill');
      // 幸运存钱罐：每笔记账随机掉金币入罐
      await dropCoinsIntoPiggy(context);
      // 小鸡旅行：旅途中记账提前归来
      await boostTravel(context);
      // 每日鸡运签：推进今日签上任务
      await trackFortuneBill(context);
      // 新玩法：摇钱树浇水 / 签到打卡 / 守护战 / 无消费日结算
      if (bill) {
        const playground = await trackPlaygroundOnBill(context,
          bill.ledgerId ?? DEFAULT_LEDGER_ID, bill.amount, bill.type);
        if (playground.guardian === 'defeated') {
          promptAction.showToast({ message: '吞金兽被击败！去小鸡页-玩法乐园领奖吧', duration: 2500 });
        } else if (playground.treeWithered) {
          promptAction.showToast({ message: '摇钱树因断签枯萎了…重新种一棵吧', duration: 2500 });
        }
      }
      const fresh = await checkAndUnlock(context, criteria);
      if (fresh.length > 0) {
        const names: string[] = fresh.map((d: AchievementDef): string => d.name);
        promptAction.showToast({ message: `小鸡捡到新宝贝：${names.join('、')}！`, duration: 2500 });
      } else if (multiplier > 1) {
        promptAction.showToast({
          message: `连续记账 ${criteria.streakDays} 天，成长值 +${gained}`,
          duration: 1800
        });
      }
      this.loadUserProgress();
    } catch (e) {
      console.error('记账经验/成就检查失败', e);
    }
  }

  // ---------- 新手引导 ----------
  // 引导介绍页（GuideIntroPage）负责新手引导；设置页提供重新体验入口

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
    // 深浅切换后品牌色取值切换（浅色/深色预设），同步全局组件
    this.applyBrandThemeColors();
    // 深浅切换后重绘统计图表（Canvas 颜色按模式选取）
    if (this.currentTabIndex === 1) {
      setTimeout(() => {
        this.drawPieChart();
        this.drawTrendChart();
        this.drawYearlyTrendChart();
      }, 50);
    }
  }

  // ---------- 自定义主题颜色 ----------
  applyBrandThemeColors(): void {
    AppStorage.setOrCreate(BRAND_THEME_INDEX_KEY, this.brandThemeIndex);
    applyBrandTheme(this.brandThemeIndex,
      this.currentColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
  }

  switchBrandTheme(index: number): void {
    this.brandThemeIndex = index;
    this.applyBrandThemeColors();
    this.saveBrandThemeIndex();
    hapticTick();
  }

  // 资产明细页点击「资产管理」后返回主页，切换到财富 tab（wealth_mode 已由来源页设为 'asset'）
  onJumpToWealthAsset(): void {
    if (!this.jumpToWealthAsset) {
      return;
    }
    this.jumpToWealthAsset = false;
    animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
      this.currentTabIndex = 3;
    });
  }

  // 触感反馈开关/强度持久化
  async loadHapticEnabled(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');
      this.hapticEnabled = (await prefs.get('haptic_enabled', true)) as boolean;
      const intensity = (await prefs.get('haptic_intensity', 100)) as number;
      this.hapticIntensity = isNaN(intensity) ? 100 : Math.min(100, Math.max(1, intensity));
    } catch (e) {
      console.error('加载触感反馈设置失败', e);
    }
  }

  async saveHapticIntensity(value: number): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');
      await prefs.put('haptic_intensity', value);
      await prefs.flush();
    } catch (e) {
      console.error('保存触感强度设置失败', e);
    }
  }

  async saveHapticEnabled(value: boolean): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');
      await prefs.put('haptic_enabled', value);
      await prefs.flush();
    } catch (e) {
      console.error('保存触感反馈设置失败', e);
    }
  }

  async loadBrandThemeIndex(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');
      const idx = await prefs.get('brand_theme_index', 0) as number;
      this.brandThemeIndex = Math.max(0, Math.min(BRAND_THEMES.length - 1, idx));
    } catch (e) {
      console.error('加载主题颜色失败', e);
    }
    this.applyBrandThemeColors();
  }

  async saveBrandThemeIndex(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');
      await prefs.put('brand_theme_index', this.brandThemeIndex);
      await prefs.flush();
    } catch (e) {
      console.error('保存主题颜色失败', e);
    }
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
        // 模式确定后按新模式重设品牌色（onColorModeChanged 也会兜底触发）
        applyBrandTheme(this.brandThemeIndex,
          targetMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      }, 200);
    } else {
      this.updateSystemBarColor(mode);
      applyBrandTheme(this.brandThemeIndex,
        mode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    }
  }


  async updateSystemBarColor(mode: ConfigurationConstant.ColorMode) {
    const isDark = mode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const win = await window.getLastWindow(context);
      // 窗口背景色与 bg_main 同步，避免页面未铺满的避让区露出异色底
      win.setWindowBackgroundColor(isDark ? '#101116' : '#F6F7FB');
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

  // 批量更新资金账户余额：整批只做一次读、一次写。
  // 逐笔调用 updateAsset 会是 O(n) 次 Preferences 读写，
  // 周期账单回填一次可能几十笔、批量删除同样。
  async applyAssetsBatch(bills: BillItem[], operation: 'add' | 'remove'): Promise<void> {
    if (bills.length === 0) {
      return;
    }
    const list = await this.loadAssetList();
    for (const bill of bills) {
      let item = list.find(i => i.name === bill.source);
      if (!item) {
        item = { name: bill.source, amount: 0 };
        list.push(item);
      }
      const delta: number = bill.type === '收入' ? bill.amount : -bill.amount;
      item.amount += (operation === 'add' ? delta : -delta);
      if (item.amount < 0) {
        item.amount = 0;
      }
    }
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
      this.refreshWidgetCards();
      console.info('✅ 预算已保存');
    } catch (e) {
      console.error('保存预算失败: ' + JSON.stringify(e));
    }
  }


  // ==================== 平板/折叠屏宽屏适配 ====================
  // 宽屏断点（由 EntryAbility 统一检测并写入 AppStorage）：窗口宽度 >= 840vp 时切换为侧边导航 + 内容限宽布局
  @StorageProp('isWideScreen') isWideScreen: boolean = false;

  // 全屏沉浸式布局：状态栏避让高度（vp），由 EntryAbility 发布到 AppStorage，主内容列据此留白避让
  @StorageProp('statusBarVp') statusBarVp: number = 46;
  // 底部手势条避让高度（vp）：悬浮页签栏整体抬到手势条上方
  @StorageProp('navBarVp') navBarVp: number = 28;

  // 宽屏时底部悬浮页签栏样式（窄屏返回悬浮样式，宽屏返回 undefined 使用侧边栏默认样式）
  private getTabBarFloatingStyle(): HdsTabsFloatingStyle | undefined {
    if (this.isWideScreen) {
      return undefined;
    }
    return {
      // 页签栏悬浮于底部手势条上方：barBottomMargin 取手势条避让高度，
      // 小横杠不再叠在栏体上，栏体与屏幕底边留出手势条空间
      barBottomMargin: this.navBarVp,
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.IMMERSIVE,
        materialLevel: hdsMaterial.MaterialLevel.EXQUISITE
      }
    };
  }


  async aboutToAppear() {
    console.info('📌 aboutToAppear 开始');
    this.loadUserProgress();
    this.initPrivacyLockState();
    this.loadHapticEnabled();
    this.loadReminderData();
    // 未读提醒圆点呼吸：轻微缩放往复，提示有待处理事项
    animateTo({
      duration: 1100,
      curve: Curve.EaseInOut,
      iterations: -1,
      playMode: PlayMode.Alternate
    }, () => {
      this.reminderDotPulse = 1.35;
    });

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
        this.updateStatSummary();
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
            const delta: number = (year * 12 + month) - (this.billViewYear * 12 + this.billViewMonth);
            this.switchBillMonth(delta, year, month);
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

    // ✅ 加载账单页视图偏好（列表/日历）
    this.loadBillViewMode();

    // ✅ 加载账单页汇总卡固定偏好
    this.loadBillSummaryPinned();

    // ✅ 加载自定义主题颜色并应用到全局
    this.loadBrandThemeIndex();
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

  private billWeekLabels: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];

  // 账单页：浏览月份的总支出（当前账本，不受分类/标签筛选影响）
  getBillViewMonthExpense(): number {
    let sum = 0;
    this.bills.forEach((b: BillItem) => {
      const d = new Date(b.date);
      if ((b.ledgerId ?? DEFAULT_LEDGER_ID) === this.currentLedgerId &&
        d.getFullYear() === this.billViewYear && (d.getMonth() + 1) === this.billViewMonth &&
        b.type === '支出') {
        sum += b.amount;
      }
    });
    return sum;
  }

  // 账单页：浏览月份的总收入
  getBillViewMonthIncome(): number {
    let sum = 0;
    this.bills.forEach((b: BillItem) => {
      const d = new Date(b.date);
      if ((b.ledgerId ?? DEFAULT_LEDGER_ID) === this.currentLedgerId &&
        d.getFullYear() === this.billViewYear && (d.getMonth() + 1) === this.billViewMonth &&
        b.type === '收入') {
        sum += b.amount;
      }
    });
    return sum;
  }

  // 账单页：月结余（收入 - 支出）
  getBillViewMonthBalance(): number {
    return this.getBillViewMonthIncome() - this.getBillViewMonthExpense();
  }

  // 账单页：按日期分组（日期倒序，组内按时间倒序）
  getBillDayGroups(): DayBillGroup[] {
    const bills = this.getBillViewBills();
    const map = new Map<number, BillItem[]>();
    bills.forEach((item: BillItem) => {
      const d = new Date(item.date);
      const key = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
      const existing = map.get(key);
      if (existing !== undefined) {
        existing.push(item);
      } else {
        map.set(key, [item]);
      }
    });

    const groups: DayBillGroup[] = [];
    map.forEach((list: BillItem[], key: number) => {
      const sorted = [...list].sort((a: BillItem, b: BillItem) => b.date - a.date);
      let expense = 0;
      let income = 0;
      sorted.forEach((b: BillItem) => {
        if (b.type === '收入') {
          income += b.amount;
        } else {
          expense += b.amount;
        }
      });
      groups.push({
        date: key,
        dayExpense: expense,
        dayIncome: income,
        bills: sorted
      });
    });

    groups.sort((a: DayBillGroup, b: DayBillGroup) => b.date - a.date);
    return groups;
  }

  // 账单页：日期卡片标题（今天/昨天/M月d日 周X/跨年含年份）
  formatBillDayHeader(ts: number): string {
    const d = new Date(ts);
    const now = new Date();
    const startToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
    if (ts === startToday) {
      return '今天';
    }
    if (ts === startToday - 24 * 60 * 60 * 1000) {
      return '昨天';
    }
    const week = this.billWeekLabels[d.getDay()];
    if (d.getFullYear() === now.getFullYear()) {
      return `${d.getMonth() + 1}月${d.getDate()}日 ${week}`;
    }
    return `${d.getFullYear()}年${d.getMonth() + 1}月${d.getDate()}日`;
  }

  // 账单页：日期卡片右上角当日收支摘要
  getBillDaySummaryText(group: DayBillGroup): string {
    const parts: string[] = [];
    if (group.dayExpense > 0) {
      parts.push('支 ¥' + group.dayExpense.toFixed(2));
    }
    if (group.dayIncome > 0) {
      parts.push('收 ¥' + group.dayIncome.toFixed(2));
    }
    return parts.join(' · ');
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
  showMultiDayDetailDialog(days: number[], year: number = this.currentYear, month: number = this.currentMonth) {
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
    return this.getExpenseStatsFrom(this.getStatPeriodBills());
  }

  getExpenseStatsFrom(bills: BillItem[]): ExpenseStat[] {
    const map = new Map<string, number>();
    bills
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
    // 每日支出建议：仅当查看的是真实当前月份时，按「剩余预算 ÷ 剩余天数(含今天)」计算
    const now = new Date();
    let dailySuggestion = 0;
    let remainingDays = 0;
    if (now.getFullYear() === this.currentYear && (now.getMonth() + 1) === this.currentMonth && !isOverBudget) {
      const daysInMonth = new Date(this.currentYear, this.currentMonth, 0).getDate();
      remainingDays = daysInMonth - now.getDate() + 1;
      if (remainingDays > 0) {
        dailySuggestion = remaining / remainingDays;
      }
    }
    return {
      monthlyExpense,
      usedPercentForDisplay,
      usedPercentForColor,
      isOverBudget,
      remaining,
      dailySuggestion,
      remainingDays
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

  // ---------- 统计页周期 ----------
  dayStartOf(ts: number): number {
    const d = new Date(ts);
    return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
  }

  getStatPeriodRange(): StatDateRange {
    const anchor = new Date(this.statAnchorTime);
    if (this.statPeriod === 'week') {
      const dow = anchor.getDay() === 0 ? 7 : anchor.getDay();
      const start = this.dayStartOf(anchor.getTime()) - (dow - 1) * 86400000;
      return { start: start, end: start + 6 * 86400000 };
    }
    if (this.statPeriod === 'year') {
      return {
        start: new Date(anchor.getFullYear(), 0, 1).getTime(),
        end: new Date(anchor.getFullYear(), 11, 31).getTime()
      };
    }
    if (this.statPeriod === 'all') {
      const today = this.dayStartOf(new Date().getTime());
      let earliest = today;
      for (let i = 0; i < this.bills.length; i++) {
        const bill = this.bills[i];
        if ((bill.ledgerId ?? DEFAULT_LEDGER_ID) !== this.currentLedgerId) continue;
        const t = this.dayStartOf(new Date(bill.date).getTime());
        if (t < earliest) earliest = t;
      }
      return { start: earliest, end: today };
    }
    if (this.statPeriod === 'range') {
      const today = this.dayStartOf(new Date().getTime());
      let s = this.statRangeStart > 0 ? this.dayStartOf(this.statRangeStart) : today - 29 * 86400000;
      let e = this.statRangeEnd > 0 ? this.dayStartOf(this.statRangeEnd) : today;
      if (s > e) {
        const tmp = s;
        s = e;
        e = tmp;
      }
      return { start: s, end: e };
    }
    // month（默认）
    return {
      start: new Date(anchor.getFullYear(), anchor.getMonth(), 1).getTime(),
      end: new Date(anchor.getFullYear(), anchor.getMonth() + 1, 0).getTime()
    };
  }

  getStatPeriodBills(): BillItem[] {
    const range = this.getStatPeriodRange();
    const endLimit = range.end + 86400000;
    return this.bills.filter(item => {
      if ((item.ledgerId ?? DEFAULT_LEDGER_ID) !== this.currentLedgerId) return false;
      const t = this.dayStartOf(new Date(item.date).getTime());
      return t >= range.start && t < endLimit;
    });
  }

  getStatPeriodExpense(): number {
    let sum = 0;
    this.getStatPeriodBills().forEach((b: BillItem) => {
      if (b.type === '支出') sum += b.amount;
    });
    return sum;
  }

  getStatPeriodIncome(): number {
    let sum = 0;
    this.getStatPeriodBills().forEach((b: BillItem) => {
      if (b.type === '收入') sum += b.amount;
    });
    return sum;
  }

  getStatPeriodBalance(): number {
    return this.getStatPeriodIncome() - this.getStatPeriodExpense();
  }

  getStatAvgDailyExpense(): number {
    const range = this.getStatPeriodRange();
    const today = this.dayStartOf(new Date().getTime());
    const effEnd = Math.min(range.end, today);
    const days = Math.max(1, Math.floor((effEnd - range.start) / 86400000) + 1);
    return this.getStatPeriodExpense() / days;
  }

  getStatPeriodLabel(): string {
    const range = this.getStatPeriodRange();
    const s = new Date(range.start);
    const e = new Date(range.end);
    if (this.statPeriod === 'year') {
      return `${s.getFullYear()}年`;
    }
    if (this.statPeriod === 'all') {
      return '全部账单';
    }
    if (s.getMonth() === e.getMonth() && s.getFullYear() === e.getFullYear()) {
      if (this.statPeriod === 'week' || this.statPeriod === 'range') {
        return `${s.getMonth() + 1}月${s.getDate()}日 - ${e.getDate()}日`;
      }
      return `${s.getFullYear()}年${s.getMonth() + 1}月`;
    }
    return `${s.getMonth() + 1}月${s.getDate()}日 - ${e.getMonth() + 1}月${e.getDate()}日`;
  }

  shiftStatPeriod(delta: number) {
    if (this.statPeriod === 'week') {
      this.statAnchorTime += delta * 7 * 86400000;
    } else if (this.statPeriod === 'month') {
      const a = new Date(this.statAnchorTime);
      this.statAnchorTime = new Date(a.getFullYear(), a.getMonth() + delta, 1).getTime();
    } else if (this.statPeriod === 'year') {
      const a = new Date(this.statAnchorTime);
      this.statAnchorTime = new Date(a.getFullYear() + delta, a.getMonth(), 1).getTime();
    } else {
      return;
    }
    hapticTick();
    this.playStatContentTransition();
    this.refreshStatCharts();
  }

  onStatPeriodTap(key: string) {
    if (key === this.statPeriod) return;
    hapticTick();
    if (key === 'range') {
      this.pickStatRange();
      return;
    }
    animateTo({ curve: AnimationConfig.SPRING }, () => {
      this.statPeriod = key;
    });
    this.statAnchorTime = new Date().getTime();
    this.playStatContentTransition();
    this.refreshStatCharts();
  }

  pickStatRange() {
    const ui = this.getUIContext();
    const today = new Date();
    ui.showDatePickerDialog({
      start: new Date(2000, 0, 1),
      end: today,
      selected: this.statRangeStart > 0 ? new Date(this.statRangeStart)
        : new Date(today.getFullYear(), today.getMonth(), today.getDate() - 29),
      onDateAccept: (value: Date) => {
        const start = this.dayStartOf(value.getTime());
        ui.showDatePickerDialog({
          start: value,
          end: today,
          selected: this.statRangeEnd > 0 ? new Date(this.statRangeEnd) : today,
          onDateAccept: (v2: Date) => {
            this.statRangeStart = start;
            this.statRangeEnd = this.dayStartOf(v2.getTime());
            animateTo({ curve: AnimationConfig.SPRING }, () => {
              this.statPeriod = 'range';
            });
            hapticTick();
            this.playStatContentTransition();
            this.refreshStatCharts();
          }
        });
      }
    });
  }

  // 周期切换时内容过渡：瞬间缩隐，随后弹簧回弹（Q弹效果）
  playStatContentTransition() {
    this.statContentOpacity = 0;
    this.statContentScale = 0.94;
    setTimeout(() => {
      animateTo({ curve: AnimationConfig.SPRING }, () => {
        this.statContentOpacity = 1;
        this.statContentScale = 1;
      });
    }, 90);
  }

  refreshStatCharts() {
    this.updateStatSummary();
    setTimeout(() => {
      this.drawPieChart();
      this.drawTrendChart();
    }, 50);
  }

  // 重算统计页汇总缓存（数据或周期变化时调用）
  updateStatSummary() {
    this.statSummaryExpense = this.getStatPeriodExpense();
    this.statSummaryIncome = this.getStatPeriodIncome();
    this.statSummaryBalance = this.getStatPeriodBalance();
    this.statSummaryAvgDaily = this.getStatAvgDailyExpense();
    this.statRangeLabelText = this.getStatPeriodLabel();
    this.statLegendStats = this.getExpenseStats();
  }

  // 统计页趋势数据：周/月/短范围=按天，年/全部/长范围=按月聚合
  getStatTrendPoints(): StatTrendPoint[] {
    const range = this.getStatPeriodRange();
    const bills = this.getStatPeriodBills().filter(b => b.type === '支出');
    const dayMs = 86400000;
    const dayCount = Math.floor((range.end - range.start) / dayMs) + 1;
    const weekLabels: string[] = ['日', '一', '二', '三', '四', '五', '六'];

    if (this.statPeriod === 'year') {
      const y = new Date(range.start).getFullYear();
      const monthly: number[] = new Array(12).fill(0);
      bills.forEach((b: BillItem) => {
        monthly[new Date(b.date).getMonth()] += b.amount;
      });
      const pts: StatTrendPoint[] = [];
      for (let i = 0; i < 12; i++) {
        pts.push({ label: `${i + 1}月`, amount: monthly[i], day: 0 });
      }
      return pts;
    }

    if (this.statPeriod === 'all' || (this.statPeriod === 'range' && dayCount > 62)) {
      const sY = new Date(range.start).getFullYear();
      const sM = new Date(range.start).getMonth();
      const eY = new Date(range.end).getFullYear();
      const eM = new Date(range.end).getMonth();
      const totalMonths = (eY - sY) * 12 + (eM - sM) + 1;
      const amounts: number[] = new Array(totalMonths).fill(0);
      bills.forEach((b: BillItem) => {
        const d = new Date(b.date);
        const idx = (d.getFullYear() - sY) * 12 + (d.getMonth() - sM);
        if (idx >= 0 && idx < totalMonths) amounts[idx] += b.amount;
      });
      const pts: StatTrendPoint[] = [];
      for (let i = 0; i < totalMonths; i++) {
        pts.push({ label: `${((sM + i) % 12) + 1}月`, amount: amounts[i], day: 0 });
      }
      return pts;
    }

    // 天级：周 / 月 / 短范围
    const pts: StatTrendPoint[] = [];
    for (let i = 0; i < dayCount; i++) {
      const d = new Date(range.start + i * dayMs);
      if (this.statPeriod === 'week') {
        pts.push({ label: weekLabels[d.getDay()], amount: 0, day: d.getDate() });
      } else {
        pts.push({ label: `${d.getDate()}日`, amount: 0, day: d.getDate() });
      }
    }
    bills.forEach((b: BillItem) => {
      const t = this.dayStartOf(new Date(b.date).getTime());
      const idx = Math.floor((t - range.start) / dayMs);
      if (idx >= 0 && idx < pts.length) pts[idx].amount += b.amount;
    });
    return pts;
  }

  // 处理趋势图点击
  handleTrendClick(x: number, y: number) {
    const data = this.getStatTrendPoints();
    if (data.length < 2) {
      promptAction.showToast({ message: '暂无趋势数据', duration: 1500 });
      return;
    }
    const maxAmount = Math.max(...data.map(d => d.amount), 1);
    const canvasWidth = this.trendCanvasWidth || 400;
    const padding: Padding = { top: 20, bottom: 36, left: 32, right: 10 };
    const chartWidth = canvasWidth - padding.left - padding.right;
    const chartHeight = 200 - padding.top - padding.bottom;

    const hitIndexes: number[] = [];
    let nearestIndex = -1;
    let minDistance = 45;
    for (let i = 0; i < data.length; i++) {
      if (data[i].amount === 0) continue;
      const px = padding.left + (i / (data.length - 1 || 1)) * chartWidth;
      const py = padding.top + chartHeight - (data[i].amount / maxAmount) * chartHeight;
      const distance = Math.sqrt((x - px) ** 2 + (y - py) ** 2);
      if (distance < 45) {
        hitIndexes.push(i);
        if (distance < minDistance) {
          minDistance = distance;
          nearestIndex = i;
        }
      }
    }

    if (hitIndexes.length === 0) {
      promptAction.showToast({ message: '没有命中数据点', duration: 1500 });
      return;
    }

    // 天级数据且首尾同月 → 弹详情窗；否则（月级聚合 / 跨月）弹 toast
    const range = this.getStatPeriodRange();
    const s = new Date(range.start);
    const e = new Date(range.end);
    const isDayLevel = this.statPeriod === 'week' || this.statPeriod === 'month' ||
      (this.statPeriod === 'range' && s.getFullYear() === e.getFullYear() && s.getMonth() === e.getMonth());
    if (isDayLevel) {
      const hitDays: number[] = hitIndexes.map(i => data[i].day);
      this.showMultiDayDetailDialog(hitDays, s.getFullYear(), s.getMonth() + 1);
    } else if (nearestIndex >= 0) {
      const p = data[nearestIndex];
      promptAction.showToast({ message: `${p.label} 支出 ¥${p.amount.toFixed(2)}`, duration: 1500 });
    }
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

  // 等待指定毫秒（动画编排用）
  waitMs(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, ms);
    });
  }

  // 记账页月份切换：旧内容滑出 → 换月 → 新内容从对侧滑入
  async switchHomeMonth(delta: number): Promise<void> {
    if (this.homeMonthSwitching) return;
    this.homeMonthSwitching = true;

    // 1. 旧内容沿切换方向滑出并淡出
    animateTo({ duration: 160, curve: Curve.EaseIn }, () => {
      this.homeContentShiftX = -delta * 56;
      this.homeContentAlpha = 0;
    });
    await this.waitMs(170);

    // 2. 更新月份数据（此时内容不可见）
    if (delta > 0) {
      if (this.currentMonth === 12) {
        this.currentMonth = 1;
        this.currentYear++;
      } else {
        this.currentMonth++;
      }
    } else {
      if (this.currentMonth === 1) {
        this.currentMonth = 12;
        this.currentYear--;
      } else {
        this.currentMonth--;
      }
    }
    this.updateChartIfNeeded();
    this.loadBudget();

    // 3. 瞬移到对侧起点
    animateTo({ duration: 0 }, () => {
      this.homeContentShiftX = delta * 56;
    });
    await this.waitMs(30);

    // 4. 新内容弹簧滑入
    animateTo({ duration: 360, curve: AnimationConfig.SPRING_SOFT }, () => {
      this.homeContentShiftX = 0;
      this.homeContentAlpha = 1;
    });
    await this.waitMs(40);
    this.homeMonthSwitching = false;
  }

  goPreviousMonth() {
    this.switchHomeMonth(-1);
  }

  goNextMonth() {
    this.switchHomeMonth(1);
  }

  // 账单页月份切换：同款方向性滑动；delta 为月份差（方向取符号），可指定目标年月
  async switchBillMonth(delta: number, targetYear?: number, targetMonth?: number): Promise<void> {
    if (this.billMonthSwitching) return;
    this.billMonthSwitching = true;
    hapticTick();
    const dir: number = delta >= 0 ? 1 : -1;

    // 1. 旧内容滑出
    animateTo({ duration: 160, curve: Curve.EaseIn }, () => {
      this.billContentShiftX = -dir * 56;
      this.billContentAlpha = 0;
    });
    await this.waitMs(170);

    // 2. 更新月份数据
    if (targetYear !== undefined && targetMonth !== undefined) {
      this.billViewYear = targetYear;
      this.billViewMonth = targetMonth;
    } else if (delta > 0) {
      if (this.billViewMonth === 12) {
        this.billViewMonth = 1;
        this.billViewYear++;
      } else {
        this.billViewMonth++;
      }
    } else {
      if (this.billViewMonth === 1) {
        this.billViewMonth = 12;
        this.billViewYear--;
      } else {
        this.billViewMonth--;
      }
    }

    // 3. 瞬移到对侧起点
    animateTo({ duration: 0 }, () => {
      this.billContentShiftX = dir * 56;
    });
    await this.waitMs(30);

    // 4. 新内容弹簧滑入
    animateTo({ duration: 360, curve: AnimationConfig.SPRING_SOFT }, () => {
      this.billContentShiftX = 0;
      this.billContentAlpha = 1;
    });
    await this.waitMs(40);
    this.billMonthSwitching = false;
  }

  goBillPrevMonth() {
    this.switchBillMonth(-1);
  }

  goBillNextMonth() {
    this.switchBillMonth(1);
  }

  // 账单页汇总卡：瞬间隐藏 → 弹簧回弹（支出/收入切换时）
  playBillSummaryTransition() {
    animateTo({ duration: 90, curve: Curve.EaseIn }, () => {
      this.billSummaryOpacity = 0;
      this.billSummaryScale = 0.92;
    });
    setTimeout(() => {
      animateTo({ duration: 360, curve: AnimationConfig.SPRING_SOFT }, () => {
        this.billSummaryOpacity = 1;
        this.billSummaryScale = 1;
      });
    }, 95);
  }

  // ---------- 账单页视图切换：列表 / 日历 ----------
  switchBillViewMode(mode: string) {
    if (mode === this.billViewMode) return;
    hapticTick();
    animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
      this.billViewMode = mode;
    });
    this.saveBillViewMode();
  }

  async loadBillViewMode() {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');
      const mode = await prefs.get('bill_view_mode', 'list') as string;
      this.billViewMode = mode === 'calendar' ? 'calendar' : 'list';
    } catch (e) {
      console.error('加载账单视图偏好失败', e);
    }
  }

  async saveBillViewMode() {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');
      await prefs.put('bill_view_mode', this.billViewMode);
      await prefs.flush();
    } catch (e) {
      console.error('保存账单视图偏好失败', e);
    }
  }

  // ---------- 账单页汇总卡固定开关（钉子） ----------
  toggleBillSummaryPinned() {
    hapticTick();
    animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
      this.billSummaryPinned = !this.billSummaryPinned;
    });
    this.saveBillSummaryPinned();
  }

  async loadBillSummaryPinned() {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');
      const pinned = await prefs.get('bill_summary_pinned', true) as boolean;
      this.billSummaryPinned = pinned;
    } catch (e) {
      console.error('加载汇总卡固定偏好失败', e);
    }
  }

  async saveBillSummaryPinned() {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');
      await prefs.put('bill_summary_pinned', this.billSummaryPinned);
      await prefs.flush();
    } catch (e) {
      console.error('保存汇总卡固定偏好失败', e);
    }
  }

  // 账单页汇总卡片（固定在顶部 / 随账单列表滚动两种摆放共用）
  @Builder
  BillSummaryCard() {
    Column() {
      Row() {
        Column() {
          Text(this.billSummaryMode === 'expense' ? '本月总支出' : '本月总收入')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
          Text('¥' + (this.billSummaryMode === 'expense' ?
            this.getBillViewMonthExpense() : this.getBillViewMonthIncome()).toFixed(2))
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.billSummaryMode === 'expense' ?
            $r('app.color.expense_red') : $r('app.color.income_gold'))
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)

        Blank()

        // 支出/收入切换
        Row() {
          Text('支出')
            .fontSize(15)
            .fontColor(this.billSummaryMode === 'expense' ? this.brandMain : $r('app.color.text_secondary'))
            .fontWeight(this.billSummaryMode === 'expense' ? FontWeight.Medium : FontWeight.Normal)
            .padding({ left: 12, right: 12, top: 4, bottom: 4 })
            .borderRadius(12)
            .backgroundColor(this.billSummaryMode === 'expense' ? this.brandTint : Color.Transparent)
            .onClick(() => {
              if (this.billSummaryMode !== 'expense') {
                animateTo({ duration: 200, curve: AnimationConfig.SPRING_SOFT }, () => {
                  this.billSummaryMode = 'expense';
                });
                this.playBillSummaryTransition();
              }
            })
          Text('收入')
            .fontSize(15)
            .fontColor(this.billSummaryMode === 'income' ? this.brandMain : $r('app.color.text_secondary'))
            .fontWeight(this.billSummaryMode === 'income' ? FontWeight.Medium : FontWeight.Normal)
            .padding({ left: 12, right: 12, top: 4, bottom: 4 })
            .borderRadius(12)
            .backgroundColor(this.billSummaryMode === 'income' ? this.brandTint : Color.Transparent)
            .onClick(() => {
              if (this.billSummaryMode !== 'income') {
                animateTo({ duration: 200, curve: AnimationConfig.SPRING_SOFT }, () => {
                  this.billSummaryMode = 'income';
                });
                this.playBillSummaryTransition();
              }
            })
        }

        // 固定开关（钉子）：固定时常驻顶部，取消固定后随账单一起滚动、列表可视面积更大
        SymbolGlyph(this.billSummaryPinned ? $r('sys.symbol.pin_fill') : $r('sys.symbol.pin'))
          .fontSize(17)
          .fontColor([this.billSummaryPinned ? this.brandMain : $r('app.color.text_secondary')])
          .padding(6)
          .borderRadius(10)
          .margin({ left: 8 })
          .onClick(() => { this.toggleBillSummaryPinned(); })
      }
      .width('100%')

      Divider()
        .color($r('app.color.border_color'))
        .margin({ top: 14, bottom: 10 })

      Row() {
        Text('月结余')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
        Blank()
        Text((this.getBillViewMonthBalance() >= 0 ? '+' : '') + '¥' + this.getBillViewMonthBalance().toFixed(2))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getBillViewMonthBalance() >= 0 ?
          $r('app.color.income_gold') : $r('app.color.expense_red'))
      }
      .width('100%')
    }
    .opacity(this.billSummaryOpacity)
    .scale({ x: this.billSummaryScale, y: this.billSummaryScale })
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius({ topLeft: 18, topRight: 15, bottomLeft: 17, bottomRight: 19 })
    .shadow({ radius: 0, color: $r('app.color.ink_shadow'), offsetX: 3, offsetY: 3 }).border({ width: 1, color: $r('app.color.ink_line') })
    .margin({ bottom: 12 })
  }

  // ---------- 增删改账单 ----------
  addBill(name: string, amount: number, type: '收入' | '支出', date: Date, category: string, source: string, tags?: string[], photos?: string[]) {
    const newBill: BillItem = {
      id: this.nextBillId(),
      name: name,
      amount: amount,
      type: type,
      date: date.getTime(),
      category: category || '其他',
      source: source || '现金',
      tags: tags || [],  // ✅ 使用传入的 tags
      ledgerId: this.currentLedgerId,  // 记入当前选中账本
      photoUris: photos && photos.length > 0 ? photos : []
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
    this.refreshKey++;  // 强制刷新账单页分组列表（嵌套 ForEach 组键值需变化才会重渲染）
    this.saveBillsToPreferences();
    this.loadBudget();
    this.grantBillXpAndCheck(newBill);  // 记账经验（含连击加成）并检查成就解锁 + 新玩法钩子
  }

  // 删除账单：移入回收站（保留 30 天，可在"我的-回收站"恢复）
  deleteBill(id: number) {
    const billToDelete = this.bills.find(item => item.id === id);
    animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
      this.bills = this.bills.filter(item => item.id !== id);
    });
    if (billToDelete) {
      this.updateAsset(billToDelete.source, billToDelete.type, billToDelete.amount, 'remove');
      this.moveToRecycleBin([billToDelete]);
      promptAction.showToast({ message: '已移入回收站，30天内可恢复', duration: 1500 });
    }
    this.refreshKey++;  // 强制刷新账单页分组列表（嵌套 ForEach 组键值需变化才会重渲染）
    this.saveBillsToPreferences();
    this.loadBudget();
  }

  // 将账单移入回收站（同时清理已过保留期的条目）
  async moveToRecycleBin(items: BillItem[]): Promise<void> {
    if (items.length === 0) {
      return;
    }
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');
      const data = await prefs.get(RECYCLE_BIN_KEY, '[]') as string;
      const existing = JSON.parse(data) as RecycleBillItem[];
      const now = Date.now();
      const valid = existing.filter((it: RecycleBillItem) => now - it.deletedAt < RECYCLE_RETENTION_MS);
      // 已过保留期的条目被清理时，同步删除其小票图片文件
      const expired = existing.filter((it: RecycleBillItem) => now - it.deletedAt >= RECYCLE_RETENTION_MS);
      expired.forEach((it: RecycleBillItem) => {
        if (it.bill.photoUris && it.bill.photoUris.length > 0) {
          deleteBillPhotos(it.bill.photoUris);
        }
      });
      const newItems: RecycleBillItem[] = items.map((bill: BillItem): RecycleBillItem => {
        return { bill: bill, deletedAt: now };
      });
      await prefs.put(RECYCLE_BIN_KEY, JSON.stringify([...newItems, ...valid]));
      await prefs.flush();
    } catch (e) {
      console.error('移入回收站失败: ' + JSON.stringify(e));
    }
  }

  async updateBill(id: number, name: string, amount: number, type: '收入' | '支出', date: Date, category: string, source: string, tags?: string[], photos?: string[]) {
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
      ledgerId: oldBill.ledgerId,  // 保留原账本归属
      recurringKey: oldBill.recurringKey,  // 保留周期账单标记
      photoUris: photos || [],
      // 退款相关的交易元数据必须由 persisted 数据带过来，不能丢：
      // orderNo 是下次导入同一份支付宝/微信账单时精确匹配退款的唯一凭据，
      // 一旦丢掉，这笔账单后续再也无法自动抵扣退款
      orderNo: oldBill.orderNo,
      refundAmount: oldBill.refundAmount !== undefined && oldBill.refundAmount > 0 ?
        oldBill.refundAmount : undefined,
      // 净额被改动时同步重算原始支付金额（原始 = 新净额 + 已退款）
      originalAmount: oldBill.refundAmount !== undefined && oldBill.refundAmount > 0 ?
        Math.round((amount + oldBill.refundAmount) * 100) / 100 : undefined
    };

    // 编辑中被移除的图片文件同步删除
    const removedPhotos: string[] = (oldBill.photoUris || []).filter((uri: string): boolean =>
      (updatedBill.photoUris || []).indexOf(uri) === -1);
    if (removedPhotos.length > 0) {
      deleteBillPhotos(removedPhotos);
    }

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
    const minDate = this.bills.reduce((min: number, b: BillItem): number => b.date < min ? b.date : min,
      this.bills[0].date);
    const firstDate = new Date(minDate);
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

  // 带动画地更新记账提醒开关状态（下方设置项随之展开/收起）
  setReminderOnAnimated(value: boolean) {
    animateTo({ curve: AnimationConfig.SPRING }, () => {
      this.isReminderOn = value;
    });
  }

  async onReminderToggle(isOn: boolean) {
    // 异步发布/取消期间忽略再次点击，避免竞态
    if (this.reminderBusy) {
      this.setReminderOnAnimated(!isOn);
      return;
    }
    hapticTick();
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
      this.setReminderOnAnimated(false);
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
      this.setReminderOnAnimated(false);
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
      message: '乌鸡记账 v1.5.0\n\n用心记录每一笔，养肥你的小金库。\n\n© 2026 乌鸡工作室',
      buttons: [
        { text: '确定', color: this.brandMain }
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
        billsToExport = [...this.bills];
      }

      if (billsToExport.length === 0) {
        promptAction.showToast({ message: '没有账单可导出', duration: 2000 });
        return;
      }

      billsToExport.sort((a, b) => a.date - b.date);

      // 完整列：资金来源、标签、已退款、订单号都要带上，
      // 否则用户导出再导入（换机、备份恢复）时会静默丢失这些字段
      let csvContent = '\uFEFF日期,类型,分类,用途,金额,账本,资金来源,标签,已退款,订单号\n';
      for (let item of billsToExport) {
        const d = new Date(item.date);
        const dateStr = d.getFullYear() + '-' +
          String(d.getMonth() + 1).padStart(2, '0') + '-' +
          String(d.getDate()).padStart(2, '0');
        const typeStr = item.type === '收入' ? '收入' : '支出';
        const tagStr: string = item.tags !== undefined ? item.tags.join(';') : '';
        const refundStr: string =
          (item.refundAmount !== undefined && item.refundAmount > 0) ? item.refundAmount.toFixed(2) : '0.00';
        const orderStr: string = item.orderNo !== undefined ? item.orderNo : '';
        csvContent += dateStr + ',' + typeStr + ',' + escapeCsvField(item.category) + ',' +
          escapeCsvField(item.name) + ',' + item.amount.toFixed(2) + ',' +
          escapeCsvField(this.getLedgerNameById(item.ledgerId)) + ',' +
          escapeCsvField(item.source) + ',' + escapeCsvField(tagStr) + ',' +
          refundStr + ',' + escapeCsvField(orderStr) + '\n';
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
      const recurringData = await prefs.get('recurring_bills', '[]') as string;

      const backupData: BackupData = {
        version: '1.1',
        exportTime: new Date().toISOString(),
        bills: JSON.parse(billsData),
        assets: JSON.parse(assetData),
        ledgers: JSON.parse(ledgersData) as LedgerItem[],
        recurring: JSON.parse(recurringData) as RecurringBill[]
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
          { text: '取消', color: $r('app.color.text_secondary') },
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
      if (backupData.recurring !== undefined && Array.isArray(backupData.recurring)) {
        await prefs.put('recurring_bills', JSON.stringify(backupData.recurring));
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

  // 「我的」页导入账单入口：选择导入微信账单还是支付宝账单
  chooseImportSource() {
    this.getUIContext().getPromptAction().showActionMenu({
      title: '选择账单来源',
      buttons: [
        { text: '微信账单（Excel）', color: this.brandMain },
        { text: '支付宝账单（CSV）', color: this.brandMain },
        { text: '取消', color: $r('app.color.text_secondary') }
      ]
    }).then((result: promptAction.ActionMenuSuccessResponse) => {
      if (result.index === 0) {
        this.importBillsFromFile('wechat');
      } else if (result.index === 1) {
        this.importBillsFromFile('alipay');
      }
    }).catch(() => {
    });
  }

  // 导入账单：'wechat' 微信账单（Excel）| 'alipay' 支付宝账单（CSV，GBK 编码）
  async importBillsFromFile(format: string) {
    if (this.isLoading) {
      return;
    }
    this.isLoading = true;

    try {
      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker();
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      options.fileSuffixFilters = format === 'alipay' ? ['csv'] : ['xlsx', 'xls'];
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
          const file: fs.File = fs.openSync(uri, fs.OpenMode.READ_ONLY);
          const stat: fs.Stat = fs.statSync(file.fd);
          const fileContent: ArrayBuffer = new ArrayBuffer(stat.size);
          fs.readSync(file.fd, fileContent);
          fs.closeSync(file);

          // 组装 worker 参数：账本摘要 + 既有账单 JSON（@State 数组先 stringify 成普通数据再跨线程传输）
          const ledgerBriefs: Array<LedgerBrief> = this.ledgers.map((lg: LedgerItem): LedgerBrief => {
            const brief: LedgerBrief = {
              id: lg.id,
              name: lg.name,
              categories: [...lg.categories]
            };
            return brief;
          });
          const existingBillsJson: string = JSON.stringify(this.bills);

          // 退款记录用于重复导入时的幂等（已抵扣过的退款不重复抵扣）
          const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
          let refundRecordsJson: string = '[]';
          let prefs: dataPreferences.Preferences | undefined = undefined;
          if (context) {
            prefs = await dataPreferences.getPreferences(context, 'bill_data');
            refundRecordsJson = await prefs.get('refund_records', '[]') as string;
          }

          // 文件解析、查重、分类匹配、账单组装、合并序列化全部在 taskpool 线程完成，
          // 主线程只做文件读取和落盘，账单量大时加载动画不再卡顿
          const result: ImportWorkerResult = await taskpool.execute(importBillsInWorker,
            fileContent, format, existingBillsJson, ledgerBriefs, [...CATEGORIES], this.currentLedgerId, DEFAULT_LEDGER_ID, refundRecordsJson
          ) as ImportWorkerResult;
          const importedCount: number = result.importedCount;

          // 导入的账单不同步改动资金账户余额（有意如此）：
          // 导入的是历史流水，而资产账户余额代表"当下"的实有金额，
          // 用户手动设置余额时通常已经包含了这些历史交易，再扣一遍会重复计算
          this.bills = this.bills.concat(result.newBills);
          // 退款抵扣同步到界面：更新原账单净金额与退款信息（账单记录保留）
          if (result.existingUpdates.length > 0) {
            const updates: Array<ExistingBillUpdate> = result.existingUpdates;
            this.bills = this.bills.map((b: BillItem): BillItem => {
              for (let ui: number = 0; ui < updates.length; ui++) {
                if (updates[ui].id === b.id) {
                  const copy: BillItem = {
                    id: b.id,
                    name: b.name,
                    amount: updates[ui].amount,
                    type: b.type,
                    date: b.date,
                    category: b.category,
                    source: b.source,
                    ledgerId: b.ledgerId,
                    recurringKey: b.recurringKey,
                    tags: b.tags,
                    photoUris: b.photoUris,
                    refundAmount: updates[ui].refundAmount,
                    originalAmount: updates[ui].originalAmount,
                    orderNo: b.orderNo
                  };
                  return copy;
                }
              }
              return b;
            });
          }
          this.refreshKey++;
          // 导入的 id 可能远大于此前分配过的主键，重算水位防止后续记账撞号
          this.refreshBillIdWatermark();

          // 直接写入 worker 序列化好的合并结果，避免主线程再对大数组做 JSON.stringify
          if (prefs) {
            await prefs.put('bills_key', result.mergedJson);
            await prefs.put('refund_records', result.refundRecordsJson);
            await prefs.flush();
            this.updateStatSummary();
            console.info('✅ 账单已保存到 Preferences，共 ' + this.bills.length + ' 条');
          } else {
            await this.saveBillsToPreferences();
          }

          const elapsed: number = Date.now() - startTime;
          const minDisplayTime: number = 500;

          const finishImport = () => {
            if (this.loadingDialogController) {
              this.loadingDialogController.close();
            }
            this.isLoading = false;
            let toastMsg: string = `导入成功，共导入 ${importedCount} 条账单`;
            if (result.refundNettedCount > 0) {
              toastMsg += `，退款抵扣 ${result.refundNettedCount} 笔`;
            }
            if (result.refundUnmatchedCount > 0) {
              toastMsg += `，${result.refundUnmatchedCount} 笔退款未匹配到原账单`;
            }
            promptAction.showToast({
              message: toastMsg,
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

  // 显示删除确认弹窗
  showDeleteConfirmDialog() {
    const billsToDelete: BillItem[] = this.getBillViewBills();
    if (billsToDelete.length === 0) {
      promptAction.showToast({ message: '当前没有可删除的账单', duration: 1500 });
      return;
    }

    promptAction.showDialog({
      title: '确认删除',
      message: `将删除当前筛选条件下的 ${billsToDelete.length} 条账单，删除后可在回收站恢复，确定吗？`,
      buttons: [
        {
          text: '取消',
          color: $r('app.color.text_secondary')
        },
        {
          text: '删除',
          color: $r('app.color.expense_red')
        }
      ]
    }).then((result: DialogResult) => {
      if (result.index === 1) {
        this.executeBatchDelete(billsToDelete);
      }
    }).catch(() => {});
  }

  // 批量删除：逐笔回退资产余额，再统一移入回收站
  async executeBatchDelete(billsToDelete: BillItem[]): Promise<void> {
    const idsToDelete: Set<number> = new Set(billsToDelete.map((bill: BillItem) => bill.id));
    this.bills = this.bills.filter((bill: BillItem) => !idsToDelete.has(bill.id));
    // 整批一次性回退余额，替代原先逐笔 updateAsset 的 N 次读写
    await this.applyAssetsBatch(billsToDelete, 'remove');
    await this.moveToRecycleBin(billsToDelete);
    this.saveBillsToPreferences();
    promptAction.showToast({
      message: `已移入回收站 ${billsToDelete.length} 条账单`,
      duration: 1500
    });
  }

  // ---------- 打开弹窗 ----------
  openAddDialog() {
    // 半模态弹层：内容随 sheet 显隐构建/销毁，分类列表每次打开都是当前账本的
    this.actionSheetType = 'add';
    this.showActionSheet = true;
  }

  openEditDialog(bill: BillItem) {
    // 半模态弹层：与记一笔一致，内容随 sheet 显隐构建/销毁
    this.editSheetBill = bill;
    this.showEditSheet = true;
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
    // 半模态弹层：账单列表随 sheet 构建时传入，始终为最新数据
    this.actionSheetType = 'search';
    this.showActionSheet = true;
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
          this.saveBudget(amount).then((): void => {
            this.loadReminderData();  // 预算变更立即刷新提醒角标
          });
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
    const palette = getChartPalette(this.currentColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
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
      ctx.fillStyle = palette.textLight;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText('该时段暂无支出', centerX, centerY);
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
      ctx.strokeStyle = palette.cardBg;
      ctx.lineWidth = 2;
      ctx.stroke();
      startAngle += sliceAngle;
    }
  }

  drawTrendChart() {
    if (!this.trendCanvasCtx) return;
    const ctx = this.trendCanvasCtx;
    const palette = getChartPalette(this.currentColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    const data = this.getStatTrendPoints();

    let canvasWidth = this.trendCanvasWidth;
    if (canvasWidth <= 0) {
      canvasWidth = 400;
    }
    const canvasHeight = 200;

    const hasData = data.some(d => d.amount > 0);
    if (!hasData) {
      ctx.clearRect(0, 0, canvasWidth, canvasHeight);
      ctx.font = '24px sans-serif';
      ctx.fillStyle = palette.textLight;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText('该时段暂无支出数据', canvasWidth / 2, canvasHeight / 2);
      return;
    }

    const maxAmount = Math.max(...data.map(d => d.amount), 1);
    const padding: Padding = { top: 20, bottom: 36, left: 32, right: 10 };
    const chartWidth = canvasWidth - padding.left - padding.right;
    const chartHeight = canvasHeight - padding.top - padding.bottom;

    const getX = (index: number) => padding.left + (index / (data.length - 1 || 1)) * chartWidth;
    const getY = (amount: number) => padding.top + chartHeight - (amount / maxAmount) * chartHeight;

    ctx.clearRect(0, 0, canvasWidth, canvasHeight);

    ctx.strokeStyle = palette.grid;
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
      ctx.fillStyle = palette.text;
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
      ctx.fillStyle = palette.cardBg;
      ctx.fill();
      ctx.strokeStyle = '#FF6B6B';
      ctx.lineWidth = 2.5;
      ctx.stroke();
    }

    const labelStep = data.length <= 8 ? 1 : Math.max(3, Math.floor(data.length / 6));
    for (let i = 0; i < data.length; i += labelStep) {
      const x = getX(i);
      ctx.fillStyle = palette.text;
      ctx.font = 'bold 26px sans-serif';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'top';
      ctx.fillText(data[i].label, x, chartHeight + padding.top + 8);
    }
  }

  // 绘制年度支出趋势图（柱状图）
  drawYearlyTrendChart() {
    if (!this.yearCanvasCtx) return;
    const ctx = this.yearCanvasCtx;
    const palette = getChartPalette(this.currentColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    const monthlyData = this.getYearlyExpenseData();
    const maxAmount = Math.max(...monthlyData, 1);

    const padding: Padding = { top: 20, bottom: 36, left: 32, right: 10 };
    const canvasWidth = this.yearCanvasWidth || 400;
    const canvasHeight = 200;
    const chartWidth = canvasWidth - padding.left - padding.right;
    const chartHeight = canvasHeight - padding.top - padding.bottom;

    ctx.clearRect(0, 0, canvasWidth, canvasHeight);

    ctx.strokeStyle = palette.grid;
    ctx.lineWidth = 1.5;
    for (let i = 0; i <= 4; i++) {
      const y = padding.top + (i / 4) * chartHeight;
      ctx.beginPath();
      ctx.moveTo(padding.left, y);
      ctx.lineTo(canvasWidth - padding.right, y);
      ctx.stroke();
    }

    ctx.fillStyle = palette.text;
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

      ctx.fillStyle = monthlyData[i] > 0 ? '#FF6B6B' : palette.track;
      ctx.beginPath();
      ctx.roundRect(x, y, barWidth, barHeight, [2, 2, 0, 0]);
      ctx.fill();

      ctx.fillStyle = palette.text;
      ctx.font = 'bold 26px sans-serif';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'top';
      const labelX = padding.left + (i / 12) * chartWidth + chartWidth / 12 / 2;
      ctx.fillText((i + 1) + '月', labelX, padding.top + chartHeight + 8);
    }
  }

  updateChartIfNeeded() {
    if (this.currentTabIndex === 1) {
      this.updateStatSummary();
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
          .backgroundColor(this.getBudgetStatus().usedPercentForColor > 100 ? $r('app.color.expense_red') : this.getBudgetStatus().usedPercentForColor > 80 ? $r('app.color.budget_orange') : $r('app.color.success_green'))
          .borderRadius(4)
          .animation({ curve: AnimationConfig.SPRING_SOFT })
        }
        .width('100%')
        .height(8)
        .backgroundColor($r('app.color.border_color'))
        .borderRadius(4)
        .alignItems(HorizontalAlign.Start)
        .margin({ bottom: 6 })

        Row() {
          Text(this.getBudgetStatus().isOverBudget ? `超支 ¥${(this.getBudgetStatus().monthlyExpense - this.budget).toFixed(0)}` : `剩余 ¥${this.getBudgetStatus().remaining.toFixed(0)}`)
            .fontSize(14)
            .fontColor(this.getBudgetStatus().isOverBudget ? $r('app.color.expense_red') : $r('app.color.success_green'))
          Blank()
          Text(this.getBudgetStatus().usedPercentForColor > 100 ? '已超支' : `已使用 ${this.getBudgetStatus().usedPercentForColor.toFixed(0)}%`)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')

        Row() {
          Text('每日支出建议')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
          Blank()
          if (this.getBudgetStatus().isOverBudget) {
            Text('本月已超支，建议减少非必要开支')
              .fontSize(13)
              .fontColor($r('app.color.expense_red'))
          } else if (this.getBudgetStatus().remainingDays > 0) {
            Text(`¥${this.getBudgetStatus().dailySuggestion.toFixed(2)} / 天 · 还剩 ${this.getBudgetStatus().remainingDays} 天`)
              .fontSize(13)
              .fontColor($r('app.color.budget_orange'))
          } else {
            Text('仅对当月预算提供建议')
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
          }
        }
        .width('100%')
        .padding({ top: 8, bottom: 8, left: 10, right: 10 })
        .borderRadius(10)
        .backgroundColor($r('app.color.border_color'))
        .margin({ top: 10 })
      }
      .width('100%')
      .padding(16)
      .backgroundColor($r('app.color.card_bg'))
      .borderRadius({ topLeft: 18, topRight: 15, bottomLeft: 17, bottomRight: 19 })
      .shadow({ radius: 0, color: $r('app.color.ink_shadow'), offsetX: 3, offsetY: 3 }).border({ width: 1, color: $r('app.color.ink_line') })
      .margin({ bottom: 16 })
      .scale({ x: this.pressedCard === 'budget' ? 0.96 : 1, y: this.pressedCard === 'budget' ? 0.96 : 1 })
      .animation({ curve: AnimationConfig.SPRING })
      .translate({ x: this.homeContentShiftX })
      .opacity(this.homeContentAlpha)
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
            .fontColor(this.brandMain)
        }
        .width('100%')
      }
      .width('100%')
      .padding(16)
      .backgroundColor($r('app.color.card_bg'))
      .borderRadius({ topLeft: 18, topRight: 15, bottomLeft: 17, bottomRight: 19 })
      .shadow({ radius: 0, color: $r('app.color.ink_shadow'), offsetX: 3, offsetY: 3 }).border({ width: 1, color: $r('app.color.ink_line') })
      .margin({ bottom: 16 })
      .scale({ x: this.pressedCard === 'budget' ? 0.96 : 1, y: this.pressedCard === 'budget' ? 0.96 : 1 })
      .animation({ curve: AnimationConfig.SPRING })
      .translate({ x: this.homeContentShiftX })
      .opacity(this.homeContentAlpha)
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
    this.loadUserProgress();  // 从成就页返回时刷新等级/经验显示
    this.loadReminderData();  // 回到页面时刷新提醒（财富页可能改了信用账户/存钱目标）
    this.consumePrivacyRelockSignal();  // 应用回到前台时重新锁定（隐私锁）

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

    // 周期账单规则变更信号（来自周期账单管理页）
    const recurringRefreshFlag = AppStorage.get<number>('shouldRefreshRecurring') || 0;
    if (recurringRefreshFlag !== this.lastRecurringRefreshFlag) {
      this.lastRecurringRefreshFlag = recurringRefreshFlag;
      console.info('📌 检测到周期账单规则变更，重新生成');
      this.reloadRecurringBills();
    } else {
      // 兜底：只在「跨天后的第一次回前台」补生成。
      // 原先这里无条件每次页面显露都跑一遍，会把 366 天 × 全部规则重扫一次；
      // 且 loadRecurringBills() 的 Promise 没有被等待，
      // 规则刚改完就立刻返回首页时拿到的是旧规则
      const d: Date = new Date();
      const todayKey: string = `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`;
      if (todayKey !== this.lastRecurringCheckDay) {
        this.reloadRecurringBills();
      }
    }
  }

  // ---------- Tab 构建器 ----------
  @Builder
  TabBuilder(title: string, index: number, icon: Resource) {
    Column() {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor(this.currentTabIndex === index ? [this.brandMain] : [$r('app.color.text_secondary')])
        .scale({
          x: this.currentTabIndex === index ? this.tabIconPop : 1,
          y: this.currentTabIndex === index ? this.tabIconPop : 1
        })
      Text(title)
        .fontSize(12)
        .fontColor(this.currentTabIndex === index ? this.brandMain : $r('app.color.text_secondary'))
        .fontWeight(this.currentTabIndex === index ? 600 : FontWeight.Normal)
        .margin({ top: 2 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .scale({
      x: this.pressedTabIdx === index ? 0.88 : 1,
      y: this.pressedTabIdx === index ? 0.88 : 1
    })
    .animation({ curve: MotionCurves.PRESS })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressedTabIdx = index;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressedTabIdx = -1;
      }
    })
  }

  // 统计页右上角"报告"按钮的弹出菜单：选择每周/月度/年度报告
  @Builder
  reportMenuBuilder() {
    Menu() {
      MenuItem({ content: '每周报告' })
        .onClick(() => {
          router.pushUrl({ url: 'pages/WeeklyReportPage' });
        })
      MenuItem({ content: '月度报告' })
        .onClick(() => {
          router.pushUrl({ url: 'pages/MonthlyReportPage' });
        })
      MenuItem({ content: '年度报告' })
        .onClick(() => {
          router.pushUrl({ url: 'pages/AnnualReportPage' });
        })
    }
  }

  // ---------- 账本切换入口 ----------
  @Builder
  LedgerChip() {
    Row() {
      SymbolGlyph(getLedgerIconResource(this.getCurrentLedger().icon))
        .fontSize(12)
        .fontColor([this.brandMain])
      Text(this.getCurrentLedger().name)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.brandMain)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: 72 })
        .margin({ left: 3 })
      SymbolGlyph($r('sys.symbol.chevron_down'))
        .fontSize(10)
        .fontColor([this.brandMain])
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
                  .fontColor([this.brandMain])
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
          .fontColor(this.brandMain)
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

  // ---------- 记一笔 / 搜索账单半模态弹层（共用，按类型切换内容） ----------
  @Builder
  ActionSheetBuilder() {
    if (this.actionSheetType === 'add') {
      AddBillSheetContent({
        categories: this.getCurrentLedgerCategories(),
        onAddBill: (name: string, amount: number, type: '收入' | '支出', date: Date, category: string, source: string, tags: string[], photos: string[]) => {
          this.addBill(name, amount, type, date, category, source, tags, photos);
        },
        onClose: () => {
          this.showActionSheet = false;
        }
      })
    } else {
      SearchBillSheetContent({
        bills: this.bills,
        onSelectBill: (bill: BillItem) => {
          const d = new Date(bill.date);
          this.currentYear = d.getFullYear();
          this.currentMonth = d.getMonth() + 1;
          this.openDetailDialog(bill);
        },
        onClose: () => {
          this.showActionSheet = false;
        }
      })
    }
  }

  // ---------- 编辑账单半模态弹层（与记一笔一致的弹出效果） ----------
  @Builder
  EditSheetBuilder() {
    if (this.editSheetBill !== null) {
      EditBillSheetContent({
        billId: this.editSheetBill.id,
        paramName: this.editSheetBill.name,
        paramAmount: this.editSheetBill.amount.toString(),
        paramType: this.editSheetBill.type,
        paramDate: new Date(this.editSheetBill.date),
        paramCategory: this.editSheetBill.category || '其他',
        paramSource: this.editSheetBill.source || '现金',
        paramTags: this.editSheetBill.tags || [],
        paramPhotoUris: this.editSheetBill.photoUris || [],
        categories: this.getCurrentLedgerCategories(),
        onUpdateBill: (id: number, name: string, amount: number, type: '收入' | '支出', date: Date, category: string, source: string, tags: string[], photos: string[]) => {
          this.updateBill(id, name, amount, type, date, category, source, tags, photos);
        },
        onClose: () => {
          this.showEditSheet = false;
        }
      })
    }
  }

  // ---------- 隐私锁锁屏构建器 ----------
  @Builder
  LockKeyBuilder(key: string) {
    Text(key)
      .fontSize(26)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.pressedLockKey === key ? $r('app.color.text_white') : $r('app.color.text_primary'))
      .width(72)
      .height(72)
      .textAlign(TextAlign.Center)
      .backgroundColor(this.pressedLockKey === key ? this.brandMain : $r('app.color.card_bg'))
      .borderRadius(36)
      .scale({
        x: this.pressedLockKey === key ? 0.88 : 1,
        y: this.pressedLockKey === key ? 0.88 : 1
      })
      .animation({ duration: 120, curve: Curve.Friction })
      .onTouch((event: TouchEvent) => {
        if (this.lockoutRemainSec > 0) {
          return;
        }
        if (event.type === TouchType.Down) {
          this.pressedLockKey = key;
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.pressedLockKey = '';
          if (event.type === TouchType.Up) {
            this.onLockKeyPress(key);
          }
        }
      })
  }

  @Builder
  LockKeyRow(keys: string[]) {
    Row({ space: 24 }) {
      ForEach(keys, (k: string) => {
        this.LockKeyBuilder(k)
      }, (k: string) => k)
    }
  }

  @Builder
  PrivacyLockOverlayBuilder() {
    Column() {
      if (this.lockBackupMode) {
        // ---------- 备用密码解锁模式 ----------
        Column() {
          Blank()

          SymbolGlyph($r('sys.symbol.key'))
            .fontSize(48)
            .fontColor([this.brandMain])
            .margin({ bottom: 14 })
            .transition(TransitionEffect.OPACITY
              .combine(TransitionEffect.scale({ x: 0.6, y: 0.6 }))
              .animation({ duration: 300, curve: AnimationConfig.SPRING }))

          Text('备用密码解锁')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))

          if (this.lockHintText.length > 0) {
            Text(`提示：${this.lockHintText}`)
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .padding({ left: 14, right: 14, top: 8, bottom: 8 })
              .backgroundColor($r('app.color.card_bg'))
              .borderRadius(14)
              .margin({ top: 14 })
          } else {
            Text('请输入设置时填写的备用密码')
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 14 })
          }

          TextInput({ placeholder: '请输入备用密码', text: this.lockBackupInput })
            .type(InputType.Normal)
            .fontColor($r('app.color.text_primary'))
            .width('78%')
            .height(48)
            .fontSize(16)
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(12)
            .border({ width: 1, color: $r('app.color.border_color') })
            .padding({ left: 16, right: 16 })
            .margin({ top: 24 })
            .enabled(this.lockoutRemainSec === 0)
            .onChange((val: string) => {
              this.lockBackupInput = val;
              this.lockBackupErrorText = '';
            })
            .onSubmit(() => {
              this.tryBackupUnlock();
            })

          if (this.lockoutRemainSec > 0) {
            Text(`尝试次数过多，${this.lockoutRemainSec} 秒后重试`)
              .fontSize(13)
              .fontColor($r('app.color.expense_red'))
              .margin({ top: 16 })
          } else if (this.lockBackupErrorText.length > 0) {
            Text(this.lockBackupErrorText)
              .fontSize(13)
              .fontColor($r('app.color.expense_red'))
              .margin({ top: 16 })
              .transition(TransitionEffect.OPACITY.animation({ duration: 150 }))
          }

          Button('解锁')
            .width('78%')
            .height(44)
            .fontSize(16)
            .backgroundColor(this.brandMain)
            .fontColor($r('app.color.text_white'))
            .borderRadius(22)
            .margin({ top: 28 })
            .opacity(this.lockoutRemainSec > 0 ? 0.4 : 1)
            .onClick(() => {
              this.tryBackupUnlock();
            })

          Blank()

          Row({ space: 28 }) {
            Text('返回数字密码')
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .onClick(() => {
                this.lockBackupMode = false;
                this.lockBackupInput = '';
                this.lockBackupErrorText = '';
              })
            Text('清除数据')
              .fontSize(13)
              .fontColor($r('app.color.expense_red'))
              .onClick(() => {
                this.clearAllDataAndResetLock();
              })
          }
          .margin({ bottom: 28 })
        }
        .width('100%')
        .height('100%')
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.translate({ x: 60 }))
          .animation({ duration: 300, curve: AnimationConfig.SPRING_SOFT }))
      } else {
        // ---------- 数字密码解锁模式 ----------
        Column() {
          Blank()

          SymbolGlyph($r('sys.symbol.lock'))
            .fontSize(48)
            .fontColor([this.brandMain])
            .margin({ bottom: 14 })
            .transition(TransitionEffect.OPACITY
              .combine(TransitionEffect.scale({ x: 0.6, y: 0.6 }))
              .animation({ duration: 300, curve: AnimationConfig.SPRING }))

          Text('乌鸡记账')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .transition(TransitionEffect.OPACITY
              .combine(TransitionEffect.translate({ y: 14 }))
              .animation({ duration: 320, curve: AnimationConfig.SPRING_SOFT }))

          if (this.lockUnlockSuccess) {
            // 解锁成功：绿色对勾替换密码点
            Row({ space: 16 }) {
              Column() {
                SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                  .fontSize(52)
                  .fontColor([$r('app.color.success_green')])
              }
              .justifyContent(FlexAlign.Center)
            }
            .height(52)
            .margin({ top: 28 })
            .transition(TransitionEffect.OPACITY
              .combine(TransitionEffect.scale({ x: 0.4, y: 0.4 }))
              .animation({ duration: 280, curve: AnimationConfig.SPRING }))
          } else {
            Text(this.lockoutRemainSec > 0 ? `尝试次数过多，${this.lockoutRemainSec} 秒后重试` : '输入密码解锁')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 6 })
              .transition(TransitionEffect.OPACITY
                .combine(TransitionEffect.translate({ y: 10 }))
                .animation({ duration: 320, curve: AnimationConfig.SPRING_SOFT }))

            Row({ space: 16 }) {
              ForEach([0, 1, 2, 3, 4, 5], (i: number) => {
                Column() {
                  if (i < this.lockInput.length) {
                    Column() {
                    }
                    .width(14)
                    .height(14)
                    .borderRadius(7)
                    .backgroundColor(this.lockDotsError ? $r('app.color.expense_red') : this.brandMain)
                    .transition(TransitionEffect.OPACITY
                      .combine(TransitionEffect.scale({ x: 0.2, y: 0.2 }))
                      .animation({ duration: 200, curve: AnimationConfig.SPRING }))
                  }
                }
                .width(20)
                .height(20)
                .borderRadius(10)
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
                .border({
                  width: 1.5,
                  color: i < this.lockInput.length
                    ? (this.lockDotsError ? $r('app.color.expense_red') : this.brandMain)
                    : $r('app.color.border_color')
                })
              }, (i: number) => i.toString() + (this.lockDotsError ? '_e' : ''))
            }
            .margin({ top: 28 })
            .translate({ x: this.lockShakeX })
          }

          if (this.lockErrorText.length > 0) {
            Text(this.lockErrorText)
              .fontSize(13)
              .fontColor($r('app.color.expense_red'))
              .margin({ top: 12 })
              .transition(TransitionEffect.OPACITY.animation({ duration: 150 }))
          }

          Column({ space: 16 }) {
            this.LockKeyRow(['1', '2', '3'])
            this.LockKeyRow(['4', '5', '6'])
            this.LockKeyRow(['7', '8', '9'])
            Row({ space: 24 }) {
              Column() {
              }
              .width(72)
              .height(72)

              this.LockKeyBuilder('0')

              Column() {
                SymbolGlyph($r('sys.symbol.delete_left_fill'))
                  .fontSize(26)
                  .fontColor([$r('app.color.text_secondary')])
              }
              .width(72)
              .height(72)
              .justifyContent(FlexAlign.Center)
              .onClick(() => {
                this.onLockKeyDelete();
              })
            }
          }
          .margin({ top: 36 })
          .opacity(this.lockoutRemainSec > 0 ? 0.4 : 1)

          Blank()

          if (this.fingerprintAvailable) {
            // 指纹解锁按钮：误关指纹弹窗后可重新发起识别
            Column() {
              SymbolGlyph($r('sys.symbol.touchid'))
                .fontSize(28)
                .fontColor([this.brandMain])
            }
            .width(56)
            .height(56)
            .borderRadius(28)
            .justifyContent(FlexAlign.Center)
            .backgroundColor($r('app.color.card_bg'))
            .border({ width: 1, color: $r('app.color.border_color') })
            .scale({
              x: this.pressedFingerprint ? 0.88 : 1,
              y: this.pressedFingerprint ? 0.88 : 1
            })
            .animation({ duration: 120, curve: Curve.Friction })
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) {
                this.pressedFingerprint = true;
              } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                this.pressedFingerprint = false;
              }
            })
            .onClick(() => {
              this.tryFingerprintUnlock();
            })
            .margin({ bottom: 18 })
            .opacity(this.lockoutRemainSec > 0 ? 0.4 : 1)
            .transition(TransitionEffect.OPACITY
              .combine(TransitionEffect.scale({ x: 0.6, y: 0.6 }))
              .animation({ duration: 260, curve: AnimationConfig.SPRING }))
          }

          Text('忘记密码')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .margin({ bottom: 28 })
            .onClick(() => {
              this.onForgotPinClick();
            })
        }
        .width('100%')
        .height('100%')
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.translate({ x: -60 }))
          .animation({ duration: 300, curve: AnimationConfig.SPRING_SOFT }))
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_main'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.scale({ x: 1.04, y: 1.04 }))
      .animation({ duration: 380, curve: AnimationConfig.SPRING_SOFT }))
  }

  // ---------- 功能项构建器 ----------
  @Builder
  FunctionItem(icon: Resource, label: string, action: () => void) {
    Column() {
      SymbolGlyph(icon)
        .fontSize(26)
        .fontColor([this.brandMain])
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
    Stack() {
      Column() {
      HdsTabs({ barPosition: this.isWideScreen ? BarPosition.Start : BarPosition.End, index: this.currentTabIndex }) {
        // ============================================
        // ========== 记账页（Tab 0） ==========
        // ============================================
        TabContent() {
          Row() {
          Column() {
            Row()
              .width('100%')
              .height(this.statusBarVp + 10)
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
              Stack({ alignContent: Alignment.TopEnd }) {
                SymbolGlyph($r('sys.symbol.bell'))
                  .fontSize(26)
                  .fontColor([$r('app.color.text_primary')])
                  .rotate({ angle: this.bellRotate, centerX: '50%', centerY: '15%' })
                  .onClick(() => { this.openReminderCenter(); })
                if (this.unreadCount > 0) {
                  Text(this.unreadCount > 99 ? '99+' : `${this.unreadCount}`)
                    .fontSize(9)
                    .fontColor($r('app.color.text_white'))
                    .backgroundColor($r('app.color.expense_red'))
                    .borderRadius(8)
                    .constraintSize({ minWidth: 14 })
                    .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                    .scale({ x: this.badgeScale, y: this.badgeScale })
                    .transition(TransitionEffect.OPACITY
                      .combine(TransitionEffect.scale({ x: 0.3, y: 0.3 }))
                      .animation({ curve: AnimationConfig.SPRING }))
                }
              }
              .width(30)
              .height(30)
              .margin({ right: 12 })
              .bindSheet($$this.showReminderSheet, this.ReminderSheetBuilder(), {
                height: SheetSize.MEDIUM,
                dragBar: true,
                showClose: true,
                backgroundColor: $r('app.color.glass_bg'),
                blurStyle: BlurStyle.COMPONENT_THICK
              })
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
                    value: '导入微信账单',
                    action: () => {
                      this.importBillsFromFile('wechat');
                    }
                  },
                  {
                    value: '导入支付宝账单',
                    action: () => {
                      this.importBillsFromFile('alipay');
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
                .fontSize(24)
                .fontWeight(FontWeight.Medium)
                .fontColor([this.brandMain])
                .onClick(() => { this.goPreviousMonth(); })
                .padding({ left: 14, right: 10, top: 12, bottom: 12 })

              Text(`${this.currentYear}年${this.currentMonth}月`)
                .fontSize(18)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)
                .textAlign(TextAlign.Center)

              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(24)
                .fontWeight(FontWeight.Medium)
                .fontColor([this.brandMain])
                .onClick(() => { this.goNextMonth(); })
                .padding({ left: 10, right: 14, top: 12, bottom: 12 })

              Blank().width(12)

              Button() {
                Image($r('sys.media.ohos_ic_public_search_filled'))
                  .width(20).height(20).fillColor(this.brandMain)
              }
              .width(34).height(34)
              .backgroundColor($r('app.color.category_btn_bg'))
              .borderColor($r('app.color.border_color')).borderWidth(1).borderRadius(17)
              .onClick(() => { this.openSearchDialog(); })

              Blank().width(14)

              Button('手动记账')
                .backgroundColor(this.brandMain)
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
            // 首页总资产暂时不展示，需要时恢复下方注释即可（当月变化卡片自动占满整行）
            Row() {
              /* Column() {
                Row() {
                  Text('我的总资产')
                    .fontSize(13)
                    .fontColor('#CCFFFFFF')
                  Image($r('sys.media.ohos_ic_public_arrow_right'))
                    .width(14)
                    .height(14)
                    .fillColor('#CCFFFFFF')
                    .margin({ left: 4 })
                }
                Text('¥' + this.totalAsset.toFixed(2))
                  .fontSize(26)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_white'))
                  .margin({ top: 2 })
              }
              .width('100%')
              .padding({ top: 16, bottom: 16, left: 16, right: 16 })
              .borderRadius(20)
              .linearGradient({
                angle: 135,
                colors: [[this.brandLight, 0], [this.brandMain, 0.55], [this.brandDeep, 1]]
              })
              .shadow({ radius: 0, color: $r('app.color.ink_shadow'), offsetX: 3, offsetY: 3 }).border({ width: 1, color: $r('app.color.ink_line') })
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

              Blank().width(12) */

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
              .padding({ top: 16, bottom: 16, left: 16, right: 16 })
              .backgroundColor($r('app.color.card_bg'))
              .borderRadius({ topLeft: 22, topRight: 19, bottomLeft: 21, bottomRight: 23 })
              .shadow({ radius: 0, color: $r('app.color.ink_shadow'), offsetX: 3, offsetY: 3 }).border({ width: 1, color: $r('app.color.ink_line') })
              .layoutWeight(1)
              .scale({ x: this.pressedCard === 'monthChange' ? 0.96 : 1, y: this.pressedCard === 'monthChange' ? 0.96 : 1 })
              .animation({ curve: AnimationConfig.SPRING })
            }
            .width('100%')
            .margin({ bottom: 16 })
            .translate({ x: this.homeContentShiftX })
            .opacity(this.homeContentAlpha)

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
                  .fontColor(this.brandMain)
                  .fontWeight(FontWeight.Medium)
                  .onClick(() => {
                    hapticTick();
                    animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
                      this.currentTabIndex = 2;
                    });
                  })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 8 })

              List() {
                ForEach(
                  [...this.getFilteredBills()].sort((a: BillItem, b: BillItem) => b.date - a.date).slice(0, 5),
                  (item: BillItem) => {
                    ListItem() {
                      Column() {
                        // ===== 第一行：分类小色点 + 名称 + 金额 =====
                        Row() {
                          // 分类小色点
                          Column()
                            .width(8)
                            .height(8)
                            .borderRadius(4)
                            .backgroundColor(getCategoryColor(item.category))
                            .margin({ right: 8 })

                          Text(item.name)
                            .fontSize(16)
                            .fontColor($r('app.color.text_primary'))
                            .layoutWeight(1)

                          if (item.refundAmount !== undefined && item.refundAmount > 0) {
                            Text('已退款 ¥' + item.refundAmount.toFixed(2))
                              .fontSize(11)
                              .fontColor($r('app.color.text_secondary'))
                              .margin({ right: 6 })
                          }

                          Text((item.type === '收入' ? '+' : '-') + item.amount.toFixed(2))
                            .fontSize(17)
                            .fontWeight(FontWeight.Medium)
                            .fontColor(item.type === '收入' ? $r('app.color.income_gold') : $r('app.color.expense_red'))
                            .margin({ right: 18 })

                          Image($r('sys.media.ohos_ic_public_edit'))
                            .width(18)
                            .height(18)
                            .fillColor(this.brandMain)
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
                                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                                .backgroundColor($r('app.color.category_btn_bg'))
                                .borderRadius(6)
                                .margin({ right: 4 })
                            }, (tag: string) => tag + '_' + item.id)
                          }
                          .width('100%')
                          .padding({ left: 32 })  // 左缩进对齐到名称位置（小色点8+间距8+卡片内边距16）
                        }
                      }
                      .width('100%')
                      .padding({ top: 14, left: 16, bottom: 14, right: 12 })
                      .backgroundColor($r('app.color.card_bg'))
                      .borderRadius({ topLeft: 14, topRight: 11, bottomLeft: 13, bottomRight: 15 })
                      .shadow({ radius: 6, color: $r('app.color.shadow_color'), offsetX: 0, offsetY: 2 })
                      .margin({ bottom: 8 })
                      .scale({ x: this.pressedBillId === item.id ? 0.96 : 1, y: this.pressedBillId === item.id ? 0.96 : 1 })
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
                // 尾部占位：滚动尽头末条内容完全露出悬浮页签栏上方（栏体贴底后视区更深）
                ListItem() {
                  Column()
                    .width('100%')
                    .height(180)
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
            .borderRadius({ topLeft: 18, topRight: 15, bottomLeft: 17, bottomRight: 19 })
            .shadow({ radius: 0, color: $r('app.color.ink_shadow'), offsetX: 3, offsetY: 3 }).border({ width: 1, color: $r('app.color.ink_line') })
            .margin({ bottom: 16 })
            .translate({ x: this.homeContentShiftX })
            .opacity(this.homeContentAlpha)
          }
            .width('100%')
            .height('100%')
            .padding({ left: 20, right: 20})
            .backgroundColor($r('app.color.bg_main'))
            .constraintSize({ maxWidth: this.isWideScreen ? 640 : '100%' })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          }
        .tabBar(this.TabBuilder('记账', 0, $r('sys.symbol.house')))

        // ============================================
        // ========== 统计页（Tab 1）==========
        // ============================================
        TabContent() {
          Row() {
          Column() {
            Row()
              .width('100%')
              .height(this.statusBarVp + 10)
              .backgroundColor($r('app.color.bg_main'))
              .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
              .flexShrink(0)

            Row() {
              Text('统计')
                .fontSize(28)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
              Blank()
              Row() {
                SymbolGlyph($r('sys.symbol.doc_plaintext'))
                  .fontSize(16)
                  .fontColor([this.brandMain])
                Text('报告')
                  .fontSize(13)
                  .fontColor(this.brandMain)
                  .margin({ left: 4 })
              }
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .backgroundColor($r('app.color.category_btn_bg'))
              .borderRadius(16)
              .bindMenu(this.reportMenuBuilder)
            }
            .width('100%')
            .margin({ top: 10, bottom: 4 })

            // 周期滑条：周 / 月 / 年 / 全部 / 范围（滑块带动画）
            Stack({ alignContent: Alignment.Start }) {
              Column()
                .width('20%')
                .height(34)
                .borderRadius(17)
                .backgroundColor(this.brandMain)
                .translate({ x: `${STAT_PERIOD_KEYS.indexOf(this.statPeriod) * 100}%` })

              Row() {
                ForEach(STAT_PERIOD_KEYS, (key: string, idx: number) => {
                  Text(STAT_PERIOD_LABELS[idx])
                    .fontSize(14)
                    .fontWeight(this.statPeriod === key ? FontWeight.Bold : FontWeight.Normal)
                    .fontColor(this.statPeriod === key ? Color.White : $r('app.color.text_secondary'))
                    .textAlign(TextAlign.Center)
                    .height(34)
                    .layoutWeight(1)
                    .onClick(() => { this.onStatPeriodTap(key); })
                }, (key: string) => key)
              }
              .width('100%')
            }
            .width('100%')
            .height(40)
            .padding(3)
            .backgroundColor($r('app.color.category_btn_bg'))
            .borderRadius(20)
            .margin({ bottom: 10 })

            // 周期导航：切换上一/下一周期；范围模式点击文字可重新选择
            Row() {
              if (this.statPeriod === 'week' || this.statPeriod === 'month' || this.statPeriod === 'year') {
                SymbolGlyph($r('sys.symbol.chevron_left'))
                  .fontSize(24)
                  .fontWeight(FontWeight.Medium)
                  .fontColor([this.brandMain])
                  .onClick(() => { this.shiftStatPeriod(-1); })
                  .padding({ left: 14, right: 10, top: 8, bottom: 8 })
              }

              Text(this.statRangeLabelText)
                .fontSize(18)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)
                .textAlign(TextAlign.Center)
                .opacity(this.statContentOpacity)
                .scale({ x: this.statContentScale, y: this.statContentScale })
                .onClick(() => {
                  if (this.statPeriod === 'range') {
                    this.pickStatRange();
                  }
                })

              if (this.statPeriod === 'week' || this.statPeriod === 'month' || this.statPeriod === 'year') {
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(24)
                  .fontWeight(FontWeight.Medium)
                  .fontColor([this.brandMain])
                  .onClick(() => { this.shiftStatPeriod(1); })
                  .padding({ left: 10, right: 14, top: 8, bottom: 8 })
              }
            }
            .width('100%')
            .margin({ bottom: 12 })



            Scroll() {
              Column() {
                // 收支统计卡
                Column() {
                  Row() {
                    Text('收支统计')
                      .fontSize(18)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_primary'))
                    Blank()
                    Text(this.statRangeLabelText)
                      .fontSize(12)
                      .fontColor($r('app.color.text_secondary'))
                  }
                  .width('100%')
                  .margin({ bottom: 14 })

                  Row() {
                    Column() {
                      Text('支出')
                        .fontSize(13)
                        .fontColor($r('app.color.text_secondary'))
                        .margin({ bottom: 4 })
                      Text('¥' + this.statSummaryExpense.toFixed(2))
                        .fontSize(20)
                        .fontWeight(FontWeight.Bold)
                        .fontColor($r('app.color.expense_red'))
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)

                    Column() {
                      Text('收入')
                        .fontSize(13)
                        .fontColor($r('app.color.text_secondary'))
                        .margin({ bottom: 4 })
                      Text('¥' + this.statSummaryIncome.toFixed(2))
                        .fontSize(20)
                        .fontWeight(FontWeight.Bold)
                        .fontColor($r('app.color.income_gold'))
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                  }
                  .width('100%')
                  .margin({ bottom: 14 })

                  Row() {
                    Column() {
                      Text('结余')
                        .fontSize(13)
                        .fontColor($r('app.color.text_secondary'))
                        .margin({ bottom: 4 })
                      Text('¥' + this.statSummaryBalance.toFixed(2))
                        .fontSize(20)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(this.statSummaryBalance >= 0 ? $r('app.color.income_gold') : $r('app.color.expense_red'))
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)

                    Column() {
                      Text('日均支出')
                        .fontSize(13)
                        .fontColor($r('app.color.text_secondary'))
                        .margin({ bottom: 4 })
                      Text('¥' + this.statSummaryAvgDaily.toFixed(2))
                        .fontSize(20)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(this.brandMain)
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                  }
                  .width('100%')
                }
                .width('100%')
                .backgroundColor($r('app.color.card_bg'))
                .borderRadius({ topLeft: 18, topRight: 15, bottomLeft: 17, bottomRight: 19 })
                .padding(16)
                .shadow({ radius: 0, color: $r('app.color.ink_shadow'), offsetX: 3, offsetY: 3 }).border({ width: 1, color: $r('app.color.ink_line') })
                .margin({ bottom: 16 })

                Column() {
                  Row() {
                    Text('支出分类')
                      .fontSize(18)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_primary'))
                    Blank()
                    Text('共 ' + this.statSummaryExpense.toFixed(0) + ' 元')
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
                    .onAreaChange((oldArea: Area, newArea: Area) => {
                      // 滚动会持续触发 onAreaChange，仅在宽度真正变化时才重绘，避免每帧全量重绘导致掉帧
                      const width = newArea.width as number;
                      if (width > 0 && Math.abs(width - this.pieCanvasWidth) > 0.5) {
                        this.pieCanvasWidth = width;
                        setTimeout(() => {
                          this.drawPieChart();
                        }, 100);
                      }
                    })
                    .margin({ bottom: 12 })

                  Divider()
                    .width('100%')
                    .height(1)
                    .color($r('app.color.border_color'))
                    .margin({ bottom: 12 })

                  Column() {
                    ForEach(this.statLegendStats, (item: ExpenseStat) => {
                      Row() {
                        Text(item.category)
                          .fontSize(14)
                          .fontColor($r('app.color.stat_text_color'))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .constraintSize({ maxWidth: 80 })

                        Column() {
                          Column()
                            .width(Math.max((item.total / this.statSummaryExpense) * 100, 2) + '%')
                            .height(20)
                            .backgroundColor(item.color)
                            .borderRadius(12)
                        }
                        .width('100%')
                        .height(20)
                        .backgroundColor($r('app.color.border_color'))
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
                .borderRadius({ topLeft: 18, topRight: 15, bottomLeft: 17, bottomRight: 19 })
                .padding(16)
                .shadow({ radius: 0, color: $r('app.color.ink_shadow'), offsetX: 3, offsetY: 3 }).border({ width: 1, color: $r('app.color.ink_line') })
                .margin({ bottom: 16 })


                Column() {
                  Row() {
                    Text('支出趋势')
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
                      // 滚动会持续触发 onAreaChange，仅在宽度真正变化时才重绘
                      const width = newArea.width as number;
                      if (width > 0 && Math.abs(width - this.trendCanvasWidth) > 0.5) {
                        this.trendCanvasWidth = width;
                        this.drawTrendChart();
                      }
                    })
                    .onClick((event: ClickEvent) => { this.handleTrendClick(event.x, event.y); })
                    .margin({ bottom: 6 })
                }
                .width('100%')
                .backgroundColor($r('app.color.card_bg'))
                .borderRadius({ topLeft: 18, topRight: 15, bottomLeft: 17, bottomRight: 19 })
                .padding(16)
                .shadow({ radius: 0, color: $r('app.color.ink_shadow'), offsetX: 3, offsetY: 3 }).border({ width: 1, color: $r('app.color.ink_line') })
                .margin({ bottom: 16 })


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
                        .fontColor(this.brandMain)
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
                        .fontColor(this.brandMain)
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
                      // 滚动会持续触发 onAreaChange，仅在宽度真正变化时才重绘
                      const width = newArea.width as number;
                      if (width > 0 && Math.abs(width - this.yearCanvasWidth) > 0.5) {
                        this.yearCanvasWidth = width;
                        this.drawYearlyTrendChart();
                      }
                    })
                    .margin({ bottom: 6 })
                }
                .width('100%')
                .backgroundColor($r('app.color.card_bg'))
                .borderRadius({ topLeft: 18, topRight: 15, bottomLeft: 17, bottomRight: 19 })
                .padding(16)
                .shadow({ radius: 0, color: $r('app.color.ink_shadow'), offsetX: 3, offsetY: 3 }).border({ width: 1, color: $r('app.color.ink_line') })
                .margin({ bottom: 16 })

                Row()
                  .width('100%')

                  .height(80)
              }
              .width('100%')
              .padding({ bottom: 0 })
              .opacity(this.statContentOpacity)
              .scale({ x: this.statContentScale, y: this.statContentScale })
            }
            .width('100%')
            .layoutWeight(1)
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
          }
          .width('100%')
          .height('100%')
          .padding({ left: 20, right: 20})
          .backgroundColor($r('app.color.bg_main'))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .constraintSize({ maxWidth: this.isWideScreen ? 640 : '100%' })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        }
        .tabBar(this.TabBuilder('统计', 1, $r('sys.symbol.signal')))

        // ============================================
        // ========== 账单页（Tab 2）==========
        // ============================================
        TabContent() {
          Row() {
          Column() {
            Row()
              .width('100%')
              .height(this.statusBarVp + 10)
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

              // 视图切换：列表 / 日历（选中底色滑动过渡）
              Row() {
                Stack({ alignContent: Alignment.Start }) {
                  Column()
                    .width(44)
                    .height(36)
                    .borderRadius(18)
                    .backgroundColor($r('app.color.category_btn_bg'))
                    .offset({ x: this.billViewMode === 'list' ? 0 : 44 })

                  Row() {
                    Row() {
                      SymbolGlyph($r('sys.symbol.list_bullet'))
                        .fontSize(18)
                        .fontWeight(FontWeight.Medium)
                        .fontColor([this.billViewMode === 'list' ?
                        this.brandMain : $r('app.color.text_secondary')])
                    }
                    .width(44)
                    .height(36)
                    .justifyContent(FlexAlign.Center)
                    .onClick(() => { this.switchBillViewMode('list'); })

                    Row() {
                      SymbolGlyph($r('sys.symbol.calendar'))
                        .fontSize(18)
                        .fontWeight(FontWeight.Medium)
                        .fontColor([this.billViewMode === 'calendar' ?
                        this.brandMain : $r('app.color.text_secondary')])
                    }
                    .width(44)
                    .height(36)
                    .justifyContent(FlexAlign.Center)
                    .onClick(() => { this.switchBillViewMode('calendar'); })
                  }
                }
              }
              .height(38)
              .borderRadius(19)
              .border({ width: 1, color: $r('app.color.border_color') })
              .backgroundColor($r('app.color.card_bg'))
              .margin({ right: 8 })

            }
            .width('100%')
            .margin({ top: 10, bottom: 12 })

            if (this.billViewMode === 'list') {
            Column() {
            // 月份切换（仅列表模式）：从标题栏移到内容区顶部，避免与日历视图切换控件冲突
            Row() {
              Row() {
                SymbolGlyph($r('sys.symbol.chevron_left'))
                  .fontSize(18)
                  .fontWeight(FontWeight.Medium)
                  .fontColor([this.brandMain])
                  .onClick(() => { this.goBillPrevMonth(); })
                  .padding({ left: 10, right: 4, top: 8, bottom: 8 })

                Text(`${this.billViewYear}年${this.billViewMonth}月`)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                  .width(84)
                  .textAlign(TextAlign.Center)
                  .onClick(() => {
                    this.monthPickerController = new CustomDialogController({
                      builder: MonthPickerDialog({
                        selectedDate: new Date(this.billViewYear, this.billViewMonth - 1, 1),
                        onConfirm: (year: number, month: number) => {
                          const delta: number = (year * 12 + month) - (this.billViewYear * 12 + this.billViewMonth);
                          this.switchBillMonth(delta, year, month);
                        }
                      }),
                      autoCancel: true,
                      alignment: DialogAlignment.Center,
                      customStyle: true,
                      maskColor: 'rgba(0, 0, 0, 0.4)'
                    });
                    this.monthPickerController.open();
                  })

                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(18)
                  .fontWeight(FontWeight.Medium)
                  .fontColor([this.brandMain])
                  .onClick(() => { this.goBillNextMonth(); })
                  .padding({ left: 4, right: 10, top: 8, bottom: 8 })
              }
              .height(38)
              .borderRadius(19)
              .border({ width: 1, color: $r('app.color.border_color') })
              .backgroundColor($r('app.color.card_bg'))
            }
            .width('100%')
            .justifyContent(FlexAlign.End)
            .margin({ bottom: 12 })

            // 标签筛选（无标签时隐藏）
            if (this.getAllTags().length > 0) {
              Scroll() {
                Row() {
                  ForEach(this.getAllTags(), (tag: string) => {
                    Text('#' + tag)
                      .fontSize(13)
                      .fontColor(this.billFilterTag === tag ? this.brandMain : $r('app.color.text_secondary'))
                      .fontWeight(this.billFilterTag === tag ? FontWeight.Bold : FontWeight.Normal)
                      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                      .borderRadius(8)
                      .backgroundColor(this.billFilterTag === tag ? $r('app.color.category_btn_bg') : Color.Transparent)
                      .onClick(() => {
                        this.billFilterTag = this.billFilterTag === tag ? '' : tag;
                      })
                      .flexShrink(0)
                  }, (tag: string) => tag)
                }
                .padding({ left: 4, right: 4 })  // Row 的 padding
              }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
              .width('100%')
              .height(40)
              .padding({ bottom: 0 })
              .translate({ x: this.billContentShiftX })
              .opacity(this.billContentAlpha)
            }

            Row()
              .width('100%')
              .height(8)

            // ===== 汇总卡片：固定时常驻顶部，未固定时作为列表首项随账单滚动 =====
            if (this.billSummaryPinned) {
              Column() {
                this.BillSummaryCard()
              }
              .width('100%')
              .translate({ x: this.billContentShiftX })
              .opacity(this.billContentAlpha)
            }

            // ===== 按日期分组的账单列表 =====
            List() {
              // 未固定时：汇总卡作为列表第一项，下滑即滚走，账单可视面积更大
              if (!this.billSummaryPinned) {
                ListItem() {
                  Column() {
                    this.BillSummaryCard()
                  }
                  .width('100%')
                }
              }
              ForEach(this.getBillDayGroups(), (group: DayBillGroup, groupIdx: number) => {
                ListItem() {
                  Column() {
                    // 卡片头：左日期 右当日收支
                    Row() {
                      Text(this.formatBillDayHeader(group.date))
                        .fontSize(13)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.text_secondary'))
                      Blank()
                      Text(this.getBillDaySummaryText(group))
                        .fontSize(13)
                        .fontColor($r('app.color.text_secondary'))
                    }
                    .width('100%')
                    .padding({ left: 16, right: 16, top: 12, bottom: 6 })

                    // 当日账单
                    ForEach(group.bills, (item: BillItem, idx: number) => {
                      Column() {
                        if (idx > 0) {
                          Divider()
                            .color($r('app.color.border_color'))
                            .margin({ left: 16, right: 12 })
                        }

                        // ===== 第一行：分类小色点 + 名称 + 金额 =====
                        Row() {
                          // 分类小色点（与首页当月账单列表样式统一）
                          Column()
                            .width(8)
                            .height(8)
                            .borderRadius(4)
                            .backgroundColor(getCategoryColor(item.category))
                            .margin({ right: 8 })

                          Text(item.name)
                            .fontSize(16)
                            .fontColor($r('app.color.text_primary'))
                            .layoutWeight(1)

                          if (item.refundAmount !== undefined && item.refundAmount > 0) {
                            Text('已退款 ¥' + item.refundAmount.toFixed(2))
                              .fontSize(11)
                              .fontColor($r('app.color.text_secondary'))
                              .margin({ right: 6 })
                          }

                          Text((item.type === '收入' ? '+' : '-') + item.amount.toFixed(2))
                            .fontSize(17)
                            .fontWeight(FontWeight.Medium)
                            .fontColor(item.type === '收入' ? $r('app.color.income_gold') : $r('app.color.expense_red'))
                            .margin({ right: 18 })

                          Image($r('sys.media.ohos_ic_public_edit'))
                            .width(18)
                            .height(18)
                            .fillColor(this.brandMain)
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

                        // ===== 第二行：标签（如果有）=====
                        if (item.tags && item.tags.length > 0) {
                          Row() {
                            ForEach(item.tags, (tag: string) => {
                              Text('#' + tag)
                                .fontSize(11)
                                .fontColor($r('app.color.text_secondary'))
                                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                                .backgroundColor($r('app.color.category_btn_bg'))
                                .borderRadius(6)
                                .margin({ right: 4 })
                            }, (tag: string) => tag + '_' + item.id)
                          }
                          .width('100%')
                          .padding({ left: 32 })  // 左缩进对齐到名称位置（小色点8+间距8+卡片内边距16）
                        }
                      }
                      .width('100%')
                      .padding({ top: 10, left: 16, bottom: 10, right: 12 })
                      .scale({ x: this.pressedBillId === item.id ? 0.96 : 1, y: this.pressedBillId === item.id ? 0.96 : 1 })
                      .animation({ curve: AnimationConfig.SPRING })
                      .onTouch((event: TouchEvent) => {
                        if (event.type === TouchType.Down) {
                          this.pressedBillId = item.id;
                        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                          this.pressedBillId = -1;
                        }
                      })
                      .onClick(() => { this.openDetailDialog(item); })
                    }, (item: BillItem) => item.id + '_' + this.refreshKey)
                  }
                  .width('100%')
                  .backgroundColor($r('app.color.card_bg'))
                  .borderRadius({ topLeft: 18, topRight: 15, bottomLeft: 17, bottomRight: 19 })
                  .shadow({ radius: 0, color: $r('app.color.ink_shadow'), offsetX: 3, offsetY: 3 }).border({ width: 1, color: $r('app.color.ink_line') })
                  .translate({
                    // 距中心越远的卡片偏移越大 → 卡片间距随滚动弹性伸缩
                    y: Math.max(-4, Math.min(4, groupIdx - this.billListCenterIdx)) * this.billGapStretch
                  })
                  .animation({ curve: AnimationConfig.SPRING })
                  .margin({ bottom: 12 })
                }
                .transition(this.itemTransitionEffect)
              }, (group: DayBillGroup) => group.date.toString() + '_' + this.refreshKey + '_' +
                this.billFilterCategory + '_' + this.billFilterTag)

              // 尾部占位：滚动尽头末卡完全露出悬浮页签栏上方（栏体贴底后视区更深）
              ListItem() {
                Column()
                  .width('100%')
                  .height(190)
              }
              .backgroundColor(Color.Transparent)
            }
            .width('100%')
            .height('100%')
            .layoutWeight(1)
            .backgroundColor(Color.Transparent)
            .scrollBar(BarState.Off)
            .margin({ bottom: 16 })
            .translate({ x: this.billContentShiftX })
            .opacity(this.billContentAlpha)
            .onScrollIndex((first: number, last: number, center: number) => {
              this.billListCenterIdx = center;
            })
            .onDidScroll((scrollOffset: number, scrollState: ScrollState) => {
              // 滚动速度越大间距拉伸越明显，限制最大幅度
              const target: number = Math.max(-6, Math.min(6, scrollOffset * 0.45));
              this.billGapStretch = this.billGapStretch * 0.5 + target * 0.5;
            })
            .onScrollStop(() => {
              // 停止滚动时间距弹回原状
              this.billGapStretch = 0;
            })
            }
            .width('100%')
            .layoutWeight(1)
            .transition(TransitionEffect.OPACITY
              .combine(TransitionEffect.scale({ x: 0.96, y: 0.96 }))
              .animation({ curve: AnimationConfig.SPRING_SOFT }))
            } else {
              // 日历形式
              Column() {
                CalendarTab({ bills: $ledgerBills, embedded: true })
              }
              .width('100%')
              .layoutWeight(1)
              .transition(TransitionEffect.OPACITY
                .combine(TransitionEffect.scale({ x: 0.96, y: 0.96 }))
                .animation({ curve: AnimationConfig.SPRING_SOFT }))
            }
          }
          .width('100%')
          .height('100%')
          .padding({ left: 20, right: 20 })
          .backgroundColor($r('app.color.bg_main'))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .constraintSize({ maxWidth: this.isWideScreen ? 640 : '100%' })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        }
        .tabBar(this.TabBuilder('账单', 2, $r('sys.symbol.doc_text')))


        // ============================================
        // ========== 财富页面（Tab 3） ==========
        // ============================================
        TabContent() {
          Row() {
            WealthTab({
              totalAsset: this.totalAsset,
              onAssetsChanged: () => { this.loadTotalAsset(); },
              onWealthDataChanged: () => { this.loadReminderData(); }
            })
              .constraintSize({ maxWidth: this.isWideScreen ? 640 : '100%' })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        }
        .tabBar(this.TabBuilder('财富', 3, $r('sys.symbol.wallet')))


        // ============================================
        // ========== 我的页面（Tab 4） ==========
        // ============================================
        TabContent() {
          Row() {
          Column() {
            // 状态栏占位
            Row()
              .width('100%')
              .height(this.statusBarVp + 10)
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
                  // 头像：华为账号已登录时显示账号头像/昵称首字，点击登录或退出
                  Column() {
                    if (this.huaweiAccount && this.huaweiAccount.avatarUri.length > 0) {
                      Image(this.huaweiAccount.avatarUri)
                        .width(72)
                        .height(72)
                        .borderRadius(36)
                        .objectFit(ImageFit.Cover)
                    } else {
                      Text(this.getAvatarChar())
                        .fontSize(30)
                        .fontWeight(FontWeight.Bold)
                        .fontColor($r('app.color.text_white'))
                        .textAlign(TextAlign.Center)
                    }
                  }
                  .width(72)
                  .height(72)
                  .borderRadius(36)
                  .linearGradient({
                    angle: 135,
                    colors: [[this.brandLight, 0], [this.brandMain, 0.6], [this.brandDeep, 1]]
                  })
                  .shadow({ radius: 0, color: $r('app.color.ink_shadow'), offsetX: 3, offsetY: 3 }).border({ width: 1, color: $r('app.color.ink_line') })
                  .justifyContent(FlexAlign.Center)
                  .margin({ right: 16 })
                  .onClick(() => {
                    if (this.huaweiAccount) {
                      this.onHuaweiAccountRowClick();
                    } else if (CLOUD_FEATURES_ENABLED) {
                      this.startHuaweiLogin();
                    }
                  })

                  // 用户信息
                  Column() {
                    Row() {
                      Text(this.huaweiAccount && this.huaweiAccount.nickname.length > 0
                        ? this.huaweiAccount.nickname : '乌鸡用户')
                        .fontSize(20)
                        .fontWeight(FontWeight.Bold)
                        .fontColor($r('app.color.text_primary'))
                      Text('Lv.' + this.getUserLevel())
                        .fontSize(12)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.text_white'))
                        .backgroundColor(this.isUserMaxLevel() ?
                        $r('app.color.income_gold') : this.brandMain)
                        .borderRadius(10)
                        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                        .margin({ left: 8 })
                    }

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

                    // 成就信息：经验值 + 宝藏件数
                    Row({ space: 4 }) {
                      HandIcon({ name: 'chick', iconSize: 14 })
                      Text(`${this.userXp} XP  ·  小鸡的宝藏 ${this.unlockedCount} 件`)
                        .fontSize(12)
                        .fontColor($r('app.color.text_secondary'))
                    }
                    .margin({ top: 8 })

                    // 华为账号未登录时的登录提示（调试签名不支持账号登录，隐藏）
                    if (!this.huaweiAccount && CLOUD_FEATURES_ENABLED) {
                      Text('点击头像登录华为账号 >')
                        .fontSize(12)
                        .fontColor(this.brandMain)
                        .margin({ top: 6 })
                    }

                    // 升级进度条
                    Progress({
                      value: this.userProgressDisplay,
                      total: 100,
                      type: ProgressType.Linear
                    })
                      .width('100%')
                      .height(6)
                      .borderRadius(3)
                      .color(this.isUserMaxLevel() ?
                      $r('app.color.income_gold') : this.brandMain)
                      .margin({ top: 6 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  // 进入成就页提示箭头
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(18)
                    .fontColor([$r('app.color.text_secondary')])
                    .margin({ left: 4 })
                }
                .width('100%')
                .padding({
                  top: 16,
                  bottom: 16,
                  left: 20,
                  right: 20
                })
                .backgroundColor($r('app.color.card_bg'))
                .borderRadius({ topLeft: 18, topRight: 15, bottomLeft: 17, bottomRight: 19 })
                .shadow({ radius: 0, color: $r('app.color.ink_shadow'), offsetX: 3, offsetY: 3 }).border({ width: 1, color: $r('app.color.ink_line') })
                .margin({ top: 12,bottom: 16 })
                .onClick(() => {
                  router.pushUrl({ url: 'pages/AchievementPage' });
                })

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
                  .borderRadius({ topLeft: 18, topRight: 15, bottomLeft: 17, bottomRight: 19 })
                  .shadow({
                    radius: 4,
                    color: $r('app.color.shadow_color'),
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
                  .borderRadius({ topLeft: 18, topRight: 15, bottomLeft: 17, bottomRight: 19 })
                  .shadow({
                    radius: 4,
                    color: $r('app.color.shadow_color'),
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
                  .borderRadius({ topLeft: 18, topRight: 15, bottomLeft: 17, bottomRight: 19 })
                  .shadow({
                    radius: 4,
                    color: $r('app.color.shadow_color'),
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
                      this.chooseImportSource();
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
                .borderRadius({ topLeft: 18, topRight: 15, bottomLeft: 17, bottomRight: 19 })
                .shadow({ radius: 0, color: $r('app.color.ink_shadow'), offsetX: 3, offsetY: 3 }).border({ width: 1, color: $r('app.color.ink_line') })
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

                  // 新手引导：重新体验引导介绍页（设置列表第一项）
                  Row() {
                    SymbolGlyph($r('sys.symbol.lightbulb'))
                      .fontSize(20)
                      .fontColor([$r('app.color.text_secondary')])
                      .margin({ right: 8 })
                    Text('新手引导')
                      .fontSize(16)
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
                    hapticTick();
                    router.pushUrl({ url: 'pages/GuideIntroPage' });
                  })

                  // 账本管理
                  Row() {
                    SymbolGlyph($r('sys.symbol.book'))
                      .fontSize(20)
                      .fontColor([$r('app.color.text_secondary')])
                      .margin({ right: 8 })
                    Text('账本管理')
                      .fontSize(16)
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

                  // 周期账单
                  Row() {
                    SymbolGlyph($r('sys.symbol.calendar_badge_clock'))
                      .fontSize(20)
                      .fontColor([$r('app.color.text_secondary')])
                      .margin({ right: 8 })
                    Text('周期账单')
                      .fontSize(16)
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
                    router.pushUrl({ url: 'pages/RecurringManagePage' });
                  })

                  // 回收站
                  Row() {
                    SymbolGlyph($r('sys.symbol.trash'))
                      .fontSize(20)
                      .fontColor([$r('app.color.text_secondary')])
                      .margin({ right: 8 })
                    Text('回收站')
                      .fontSize(16)
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
                    router.pushUrl({ url: 'pages/RecycleBinPage' });
                  })

                  // 隐私锁
                  Row() {
                    SymbolGlyph($r('sys.symbol.lock'))
                      .fontSize(20)
                      .fontColor([$r('app.color.text_secondary')])
                      .margin({ right: 8 })
                    Text('隐私锁')
                      .fontSize(16)
                      .fontColor($r('app.color.text_primary'))
                      .layoutWeight(1)
                    Text(this.privacyLockEnabled ? '已开启' : '未开启')
                      .fontSize(14)
                      .fontColor($r('app.color.text_secondary'))
                      .margin({ right: 8 })
                    SymbolGlyph($r('sys.symbol.chevron_right'))
                      .fontSize(16)
                      .fontColor([$r('app.color.text_secondary')])
                  }
                  .width('100%')
                  .padding({ top: 14, bottom: 14 })
                  .border({ width: { bottom: 1 }, color: $r('app.color.border_color') })
                  .onClick(() => {
                    this.onPrivacyLockRowClick();
                  })

                  // 指纹解锁（隐私锁开启且设备有指纹模块时才显示，开启前需先验证指纹）
                  if (this.privacyLockEnabled && this.fingerprintSupported) {
                    Row() {
                      SymbolGlyph($r('sys.symbol.touchid'))
                        .fontSize(20)
                        .fontColor([$r('app.color.text_secondary')])
                        .margin({ right: 8 })
                      Text('指纹解锁')
                        .fontSize(16)
                        .fontColor($r('app.color.text_primary'))
                        .layoutWeight(1)
                      Toggle({ type: ToggleType.Switch, isOn: this.fingerprintUnlockEnabled })
                        .onChange((isOn: boolean) => {
                          this.onFingerprintToggleChange(isOn);
                        })
                    }
                    .width('100%')
                    .padding({ top: 14, bottom: 14 })
                    .border({ width: { bottom: 1 }, color: $r('app.color.border_color') })
                  }

                  // 深色模式
                  Row() {
                    SymbolGlyph($r('sys.symbol.moon'))
                      .fontSize(20)
                      .fontColor([$r('app.color.text_secondary')])
                      .margin({ right: 8 })
                    Text('深色模式')
                      .fontSize(16)
                      .fontColor($r('app.color.text_primary'))
                      .layoutWeight(1)

                    Row() {
                      Text('浅色')
                        .fontSize(15)
                        .fontColor(this.userTheme === 'light' ? this.brandMain : $r('app.color.text_secondary'))
                        .fontWeight(this.userTheme === 'light' ? FontWeight.Medium : FontWeight.Normal)
                        .padding({ left: 12, right: 12, top: 4, bottom: 4 })
                        .borderRadius(12)
                        .backgroundColor(this.userTheme === 'light' ? $r('app.color.category_btn_bg') : Color.Transparent)
                        .onClick(() => { hapticTick(); this.switchTheme('light'); })

                      Text('深色')
                        .fontSize(15)
                        .fontColor(this.userTheme === 'dark' ? this.brandMain : $r('app.color.text_secondary'))
                        .fontWeight(this.userTheme === 'dark' ? FontWeight.Medium : FontWeight.Normal)
                        .padding({ left: 12, right: 12, top: 4, bottom: 4 })
                        .borderRadius(12)
                        .backgroundColor(this.userTheme === 'dark' ? $r('app.color.category_btn_bg') : Color.Transparent)
                        .onClick(() => { hapticTick(); this.switchTheme('dark'); })

                      Text('跟随系统')
                        .fontSize(15)
                        .fontColor(this.userTheme === 'system' ? this.brandMain : $r('app.color.text_secondary'))
                        .fontWeight(this.userTheme === 'system' ? FontWeight.Medium : FontWeight.Normal)
                        .padding({ left: 12, right: 12, top: 4, bottom: 4 })
                        .borderRadius(12)
                        .backgroundColor(this.userTheme === 'system' ? $r('app.color.category_btn_bg') : Color.Transparent)
                        .onClick(() => { hapticTick(); this.switchTheme('system'); })
                    }
                  }
                  .width('100%')
                  .padding({ top: 14, bottom: 14 })
                  .border({ width: { bottom: 1 }, color: $r('app.color.border_color') })

                  // 主题颜色
                  Row() {
                    // 当前主题色预览圆点
                    Column()
                      .width(20)
                      .height(20)
                      .borderRadius(10)
                      .backgroundColor(this.brandMain)
                      .margin({ right: 10 })
                    Text('主题颜色')
                      .fontSize(16)
                      .fontColor($r('app.color.text_primary'))
                      .layoutWeight(1)
                    Text(BRAND_THEMES[this.brandThemeIndex].name)
                      .fontSize(14)
                      .fontColor($r('app.color.text_secondary'))
                      .margin({ right: 8 })
                    SymbolGlyph($r('sys.symbol.chevron_right'))
                      .fontSize(16)
                      .fontColor([$r('app.color.text_secondary')])
                  }
                  .width('100%')
                  .padding({ top: 14, bottom: 14 })
                  .border({ width: { bottom: 1 }, color: $r('app.color.border_color') })
                  .onClick(() => {
                    this.brandThemeDialogController.open();
                  })

                  // 触感反馈
                  Column() {
                    Row() {
                      SymbolGlyph($r('sys.symbol.hand_tap'))
                        .fontSize(20)
                        .fontColor([$r('app.color.text_secondary')])
                        .margin({ right: 8 })
                      Text('触感反馈')
                        .fontSize(16)
                        .fontColor($r('app.color.text_primary'))
                        .layoutWeight(1)
                      Toggle({ type: ToggleType.Switch, isOn: this.hapticEnabled })
                        .onChange((isOn: boolean) => {
                          if (isOn === this.hapticEnabled) {
                            return;
                          }
                          this.hapticEnabled = isOn;
                          this.saveHapticEnabled(isOn);
                          if (isOn) {
                            // 开启时轻震一下，直观确认生效
                            hapticTick();
                          }
                        })
                    }
                    .width('100%')
                    .padding({ top: 14, bottom: 14 })

                    if (this.hapticEnabled) {
                      // 振动强度：滑块调节，拖动时实时震动预览
                      Column() {
                        Row() {
                          Text('振动强度')
                            .fontSize(15)
                            .fontColor($r('app.color.text_secondary'))
                            .layoutWeight(1)
                          Text(this.hapticIntensity < 40 ? '轻' : (this.hapticIntensity < 70 ? '中' : '强'))
                            .fontSize(15)
                            .fontWeight(FontWeight.Medium)
                            .fontColor(this.brandMain)
                        }
                        .width('100%')

                        Slider({
                          value: this.hapticIntensity,
                          min: 10,
                          max: 100,
                          step: 10,
                          style: SliderStyle.OutSet
                        })
                          .selectedColor(this.brandMain)
                          .trackColor($r('app.color.category_btn_bg'))
                          .blockColor(this.brandMain)
                          .width('100%')
                          .margin({ top: 2 })
                          .onChange((value: number, mode: SliderChangeMode) => {
                            const rounded: number = Math.round(value / 10) * 10;
                            if (rounded === this.hapticIntensity) {
                              return;
                            }
                            this.hapticIntensity = rounded;
                            this.saveHapticIntensity(rounded);
                            // 拖动过程中实时预览当前强度的震动
                            hapticTick();
                          })
                      }
                      .width('100%')
                      .padding({ bottom: 14 })
                    }
                  }
                  .width('100%')
                  .border({ width: { bottom: 1 }, color: $r('app.color.border_color') })

                  // 记账提醒（调试签名不支持代理提醒，隐藏）
                  if (CLOUD_FEATURES_ENABLED) {
                    Column() {
                      Row() {
                        SymbolGlyph($r('sys.symbol.bell'))
                          .fontSize(20)
                          .fontColor([$r('app.color.text_secondary')])
                          .margin({ right: 8 })
                        Text('记账提醒')
                          .fontSize(16)
                          .fontColor($r('app.color.text_primary'))
                        Blank()
                        Toggle({ type: ToggleType.Switch, isOn: this.isReminderOn })
                          .onChange((isOn: boolean) => {
                            // 发布失败后开关回弹会再次触发 onChange，此处忽略与当前状态一致的重复回调
                            if (isOn === this.isReminderOn) {
                              return;
                            }
                            this.setReminderOnAnimated(isOn);
                            this.onReminderToggle(isOn);
                          })
                      }
                      .width('100%')
                      .padding({ top: 14, bottom: 14 })
                      .border({ width: { bottom: 1 }, color: $r('app.color.border_color') })

                      if (this.isReminderOn) {
                        // 开关展开/收起时，下方设置项带过渡动画
                        Column() {
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
                              .fontColor(this.brandMain)
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
                              .fontColor(this.brandMain)
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
                        .width('100%')
                        .transition(TransitionEffect.OPACITY
                          .combine(TransitionEffect.translate({ y: -12 }))
                          .animation({ curve: AnimationConfig.SPRING }))
                      }
                    }
                    .width('100%')
                  }

                  // 关于应用
                  Row() {
                    SymbolGlyph($r('sys.symbol.info_circle'))
                      .fontSize(20)
                      .fontColor([$r('app.color.text_secondary')])
                      .margin({ right: 8 })
                    Text('关于应用')
                      .fontSize(16)
                      .fontColor($r('app.color.text_primary'))
                    Blank()
                    Text('v1.5.0')
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
                .borderRadius({ topLeft: 18, topRight: 15, bottomLeft: 17, bottomRight: 19 })
                .shadow({ radius: 0, color: $r('app.color.ink_shadow'), offsetX: 3, offsetY: 3 }).border({ width: 1, color: $r('app.color.ink_line') })
                .margin({ bottom: 16 })

                // ===== 5. 底部版本信息 =====
                Column() {
                  Text('乌鸡记账 v1.5.0 ·')
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
              // 底部留白：避开悬浮页签栏（栏高 56 + 底边距 navBarVp + 呼吸空间），
              // 版本信息自身另有 30vp 内边距，划到底部不被栏体遮挡
              .padding({ bottom: this.navBarVp + 38 })
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
          .constraintSize({ maxWidth: this.isWideScreen ? 640 : '100%' })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        }
        .tabBar(this.TabBuilder('我的', 4, $r('sys.symbol.person')))


      }

      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg_main'))
      .barOverlap(!this.isWideScreen)
      .vertical(this.isWideScreen)
      .barFloatingStyle(this.getTabBarFloatingStyle())
      .barHeight(this.isWideScreen ? '100%' : 56)
      .animationDuration(AnimationConfig.DURATION)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .barBackgroundColor(this.currentColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
        ? 'rgba(26, 26, 26, 0.6)' : 'rgba(255, 255, 255, 0.6)')
      .barBackgroundBlurStyle(BlurStyle.Thin)
      .onChange((index: number) => {
        hapticTick();
        this.currentTabIndex = index;
        // 选中页签图标Q弹弹跳
        this.tabIconPop = 1.25;
        animateTo({ curve: MotionCurves.BOUNCY }, () => {
          this.tabIconPop = 1;
        });
        if (index === 1) {
          this.updateStatSummary();
          setTimeout(() => {
            this.drawPieChart();
            this.drawTrendChart();
          }, 50);
        }
      })
      .bindSheet($$this.showActionSheet, this.ActionSheetBuilder(), {
        height: SheetSize.LARGE,
        dragBar: true,
        showClose: true,
        backgroundColor: $r('app.color.glass_bg'),
        blurStyle: BlurStyle.COMPONENT_THICK
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_main'))
    // 全屏沉浸式：状态栏避让由各 Tab 顶部占位条内部消化，背景延伸到状态栏下；
    // 底部悬浮页签栏抬到手势条上方（barBottomMargin = navBarVp），栏更高且不与小横杠重叠

      // 账本切换 / 编辑账单弹层宿主（同一节点链式绑定多个 bindSheet 时只有第一个生效，
      // 故各自挂到独立的零尺寸节点上）
      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showLedgerSheet, this.LedgerSheetBuilder(), {
          height: SheetSize.MEDIUM,
          dragBar: true,
          showClose: true,
          backgroundColor: $r('app.color.glass_bg'),
          blurStyle: BlurStyle.COMPONENT_THICK
        })

      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showEditSheet, this.EditSheetBuilder(), {
          height: SheetSize.LARGE,
          dragBar: true,
          showClose: true,
          backgroundColor: $r('app.color.glass_bg'),
          blurStyle: BlurStyle.COMPONENT_THICK
        })

      if (this.isPrivacyLocked) {
        this.PrivacyLockOverlayBuilder()
      }
    }
    .width('100%')
    .height('100%')
  }

}

// CSV 字段转义：包含逗号/引号/换行时用双引号包裹
function escapeCsvField(value: string): string {
  if (value.indexOf(',') !== -1 || value.indexOf('"') !== -1 ||
    value.indexOf('\n') !== -1 || value.indexOf('\r') !== -1) {
    return '"' + value.split('"').join('""') + '"';
  }
  return value;
}

// 导入任务 worker 用的账本摘要
interface LedgerBrief {
  id: number;
  name: string;
  categories: Array<string>;
}

// 导入任务 worker 的返回结果
interface ImportWorkerResult {
  newBills: Array<BillItem>;
  importedCount: number;
  mergedJson: string;
  refundRecordsJson: string;                  // 更新后的退款记录 JSON
  refundNettedCount: number;                  // 成功抵扣的退款笔数
  refundUnmatchedCount: number;               // 未匹配到原账单的退款笔数
  existingUpdates: Array<ExistingBillUpdate>; // 被退款抵扣的既有账单
}

// 统一的账单导入任务：文件解析、查重、分类匹配、组装、合并序列化全部在 worker 线程执行。
// 注意：@Concurrent 函数只能使用入参、局部变量和 import 的模块，
// 因此 CSV/Excel 解析、分类猜测等辅助逻辑全部以局部函数形式内联实现
@Concurrent
async function importBillsInWorker(
  fileContent: ArrayBuffer,
  format: string,
  existingBillsJson: string,
  ledgers: Array<LedgerBrief>,
  defaultCategories: Array<string>,
  currentLedgerId: number,
  defaultLedgerId: number,
  refundRecordsJson: string
): Promise<ImportWorkerResult> {
  const existingBills: Array<BillItem> = JSON.parse(existingBillsJson) as Array<BillItem>;
  let refundRecords: Array<RefundRecord> = [];
  try {
    refundRecords = JSON.parse(refundRecordsJson) as Array<RefundRecord>;
  } catch (e) {
    refundRecords = [];
  }

  // 每条账单独立归属其账本：查重与退款抵扣只针对当前账本的账单，
  // 其他账本已有的同款账单不阻止导入到当前账本
  const inCurrentLedger = (b: BillItem): boolean => {
    return (b.ledgerId !== undefined ? b.ledgerId : defaultLedgerId) === currentLedgerId;
  };
  // 按「金额|名称」建日期索引，O(1) 定位候选再做 60 秒窗口比对，
  // 替代原来每条导入账单全量扫描 this.bills 的 O(n×m) 做法
  const dateMap: Map<string, Array<number>> = new Map();
  for (let i: number = 0; i < existingBills.length; i++) {
    const bill: BillItem = existingBills[i];
    if (!inCurrentLedger(bill)) {
      continue;
    }
    const key: string = bill.amount + '|' + bill.name;
    const dates: Array<number> | undefined = dateMap.get(key);
    if (dates !== undefined) {
      dates.push(bill.date);
    } else {
      const first: Array<number> = [bill.date];
      dateMap.set(key, first);
    }
  }
  const isDuplicate = (date: number, amount: number, name: string): boolean => {
    const dates: Array<number> | undefined = dateMap.get(amount + '|' + name);
    if (dates === undefined) {
      return false;
    }
    for (let i: number = 0; i < dates.length; i++) {
      if (Math.abs(dates[i] - date) < 60000) {
        return true;
      }
    }
    return false;
  };
  // 接受的账单也记入索引，保证同一文件内部的重复行同样被跳过
  const rememberDate = (date: number, amount: number, name: string): void => {
    const key: string = amount + '|' + name;
    const dates: Array<number> | undefined = dateMap.get(key);
    if (dates !== undefined) {
      dates.push(date);
    } else {
      const first: Array<number> = [date];
      dateMap.set(key, first);
    }
  };

  const findLedgerById = (id: number): LedgerBrief | undefined => {
    for (let i: number = 0; i < ledgers.length; i++) {
      if (ledgers[i].id === id) {
        return ledgers[i];
      }
    }
    return undefined;
  };
  const categoriesOf = (ledger: LedgerBrief | undefined): Array<string> => {
    if (ledger !== undefined && ledger.categories.length > 0) {
      return ledger.categories;
    }
    return defaultCategories;
  };
  const fallbackCategory = (want: string, cats: Array<string>): string => {
    if (cats.indexOf(want) !== -1) {
      return want;
    }
    if (cats.indexOf('其他') !== -1) {
      return '其他';
    }
    if (cats.length > 0) {
      return cats[0];
    }
    return '其他';
  };
  // 根据关键词猜测账单分类（导入微信账单时使用）
  const guessCategoryLocal = (name: string, transType: string, counterparty: string): string => {
    const combined: string = (counterparty + ' ' + name).toLowerCase();
    const transLower: string = transType.toLowerCase();

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
  };

  // ===== 退款抵扣 =====
  // 文件内识别到的退款行（先抵扣本文件内的原支出，再抵扣既有账单）
  const parsedRefunds: Array<ParsedRefund> = [];
  // 导出把退款折叠进原支出行（收/支=支出但状态为退款）的行，跳过不记支出
  const foldedRefunds: Array<ParsedRefund> = [];
  // 未在文件内匹配到原账单、待抵扣既有账单的退款
  const pendingRefunds: Array<ParsedRefund> = [];
  let refundNettedCount: number = 0;
  let refundUnmatchedCount: number = 0;

  const refundKey = (r: ParsedRefund): string => {
    return r.source + '|' + (r.source === '微信' ? r.counterparty : r.product);
  };
  // 退款与账单名称匹配：微信按交易对方/商品包含，支付宝按商品说明相等或互含
  const refundMatchesBill = (r: ParsedRefund, billName: string): boolean => {
    if (r.source === '微信') {
      if (r.counterparty !== '' && billName.indexOf(r.counterparty) !== -1) {
        return true;
      }
      if (r.product !== '' && billName.indexOf(r.product) !== -1) {
        return true;
      }
      return false;
    }
    if (r.product === '' || billName === '') {
      return false;
    }
    return billName === r.product || billName.indexOf(r.product) !== -1 || r.product.indexOf(billName) !== -1;
  };
  // 退款与折叠退款行的匹配（双方都有交易对方/商品原文；订单号相同直接命中）
  const refundMatchesFolded = (r: ParsedRefund, f: ParsedRefund): boolean => {
    if (r.orderNo !== '' && f.orderNo !== '' && r.orderNo === f.orderNo) {
      return true;
    }
    if (r.counterparty !== '' && f.counterparty !== '' && r.counterparty === f.counterparty) {
      return true;
    }
    if (r.product !== '' && f.product !== '' &&
      (r.product === f.product || r.product.indexOf(f.product) !== -1 || f.product.indexOf(r.product) !== -1)) {
      return true;
    }
    return false;
  };
  // 退款与账单的订单号比对：双方都有订单号时精确判定；任一方缺失返回 -1（回退名称匹配）
  // 返回 1 = 同一订单，0 = 不同订单，-1 = 无法用订单号判定
  const refundOrderCmp = (r: ParsedRefund, orderNo: string): number => {
    if (r.orderNo === '' || orderNo === '') {
      return -1;
    }
    return r.orderNo === orderNo ? 1 : 0;
  };
  // 退款记录影响下的原账单净金额：重复导入旧文件时，原行金额需扣掉此前已抵扣的退款
  // 订单号优先匹配（清理过的名称可能不一致），其次按日期+名称匹配
  const applyRefundHistory = (date: number, amount: number, name: string, orderNo: string): number => {
    let refundedSum: number = 0;
    for (let i: number = 0; i < refundRecords.length; i++) {
      const rec: RefundRecord = refundRecords[i];
      const orderHit: boolean = orderNo !== '' && rec.orderNo !== undefined && rec.orderNo === orderNo;
      const nameHit: boolean = rec.billDate === date && rec.billName === name;
      if (orderHit || nameHit) {
        refundedSum += rec.amount;
      }
    }
    if (refundedSum <= 0) {
      return amount;
    }
    return Math.round((amount - refundedSum) * 100) / 100;
  };
  // 幂等：该退款此前导入时已抵扣过既有账单（有持久化记录），本次不再抵扣
  const refundAlreadyApplied = (r: ParsedRefund): boolean => {
    const key: string = refundKey(r);
    for (let k: number = 0; k < refundRecords.length; k++) {
      const rec: RefundRecord = refundRecords[k];
      if (rec.refundDate === r.date && Math.abs(rec.amount - r.amount) < 0.005 && rec.key === key) {
        return true;
      }
    }
    return false;
  };

  const newBills: Array<BillItem> = [];
  // 导入账单的主键必须是整数且全局唯一：
  // 原先用 `idBase + Math.random() * 1000 + 下标` 会产出浮点数 id，
  // 且随机量无法排除与既有账单撞号。这里取「当前时间 / 既有最大 id」的较大值起步，
  // 再按下标递增，既保证大于任何历史 id（回收站恢复不会冲突），也保证批次内互不重复
  let maxExistingId: number = 0;
  for (let i: number = 0; i < existingBills.length; i++) {
    if (existingBills[i].id > maxExistingId) {
      maxExistingId = existingBills[i].id;
    }
  }
  const idBase: number = Math.max(Date.now(), maxExistingId) + 1;
  let importedCount: number = 0;

  if (format !== 'wechat') {
    // CSV 文件：优先识别支付宝账单（官方导出为 GBK 编码，兼容 UTF-8），未命中时按本应用导出格式（utf-8）解析
    // 本应用导出格式：日期,类型,分类,用途,金额,账本
    // 按逗号拆分一行 CSV，支持双引号包裹的字段与转义引号（局部内联）
    const splitCsvLineLocal = (line: string): Array<string> => {
      const result: Array<string> = [];
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
    };
    const decodeWith = (encoding: string): string => {
      const dec: util.TextDecoder = util.TextDecoder.create(encoding, { ignoreBOM: true });
      return dec.decodeToString(new Uint8Array(fileContent), { stream: false });
    };
    let utf8Text: string = decodeWith('utf-8');
    if (utf8Text.length > 0 && utf8Text.charCodeAt(0) === 0xFEFF) {
      utf8Text = utf8Text.substring(1);
    }
    // 支付宝表头特征：同时含「交易时间」与「收/支」（新旧版本导出均满足，新版可能没有「交易分类」列）
    const looksLikeAlipay = (t: string): boolean => {
      return t.indexOf('交易时间') !== -1 && (t.indexOf('收/支') !== -1 || t.indexOf('收支') !== -1);
    };
    let alipayText: string = '';
    let gbkText: string = '';
    try {
      gbkText = decodeWith('gbk');
    } catch (e) {
      gbkText = '';
    }
    if (looksLikeAlipay(gbkText)) {
      alipayText = gbkText;
    } else if (looksLikeAlipay(utf8Text)) {
      alipayText = utf8Text;
    }

    if (alipayText !== '') {
      // 支付宝账单解析（参考微信导入：先定位表头行，再按表头列名取列，兼容不同导出版本的列差异）
      // 清理商品说明中疑似订单号的长数字段（如 -美团App-260916112007...）
      const cleanAlipayDesc = (desc: string): string => {
        const segs: Array<string> = desc.split('-');
        const kept: Array<string> = [];
        for (let s: number = 0; s < segs.length; s++) {
          const digits: string = segs[s].replace(/[^0-9]/g, '');
          if (digits.length >= 10) {
            continue;
          }
          kept.push(segs[s]);
        }
        return kept.join('-').trim();
      };
      const alipayRows: Array<CsvBillRow> = [];
      const lines: Array<string> = alipayText.split('\n');
      let headerFound: boolean = false;
      let timeCol: number = -1;
      let catCol: number = -1;
      let descCol: number = -1;
      let dirCol: number = -1;
      let amountCol: number = -1;
      let statusCol: number = -1;
      let merchantCol: number = -1;
      for (let li: number = 0; li < lines.length; li++) {
        const line: string = lines[li].trim();
        if (line.length === 0) {
          continue;
        }
        const fields: Array<string> = splitCsvLineLocal(line);
        for (let fi: number = 0; fi < fields.length; fi++) {
          fields[fi] = fields[fi].trim();
        }
        if (!headerFound) {
          // 表头行示例：交易时间,交易分类,交易对方,对方账号,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号,备注
          let hTime: number = -1;
          let hCat: number = -1;
          let hDesc: number = -1;
          let hDir: number = -1;
          let hAmount: number = -1;
          let hStatus: number = -1;
          let hMerchant: number = -1;
          for (let fi: number = 0; fi < fields.length; fi++) {
            const h: string = fields[fi];
            if (h.indexOf('交易时间') !== -1) {
              hTime = fi;
            } else if (h.indexOf('分类') !== -1) {
              hCat = fi;
            } else if (h.indexOf('商品') !== -1) {
              hDesc = fi;
            } else if (h.indexOf('收/支') !== -1 || h.indexOf('收支') !== -1) {
              hDir = fi;
            } else if (h.indexOf('金额') !== -1) {
              hAmount = fi;
            } else if (h.indexOf('状态') !== -1) {
              hStatus = fi;
            } else if (h.indexOf('商家订单') !== -1 || h.indexOf('商户订单') !== -1) {
              hMerchant = fi;
            }
          }
          if (hTime !== -1 && hDir !== -1 && hAmount !== -1) {
            headerFound = true;
            timeCol = hTime;
            catCol = hCat;
            descCol = hDesc;
            dirCol = hDir;
            amountCol = hAmount;
            statusCol = hStatus;
            merchantCol = hMerchant;
          }
          continue;
        }
        if (fields.length <= timeCol || fields.length <= dirCol || fields.length <= amountCol) {
          continue;
        }
        const typeStr: string = fields[dirCol];
        const catStr: string = catCol !== -1 && fields.length > catCol ? fields[catCol] : '';
        const statusStr: string = statusCol !== -1 && fields.length > statusCol ? fields[statusCol] : '';
        const isRefundRow: boolean = catStr.indexOf('退款') !== -1 || statusStr.indexOf('退款') !== -1;
        const date: Date = new Date(fields[timeCol].replace(/\//g, '-'));
        if (isNaN(date.getTime())) {
          continue;
        }
        const amount: number = parseFloat(fields[amountCol].replace(/[^0-9.]/g, ''));
        if (isNaN(amount) || amount === 0) {
          continue;
        }
        // 原支出行状态标注退款：导出把退款折叠进原行，不记支出
        if (typeStr === '支出' && statusStr.indexOf('退款') !== -1) {
          const foldedDesc: string = cleanAlipayDesc(descCol !== -1 && fields.length > descCol ? fields[descCol] : '');
          const folded: ParsedRefund = {
            date: date.getTime(),
            amount: Math.abs(amount),
            counterparty: '',
            product: foldedDesc,
            source: '支付宝',
            orderNo: merchantCol !== -1 && fields.length > merchantCol ? fields[merchantCol] : ''
          };
          foldedRefunds.push(folded);
          continue;
        }
        // 退款行（「不计收支」或「收入」但带退款标记）：收集待抵扣，不作为收入导入
        if (isRefundRow && typeStr !== '支出') {
          const refundDesc: string = cleanAlipayDesc(descCol !== -1 && fields.length > descCol ? fields[descCol] : '');
          const refund: ParsedRefund = {
            date: date.getTime(),
            amount: Math.abs(amount),
            counterparty: '',
            product: refundDesc,
            source: '支付宝',
            orderNo: merchantCol !== -1 && fields.length > merchantCol ? fields[merchantCol] : ''
          };
          parsedRefunds.push(refund);
          continue;
        }
        if (typeStr !== '收入' && typeStr !== '支出') {
          // 跳过「不计收支」等非收支流水
          continue;
        }
        if (statusStr !== '' && statusStr.indexOf('成功') === -1) {
          // 跳过交易关闭等未完成交易
          continue;
        }
        const desc: string = cleanAlipayDesc(descCol !== -1 && fields.length > descCol ? fields[descCol] : '');
        // 名称仅使用商品说明，不导入对方账号
        let name: string = desc;
        if (name === '') {
          name = '支付宝账单';
        }
        alipayRows.push({
          date: date.getTime(),
          type: typeStr === '收入' ? '收入' : '支出',
          category: catCol !== -1 && fields.length > catCol ? fields[catCol] : '',
          name: name,
          amount: Math.abs(amount),
          ledgerName: '',
          refundAmount: 0,
          orderNo: merchantCol !== -1 && fields.length > merchantCol ? fields[merchantCol] : '',
          source: '',
          tags: []
        });
      }
      // 退款抵扣：优先抵扣本文件内的原支出（保留账单记录，全额退款也保留为 0 元账单），
      // 其次确认折叠退款行，其余留待抵扣既有账单
      parsedRefunds.sort((a: ParsedRefund, b: ParsedRefund): number => a.date - b.date);
      for (let ri: number = 0; ri < parsedRefunds.length; ri++) {
        const r: ParsedRefund = parsedRefunds[ri];
        // 幂等：该退款此前已抵扣过既有账单（有记录），本次不再重复抵扣
        if (refundAlreadyApplied(r)) {
          continue;
        }
        let bestIdx: number = -1;
        // 第一优先：商家订单号相同的行（同一笔订单的退款）
        for (let i: number = 0; i < alipayRows.length; i++) {
          const row: CsvBillRow = alipayRows[i];
          if (row.type !== '支出' || row.date > r.date || row.amount + row.refundAmount + 0.005 < r.amount) {
            continue;
          }
          if (refundOrderCmp(r, row.orderNo) !== 1) {
            continue;
          }
          if (bestIdx === -1 || row.date > alipayRows[bestIdx].date) {
            bestIdx = i;
          }
        }
        // 第二优先：名称匹配（双方订单号不同则排除，避免误抵其他订单）
        if (bestIdx === -1) {
          for (let i: number = 0; i < alipayRows.length; i++) {
            const row: CsvBillRow = alipayRows[i];
            if (row.type !== '支出' || row.date > r.date || row.amount + row.refundAmount + 0.005 < r.amount) {
              continue;
            }
            if (refundOrderCmp(r, row.orderNo) === 0) {
              continue;
            }
            if (!refundMatchesBill(r, row.name)) {
              continue;
            }
            if (bestIdx === -1 || row.date > alipayRows[bestIdx].date) {
              bestIdx = i;
            }
          }
        }
        if (bestIdx !== -1) {
          const row: CsvBillRow = alipayRows[bestIdx];
          row.refundAmount = Math.round((row.refundAmount + r.amount) * 100) / 100;
          row.amount = Math.round((row.amount - r.amount) * 100) / 100;
          if (row.amount < 0) {
            row.amount = 0;
          }
          refundNettedCount++;
          continue;
        }
        let foldedHit: boolean = false;
        for (let fi: number = 0; fi < foldedRefunds.length; fi++) {
          const f: ParsedRefund = foldedRefunds[fi];
          if (f.date <= r.date && Math.abs(f.amount - r.amount) < 0.005 && refundMatchesFolded(r, f)) {
            foldedHit = true;
            break;
          }
        }
        if (foldedHit) {
          refundNettedCount++;
          continue;
        }
        pendingRefunds.push(r);
      }
      if (alipayRows.length === 0 && parsedRefunds.length === 0 && foldedRefunds.length === 0) {
        throw new Error('支付宝账单中未解析到有效交易记录（需为「收入/支出」且交易成功的记录）');
      }
      // 支付宝「交易分类」→ 应用分类的粗映射，未命中再走关键词猜测
      const mapAlipayCategory = (cat: string): string => {
        if (cat.indexOf('餐饮') !== -1 || cat.indexOf('食物') !== -1 || cat.indexOf('饮料') !== -1) {
          return '餐饮';
        }
        if (cat.indexOf('交通') !== -1 || cat.indexOf('出行') !== -1) {
          return '交通';
        }
        if (cat.indexOf('服饰') !== -1 || cat.indexOf('百货') !== -1 || cat.indexOf('日用') !== -1) {
          return '购物';
        }
        if (cat.indexOf('娱乐') !== -1 || cat.indexOf('休闲') !== -1 || cat.indexOf('文化') !== -1 ||
          cat.indexOf('住宿') !== -1 || cat.indexOf('旅游') !== -1) {
          return '娱乐';
        }
        if (cat.indexOf('医疗') !== -1 || cat.indexOf('健康') !== -1) {
          return '医疗';
        }
        if (cat.indexOf('教育') !== -1) {
          return '教育';
        }
        return '';
      };
      const currentCats: Array<string> = categoriesOf(findLedgerById(currentLedgerId));
      for (let i: number = 0; i < alipayRows.length; i++) {
        const row: CsvBillRow = alipayRows[i];
        // 重复导入旧文件时，扣掉此前已抵扣的退款再查重/入库
        const effectiveAmount: number = applyRefundHistory(row.date, row.amount, row.name, row.orderNo);
        if (effectiveAmount < 0.005 && row.refundAmount <= 0) {
          // 此前已被退款完全抵扣（账单已按 0 元入库），跳过
          continue;
        }
        const importAmount: number = effectiveAmount < 0 ? 0 : effectiveAmount;
        if (isDuplicate(row.date, importAmount, row.name)) {
          continue;
        }
        const mapped: string = mapAlipayCategory(row.category);
        const guessed: string = mapped !== '' ? mapped : guessCategoryLocal(row.name, row.category, row.name);
        // 猜测分类不在当前账本分类中时回退
        const category: string = fallbackCategory(guessed, currentCats);
        newBills.push({
          id: idBase + importedCount,
          name: row.name,
          amount: importAmount,
          type: row.type,
          date: row.date,
          category: category,
          source: '支付宝',
          ledgerId: currentLedgerId,
          refundAmount: row.refundAmount > 0 ? row.refundAmount : undefined,
          originalAmount: row.refundAmount > 0 ? Math.round((row.amount + row.refundAmount) * 100) / 100 : undefined,
          orderNo: row.orderNo !== '' ? row.orderNo : undefined
        });
        rememberDate(row.date, importAmount, row.name);
        importedCount++;
      }
    } else {
      // 本应用导出格式：日期,类型,分类,用途,金额,账本,资金来源,标签,已退款,订单号
      // 后四列为后加列，老版本导出文件只有前六列，这里按下标存在性读取以保持兼容
      const rows: Array<CsvBillRow> = [];
      const lines: Array<string> = utf8Text.split('\n');
      let headerFound: boolean = false;
      for (let i: number = 0; i < lines.length; i++) {
        const line: string = lines[i].trim();
        if (line.length === 0) {
          continue;
        }
        const fields: Array<string> = splitCsvLineLocal(line);
        if (fields[0] === '日期' && fields[1] === '类型') {
          headerFound = true;
          continue;
        }
        if (!headerFound) {
          // 未找到本应用导出表头前不接收数据行，避免其他来源的 CSV 被误按本格式解析
          continue;
        }
        if (fields.length < 5) {
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
        // 标签列允许为空；老版本文件没有这几列时统一回退到空值导入
        const tagRaw: string = fields.length > 7 ? fields[7] : '';
        const tagList: string[] = [];
        if (tagRaw.length > 0) {
          const parts: string[] = tagRaw.split(';');
          for (let ti: number = 0; ti < parts.length; ti++) {
            const one: string = parts[ti].trim();
            if (one.length > 0) {
              tagList.push(one);
            }
          }
        }
        const refundRaw: number = fields.length > 8 ? parseFloat(fields[8]) : 0;
        const row: CsvBillRow = {
          date: date.getTime(),
          type: type,
          category: fields[2],
          name: fields[3],
          amount: Math.abs(amount),
          ledgerName: fields.length > 5 ? fields[5] : '',
          refundAmount: refundRaw > 0 ? refundRaw : 0,
          orderNo: fields.length > 9 ? fields[9] : '',
          source: fields.length > 6 ? fields[6] : '',
          tags: tagList
        };
        rows.push(row);
      }
      if (rows.length === 0) {
        throw new Error('未识别到有效的账单数据，请确认选择的是支付宝账单（CSV）或微信账单（Excel）文件');
      }
      for (let i: number = 0; i < rows.length; i++) {
        const row: CsvBillRow = rows[i];
        if (isDuplicate(row.date, row.amount, row.name)) {
          continue;
        }
        // 账单独立归属账本：无论文件里记录的是哪个账本，一律导入当前账本
        const ledgerId: number = currentLedgerId;
        // 分类不在目标账本分类中时回退
        const category: string = fallbackCategory(row.category, categoriesOf(findLedgerById(ledgerId)));
        // 资金来源为空说明是老版本导出文件或外部 CSV，回退到原来的占位值
        const source: string = row.source.trim().length > 0 ? row.source : 'CSV导入';
        newBills.push({
          id: idBase + importedCount,
          name: row.name,
          amount: row.amount,
          type: row.type,
          date: row.date,
          category: category,
          source: source,
          ledgerId: ledgerId,
          tags: row.tags.length > 0 ? row.tags : undefined,
          refundAmount: row.refundAmount > 0 ? row.refundAmount : undefined,
          originalAmount: row.refundAmount > 0 ? Math.round((row.amount + row.refundAmount) * 100) / 100 : undefined,
          orderNo: row.orderNo !== '' ? row.orderNo : undefined
        });
        rememberDate(row.date, row.amount, row.name);
        importedCount++;
      }
    }
  } else {
    // 微信 Excel 账单（解析逻辑局部内联）
    const ExcelJS = await import('@archermind/exceljs');
    const workbook: ExcelJS.Workbook = new ExcelJS.Workbook();
    await workbook.xlsx.read(fileContent);
    const worksheet: ExcelJS.Worksheet | undefined = workbook.getWorksheet(1);
    const parsedData: Array<ParsedBillData> = [];
    if (worksheet) {
      const getCellValue = (row: ExcelJS.Row, col: number): string => {
        const cell: ExcelJS.Cell = row.getCell(col);
        if (!cell) return '';
        const value: string | number | Date | undefined = cell.value as string | number | Date | undefined;
        if (value === null || value === undefined) return '';
        if (value instanceof Date) {
          // ExcelJS 把日期单元格读成 UTC 时间戳，其 UTC 分量才是表格中显示的墙上时间；
          // 直接 String() 再解析会 +8 小时，晚间账单会漂移到第二天。这里取 UTC 分量重建本地时间
          const pad2 = (n: number): string => n < 10 ? '0' + n : '' + n;
          return value.getUTCFullYear() + '-' + pad2(value.getUTCMonth() + 1) + '-' + pad2(value.getUTCDate()) +
            ' ' + pad2(value.getUTCHours()) + ':' + pad2(value.getUTCMinutes()) + ':' + pad2(value.getUTCSeconds());
        }
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
      if (headerRowIndex !== -1) {
        for (let i: number = headerRowIndex + 1; i <= rowCount; i++) {
          const row: ExcelJS.Row = worksheet.getRow(i);
          const timeStr: string = getCellValue(row, 1);
          const transType: string = getCellValue(row, 2);
          const counterparty: string = getCellValue(row, 3);
          const name: string = getCellValue(row, 4);
          const typeStr: string = getCellValue(row, 5);
          const amountStr: string = getCellValue(row, 6);
          const statusStr: string = getCellValue(row, 8); // 当前状态
          const merchantNo: string = getCellValue(row, 10); // 商户单号（退款按订单匹配用）

          if (!timeStr || !amountStr) continue;

          const cleanAmountStr: string = amountStr.replace(/[^0-9.-]/g, '');
          const amount: number = parseFloat(cleanAmountStr);
          if (isNaN(amount) || amount === 0) continue;

          const rowDate: Date = new Date(timeStr);
          if (isNaN(rowDate.getTime())) continue;

          const isRefundRow: boolean = transType.indexOf('退款') !== -1 || statusStr.indexOf('退款') !== -1;
          // 原支出行状态标注退款：导出把退款折叠进原行，不记支出
          if (typeStr === '支出' && statusStr.indexOf('退款') !== -1) {
            const folded: ParsedRefund = {
              date: rowDate.getTime(),
              amount: Math.abs(amount),
              counterparty: counterparty,
              product: name,
              source: '微信',
              orderNo: merchantNo
            };
            foldedRefunds.push(folded);
            continue;
          }
          // 退款行（收/支为「/」「收入」等但带退款标记）：收集待抵扣，不单独入账
          if (isRefundRow && typeStr !== '支出') {
            const refund: ParsedRefund = {
              date: rowDate.getTime(),
              amount: Math.abs(amount),
              counterparty: counterparty,
              product: name,
              source: '微信',
              orderNo: merchantNo
            };
            parsedRefunds.push(refund);
            continue;
          }
          if (typeStr !== '收入' && typeStr !== '支出') continue;

          const item: ParsedBillData = {
            timeStr: timeStr,
            transType: transType,
            counterparty: counterparty,
            name: name,
            typeStr: typeStr,
            amount: Math.abs(amount),
            refundAmount: 0,
            orderNo: merchantNo
          };
          parsedData.push(item);
        }
      }
    }
    // 退款抵扣：优先抵扣本文件内的原支出（保留账单记录，全额退款也保留为 0 元账单），
    // 其次确认折叠退款行，其余留待抵扣既有账单
    parsedRefunds.sort((a: ParsedRefund, b: ParsedRefund): number => a.date - b.date);
    for (let ri: number = 0; ri < parsedRefunds.length; ri++) {
      const r: ParsedRefund = parsedRefunds[ri];
      // 幂等：该退款此前已抵扣过既有账单（有记录），本次不再重复抵扣
      if (refundAlreadyApplied(r)) {
        continue;
      }
      let bestIdx: number = -1;
      // 第一优先：商户单号相同的行（同一笔订单的退款）
      for (let i: number = 0; i < parsedData.length; i++) {
        const item: ParsedBillData = parsedData[i];
        if (item.typeStr !== '支出') {
          continue;
        }
        const itemDate: Date = new Date(item.timeStr);
        if (isNaN(itemDate.getTime()) || itemDate.getTime() > r.date ||
          item.amount + item.refundAmount + 0.005 < r.amount) {
          continue;
        }
        if (refundOrderCmp(r, item.orderNo) !== 1) {
          continue;
        }
        if (bestIdx === -1 || itemDate.getTime() > new Date(parsedData[bestIdx].timeStr).getTime()) {
          bestIdx = i;
        }
      }
      // 第二优先：名称匹配（双方订单号不同则排除，避免误抵其他订单）
      if (bestIdx === -1) {
        for (let i: number = 0; i < parsedData.length; i++) {
          const item: ParsedBillData = parsedData[i];
          if (item.typeStr !== '支出') {
            continue;
          }
          const itemDate: Date = new Date(item.timeStr);
          if (isNaN(itemDate.getTime()) || itemDate.getTime() > r.date ||
            item.amount + item.refundAmount + 0.005 < r.amount) {
            continue;
          }
          if (refundOrderCmp(r, item.orderNo) === 0) {
            continue;
          }
          const matched: boolean =
            (r.counterparty !== '' && item.counterparty !== '' && r.counterparty === item.counterparty) ||
            (r.product !== '' && item.name !== '' &&
              (r.product === item.name || r.product.indexOf(item.name) !== -1 || item.name.indexOf(r.product) !== -1));
          if (!matched) {
            continue;
          }
          if (bestIdx === -1 || itemDate.getTime() > new Date(parsedData[bestIdx].timeStr).getTime()) {
            bestIdx = i;
          }
        }
      }
      if (bestIdx !== -1) {
        const item: ParsedBillData = parsedData[bestIdx];
        item.refundAmount = Math.round((item.refundAmount + r.amount) * 100) / 100;
        item.amount = Math.round((item.amount - r.amount) * 100) / 100;
        if (item.amount < 0) {
          item.amount = 0;
        }
        refundNettedCount++;
        continue;
      }
      let foldedHit: boolean = false;
      for (let fi: number = 0; fi < foldedRefunds.length; fi++) {
        const f: ParsedRefund = foldedRefunds[fi];
        if (f.date <= r.date && Math.abs(f.amount - r.amount) < 0.005 && refundMatchesFolded(r, f)) {
          foldedHit = true;
          break;
        }
      }
      if (foldedHit) {
        refundNettedCount++;
        continue;
      }
      pendingRefunds.push(r);
    }
    const currentCats: Array<string> = categoriesOf(findLedgerById(currentLedgerId));
    for (let i: number = 0; i < parsedData.length; i++) {
      const item: ParsedBillData = parsedData[i];
      const date: Date = new Date(item.timeStr);
      if (isNaN(date.getTime())) {
        continue;
      }
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
      // 重复导入旧文件时，扣掉此前已抵扣的退款再查重/入库
      const effectiveAmount: number = applyRefundHistory(date.getTime(), item.amount, finalName, item.orderNo);
      if (effectiveAmount < 0.005 && item.refundAmount <= 0) {
        // 此前已被退款完全抵扣（账单已按 0 元入库），跳过
        continue;
      }
      const importAmount: number = effectiveAmount < 0 ? 0 : effectiveAmount;
      if (isDuplicate(date.getTime(), importAmount, finalName)) {
        continue;
      }
      const guessed: string = guessCategoryLocal(item.name || '', item.transType, item.counterparty || '');
      // 猜测分类不在当前账本分类中时回退
      const category: string = fallbackCategory(guessed, currentCats);
      newBills.push({
        id: idBase + importedCount,
        name: finalName,
        amount: importAmount,
        type: finalType,
        date: date.getTime(),
        category: category,
        source: '微信',
        ledgerId: currentLedgerId,
        refundAmount: item.refundAmount > 0 ? item.refundAmount : undefined,
        originalAmount: item.refundAmount > 0 ? Math.round((item.amount + item.refundAmount) * 100) / 100 : undefined,
        orderNo: item.orderNo !== '' ? item.orderNo : undefined
      });
      rememberDate(date.getTime(), effectiveAmount, finalName);
      importedCount++;
    }
  }

  // ===== 既有账单抵扣（退款不在本文件内时，抵扣此前导入的原账单） =====
  const existingUpdates: Array<ExistingBillUpdate> = [];
  const REFUND_MATCH_WINDOW_MS: number = 90 * 24 * 60 * 60 * 1000;
  for (let ri: number = 0; ri < pendingRefunds.length; ri++) {
    const r: ParsedRefund = pendingRefunds[ri];
    // 幂等：该退款此前导入时已抵扣过，跳过
    if (refundAlreadyApplied(r)) {
      continue;
    }
    // 在既有支出中找原账单：退款前 90 天内、累计退款不超原支付，订单号优先匹配，名称兜底，取最近的一笔
    let best: BillItem | undefined = undefined;
    // 第一优先：商户单号/商家订单号相同的账单（同一笔订单）
    for (let k: number = 0; k < existingBills.length; k++) {
      const b: BillItem = existingBills[k];
      if (!inCurrentLedger(b)) {
        continue;
      }
      if (b.type !== '支出') {
        continue;
      }
      if (b.date > r.date || r.date - b.date > REFUND_MATCH_WINDOW_MS) {
        continue;
      }
      const bOriginal: number = b.originalAmount !== undefined ? b.originalAmount : b.amount;
      const bRefunded: number = b.refundAmount !== undefined ? b.refundAmount : 0;
      if (bOriginal - bRefunded + 0.005 < r.amount) {
        continue;
      }
      if (refundOrderCmp(r, b.orderNo !== undefined ? b.orderNo : '') !== 1) {
        continue;
      }
      if (best === undefined || b.date > best.date || (b.date === best.date && b.amount > best.amount)) {
        best = b;
      }
    }
    // 第二优先：名称匹配（双方订单号都存在但不同则排除，避免误抵其他订单）
    if (best === undefined) {
      for (let k: number = 0; k < existingBills.length; k++) {
        const b: BillItem = existingBills[k];
        if (!inCurrentLedger(b)) {
          continue;
        }
        if (b.type !== '支出') {
          continue;
        }
        if (b.date > r.date || r.date - b.date > REFUND_MATCH_WINDOW_MS) {
          continue;
        }
        const bOriginal: number = b.originalAmount !== undefined ? b.originalAmount : b.amount;
        const bRefunded: number = b.refundAmount !== undefined ? b.refundAmount : 0;
        if (bOriginal - bRefunded + 0.005 < r.amount) {
          continue;
        }
        if (refundOrderCmp(r, b.orderNo !== undefined ? b.orderNo : '') === 0) {
          continue;
        }
        if (!refundMatchesBill(r, b.name)) {
          continue;
        }
        if (best === undefined || b.date > best.date || (b.date === best.date && b.amount > best.amount)) {
          best = b;
        }
      }
    }
    if (best === undefined) {
      refundUnmatchedCount++;
      continue;
    }
    const originalAmount: number = best.originalAmount !== undefined ? best.originalAmount : best.amount;
    const newRefundTotal: number = Math.round(((best.refundAmount !== undefined ? best.refundAmount : 0) + r.amount) * 100) / 100;
    let newAmount: number = Math.round((originalAmount - newRefundTotal) * 100) / 100;
    if (newAmount < 0) {
      newAmount = 0;
    }
    const record: RefundRecord = {
      refundDate: r.date,
      amount: r.amount,
      key: refundKey(r),
      billDate: best.date,
      billName: best.name,
      billId: best.id,
      orderNo: r.orderNo
    };
    refundRecords.push(record);
    // 同步更新查重索引中的金额键，保证重复导入时按净额查重
    const oldKey: string = best.amount + '|' + best.name;
    const oldDates: Array<number> | undefined = dateMap.get(oldKey);
    if (oldDates !== undefined) {
      const idx: number = oldDates.indexOf(best.date);
      if (idx !== -1) {
        oldDates.splice(idx, 1);
      }
      if (oldDates.length === 0) {
        dateMap.delete(oldKey);
      }
    }
    rememberDate(best.date, newAmount, best.name);
    best.amount = newAmount;
    best.refundAmount = newRefundTotal;
    best.originalAmount = originalAmount;
    const update: ExistingBillUpdate = {
      id: best.id,
      amount: newAmount,
      refundAmount: newRefundTotal,
      originalAmount: originalAmount
    };
    existingUpdates.push(update);
     refundNettedCount++;
  }

  // 合并结果的序列化也在 worker 完成（主线程不再对大数组做 JSON.stringify）
  const mergedJson: string = JSON.stringify(existingBills.concat(newBills));
  const result: ImportWorkerResult = {
    newBills: newBills,
    importedCount: importedCount,
    mergedJson: mergedJson,
    refundRecordsJson: JSON.stringify(refundRecords),
    refundNettedCount: refundNettedCount,
    refundUnmatchedCount: refundUnmatchedCount,
    existingUpdates: existingUpdates
  };
  return result;
  
}
