// pages/LedgerManagePage.ets
import dataPreferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import {
  LedgerItem,
  BillItem,
  DEFAULT_LEDGER_ID,
  LEDGER_ICON_KEYS,
  getLedgerIconResource,
  CATEGORIES,
  AnimationConfig
} from './Index';
import { CategoryManageParams } from './CategoryManagePage';
import { MotionCurves } from '../common/Motion';

// 账本可选颜色
const LEDGER_COLORS: string[] = [
  '#45B7D1', '#FF6B6B', '#4ECDC4', '#FFA94D',
  '#A29BFE', '#FD79A8', '#00B894', '#E17055',
  '#6C5CE7', '#FDCB6E'
];

// ========== 账本编辑弹窗（新建/编辑共用） ==========
@CustomDialog
struct LedgerEditDialog {
  @StorageProp('brand_main') brandMain: string = '#4E6EF2';
  controller: CustomDialogController = new CustomDialogController({
    builder: () => {}
  });
  title: string = '新建账本';
  paramName: string = '';
  paramIcon: string = 'book';
  paramColor: string = '#45B7D1';
  @State name: string = '';
  @State selectedIcon: string = 'book';
  @State selectedColor: string = '#45B7D1';
  onConfirm: (name: string, icon: string, color: string) => void = () => {};

  aboutToAppear() {
    this.name = this.paramName;
    this.selectedIcon = this.paramIcon;
    this.selectedColor = this.paramColor;
  }

  build() {
    Column() {
      Text(this.title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .alignSelf(ItemAlign.Start)
        .margin({ bottom: 16 })

      // 名称输入
      TextInput({ placeholder: '账本名称（如：日常开销、旅行基金）', text: this.name })
        .fontColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.card_bg'))
        .borderRadius(12)
        .border({ width: 1, color: $r('app.color.border_color') })
        .padding({ left: 16, right: 16 })
        .height(44)
        .fontSize(15)
        .width('100%')
        .onChange((val: string) => { this.name = val; })
        .margin({ bottom: 16 })

      Text('选择图标')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .margin({ bottom: 8 })

      // 图标选择网格
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(LEDGER_ICON_KEYS, (key: string) => {
          Column() {
            SymbolGlyph(getLedgerIconResource(key))
              .fontSize(22)
              .fontColor([this.selectedIcon === key ? this.brandMain : $r('app.color.text_secondary')])
          }
          .width(46)
          .height(46)
          .borderRadius(14)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor(this.selectedIcon === key ? $r('app.color.category_btn_bg') : Color.Transparent)
          .border({
            width: 1,
            color: this.selectedIcon === key ? this.brandMain : Color.Transparent
          })
          .margin({ right: 8, bottom: 8 })
          .onClick(() => {
            animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
              this.selectedIcon = key;
            });
          })
        }, (key: string) => key + this.selectedIcon)
      }
      .width('100%')
      .margin({ bottom: 12 })

      Text('选择颜色')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .margin({ bottom: 8 })

      // 颜色选择
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(LEDGER_COLORS, (color: string) => {
          Column() {
            if (this.selectedColor === color) {
              SymbolGlyph($r('sys.symbol.checkmark'))
                .fontSize(14)
                .fontColor([Color.White])
            }
          }
          .width(32)
          .height(32)
          .borderRadius(16)
          .backgroundColor(color)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .margin({ right: 10, bottom: 10 })
          .onClick(() => {
            animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
              this.selectedColor = color;
            });
          })
        }, (color: string) => color + this.selectedColor)
      }
      .width('100%')
      .margin({ bottom: 18 })

      // 按钮
      Row() {
        Button('取消')
          .backgroundColor('transparent')
          .fontColor($r('app.color.text_secondary'))
          .borderRadius(20)
          .height(40)
          .layoutWeight(1)
          .fontSize(15)
          .margin({ right: 8 })
          .onClick(() => { this.controller.close(); })

        Button('确定')
          .backgroundColor(this.brandMain)
          .fontColor($r('app.color.text_white'))
          .borderRadius(22)
          .height(44)
          .layoutWeight(1)
          .fontSize(15)
          .margin({ left: 8 })
          .onClick(() => {
            this.controller.close();
            this.onConfirm(this.name, this.selectedIcon, this.selectedColor);
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

@Component
struct LedgerManagePage {
  // 所在导航栈：由 NavDestination.onReady 注入
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('brand_main') brandMain: string = '#4E6EF2';
  @State ledgers: LedgerItem[] = [];
  @State billList: BillItem[] = [];
  @State pressedChipKey: string = '';
  private editDialogController: CustomDialogController | null = null;

  async aboutToAppear() {
    await this.loadData();
  }

  // ---------- 数据加载 ----------
  async loadData(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');

      const ledgersData = await prefs.get('ledgers_key', '[]') as string;
      const parsed = JSON.parse(ledgersData) as LedgerItem[];
      if (parsed.length > 0) {
        this.ledgers = parsed;
      }

      const billsData = await prefs.get('bills_key', '[]') as string;
      this.billList = JSON.parse(billsData) as BillItem[];
    } catch (e) {
      console.error('加载账本数据失败: ' + JSON.stringify(e));
    }
  }

  // 账本账单数
  getBillCount(id: number): number {
    let count: number = 0;
    this.billList.forEach((bill: BillItem) => {
      if ((bill.ledgerId ?? DEFAULT_LEDGER_ID) === id) {
        count++;
      }
    });
    return count;
  }

  // ---------- 保存账本列表 ----------
  async saveLedgers(ledgers: LedgerItem[]): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');
      await prefs.put('ledgers_key', JSON.stringify(ledgers));
      await prefs.flush();
      this.ledgers = ledgers;
      // 通知 Index 页面刷新账本数据
      AppStorage.setOrCreate('shouldRefreshLedgers', Date.now());
    } catch (e) {
      console.error('保存账本失败: ' + JSON.stringify(e));
      this.getUIContext().getPromptAction().showToast({ message: '保存失败', duration: 1500 });
    }
  }

  // ---------- 新建 ----------
  openCreateDialog() {
    this.editDialogController = new CustomDialogController({
      builder: LedgerEditDialog({
        title: '新建账本',
        paramName: '',
        paramIcon: 'book',
        paramColor: LEDGER_COLORS[0],
        onConfirm: (name: string, icon: string, color: string) => {
          this.createLedger(name, icon, color);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true,
      maskColor: 'rgba(0, 0, 0, 0.4)'
    });
    if (this.editDialogController) {
      this.editDialogController.open();
    }
  }

  async createLedger(name: string, icon: string, color: string): Promise<void> {
    const trimmed = name.trim();
    if (trimmed.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '请输入账本名称', duration: 1500 });
      return;
    }
    const duplicate = this.ledgers.some((item: LedgerItem) => item.name === trimmed);
    if (duplicate) {
      this.getUIContext().getPromptAction().showToast({ message: '已存在同名账本', duration: 1500 });
      return;
    }
    const newLedger: LedgerItem = {
      id: Date.now(),
      name: trimmed,
      icon: icon,
      color: color,
      categories: [...CATEGORIES],
      createdAt: Date.now(),
      isDefault: false
    };
    await this.saveLedgers([...this.ledgers, newLedger]);
    await this.loadData();
    this.getUIContext().getPromptAction().showToast({ message: '账本已创建', duration: 1200 });
  }

  // ---------- 编辑 ----------
  openEditDialog(ledger: LedgerItem) {
    this.editDialogController = new CustomDialogController({
      builder: LedgerEditDialog({
        title: '编辑账本',
        paramName: ledger.name,
        paramIcon: ledger.icon,
        paramColor: ledger.color,
        onConfirm: (name: string, icon: string, color: string) => {
          this.updateLedger(ledger, name, icon, color);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true,
      maskColor: 'rgba(0, 0, 0, 0.4)'
    });
    if (this.editDialogController) {
      this.editDialogController.open();
    }
  }

  async updateLedger(ledger: LedgerItem, name: string, icon: string, color: string): Promise<void> {
    const trimmed = name.trim();
    if (trimmed.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '请输入账本名称', duration: 1500 });
      return;
    }
    const duplicate = this.ledgers.some((item: LedgerItem) => item.id !== ledger.id && item.name === trimmed);
    if (duplicate) {
      this.getUIContext().getPromptAction().showToast({ message: '已存在同名账本', duration: 1500 });
      return;
    }
    const updated = this.ledgers.map((item: LedgerItem) => {
      if (item.id === ledger.id) {
        const copy: LedgerItem = {
          id: item.id,
          name: trimmed,
          icon: icon,
          color: color,
          categories: item.categories,
          createdAt: item.createdAt,
          isDefault: item.isDefault
        };
        return copy;
      }
      return item;
    });
    await this.saveLedgers(updated);
    await this.loadData();
    this.getUIContext().getPromptAction().showToast({ message: '账本已更新', duration: 1200 });
  }

  // ---------- 删除 ----------
  async deleteLedger(ledger: LedgerItem): Promise<void> {
    if (ledger.isDefault) {
      this.getUIContext().getPromptAction().showToast({ message: '默认账本不可删除', duration: 1500 });
      return;
    }

    const billCount = this.getBillCount(ledger.id);
    const result = await this.getUIContext().getPromptAction().showDialog({
      title: '确认删除',
      message: `删除账本「${ledger.name}」后，其中 ${billCount} 笔账单将归入默认账本，确定吗？`,
      buttons: [
        { text: '取消', color: $r('app.color.text_secondary') },
        { text: '删除', color: $r('app.color.expense_red') }
      ]
    });
    if (result.index !== 1) {
      return;
    }

    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');

      // 1. 该账本账单归入默认账本
      const billsData = await prefs.get('bills_key', '[]') as string;
      const bills = JSON.parse(billsData) as BillItem[];
      let billsChanged = false;
      bills.forEach((bill: BillItem) => {
        if ((bill.ledgerId ?? DEFAULT_LEDGER_ID) === ledger.id) {
          bill.ledgerId = DEFAULT_LEDGER_ID;
          billsChanged = true;
        }
      });
      if (billsChanged) {
        await prefs.put('bills_key', JSON.stringify(bills));
        AppStorage.setOrCreate('bills', bills);
      }

      // 2. 删除账本
      const updated = this.ledgers.filter((item: LedgerItem) => item.id !== ledger.id);
      await prefs.put('ledgers_key', JSON.stringify(updated));

      // 3. 清理该账本的预算数据
      const budgetData = await prefs.get('budget', '') as string;
      if (budgetData) {
        const parsed = JSON.parse(budgetData) as Record<string, number>;
        const kept: Record<string, number> = {};
        const prefix = `${ledger.id}:`;
        Object.keys(parsed).forEach((key: string) => {
          if (key.indexOf(prefix) !== 0) {
            kept[key] = parsed[key];
          }
        });
        await prefs.put('budget', JSON.stringify(kept));
      }

      // 4. 若删除的是当前账本，切回默认账本
      const currentIdStr = await prefs.get('current_ledger_id', '') as string;
      if (currentIdStr === ledger.id.toString()) {
        await prefs.put('current_ledger_id', DEFAULT_LEDGER_ID.toString());
      }

      await prefs.flush();

      // 5. 通知 Index 页面刷新
      AppStorage.setOrCreate('shouldRefreshBills', Date.now());
      AppStorage.setOrCreate('shouldRefreshLedgers', Date.now());

      this.ledgers = updated;
      await this.loadData();
      this.getUIContext().getPromptAction().showToast({ message: '账本已删除', duration: 1200 });
    } catch (e) {
      console.error('删除账本失败: ' + JSON.stringify(e));
      this.getUIContext().getPromptAction().showToast({ message: '删除失败', duration: 1500 });
    }
  }

  // ---------- 一键清空账本账单 ----------
  async clearLedgerBills(ledger: LedgerItem): Promise<void> {
    const billCount = this.getBillCount(ledger.id);
    if (billCount === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '该账本暂无账单', duration: 1500 });
      return;
    }

    const result = await this.getUIContext().getPromptAction().showDialog({
      title: '确认清空',
      message: `将删除账本「${ledger.name}」中的 ${billCount} 笔账单，删除后不可恢复，确定吗？`,
      buttons: [
        { text: '取消', color: $r('app.color.text_secondary') },
        { text: '清空', color: $r('app.color.expense_red') }
      ]
    });
    if (result.index !== 1) {
      return;
    }

    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');

      const billsData = await prefs.get('bills_key', '[]') as string;
      const bills = JSON.parse(billsData) as BillItem[];
      const remaining = bills.filter((bill: BillItem) => (bill.ledgerId ?? DEFAULT_LEDGER_ID) !== ledger.id);

      await prefs.put('bills_key', JSON.stringify(remaining));
      await prefs.flush();

      // 通知 Index 页面刷新
      AppStorage.setOrCreate('bills', remaining);
      AppStorage.setOrCreate('shouldRefreshBills', Date.now());

      this.billList = remaining;
      this.getUIContext().getPromptAction().showToast({ message: `已清空 ${billCount} 笔账单`, duration: 1200 });
    } catch (e) {
      console.error('清空账本账单失败: ' + JSON.stringify(e));
      this.getUIContext().getPromptAction().showToast({ message: '清空失败', duration: 1500 });
    }
  }

  // ---------- 分类管理入口 ----------
  goCategoryManage(ledger: LedgerItem) {
    this.pathStack.pushPathByName('CategoryManagePage', { ledgerId: ledger.id } as CategoryManageParams);
  }

  // 宽屏断点（全局）：平板/折叠屏下内容限宽居中
  @StorageProp('isWideScreen') isWideScreen: boolean = false;

  // 全屏沉浸式布局：状态栏/手势条避让高度由 EntryAbility 发布到 AppStorage，页面据此留白避让
  @StorageProp('statusBarVp') statusBarVp: number = 46;
  @StorageProp('navBarVp') navBarVp: number = 28;

  build() {
    NavDestination() {
    Row() {
    Column() {
      // 标题栏
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_backward'))
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor([$r('app.color.text_primary')])
          .scale({ x: this.pressedChipKey === 'back' ? 0.8 : 1, y: this.pressedChipKey === 'back' ? 0.8 : 1 })
          .animation({ curve: MotionCurves.PRESS })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              this.pressedChipKey = 'back';
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.pressedChipKey = '';
            }
          })
          .onClick(() => {
            this.pathStack.pop();
          })
          .margin({ right: 8 })

        Text('账本管理')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(24)
          .fontColor([this.brandMain])
          .scale({ x: this.pressedChipKey === 'add' ? 0.8 : 1, y: this.pressedChipKey === 'add' ? 0.8 : 1 })
          .animation({ curve: MotionCurves.PRESS })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              this.pressedChipKey = 'add';
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.pressedChipKey = '';
            }
          })
          .onClick(() => { this.openCreateDialog(); })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: this.statusBarVp + 20, bottom: 16 })

      Divider()
        .color($r('app.color.border_color'))
        .height(1)

      // 账本列表
      List() {
        ForEach(this.ledgers, (item: LedgerItem, index: number) => {
          ListItem() {
            Column() {
              Row() {
                Column() {
                  SymbolGlyph(getLedgerIconResource(item.icon))
                    .fontSize(24)
                    .fontColor([item.color])
                }
                .width(44)
                .height(44)
                .borderRadius(22)
                .backgroundColor(item.color + '1A')
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)

                Column() {
                  Row() {
                    Text(item.name)
                      .fontSize(17)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_primary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })

                    if (item.isDefault) {
                      Text('默认')
                        .fontSize(12)
                        .fontColor(this.brandMain)
                        .backgroundColor($r('app.color.category_btn_bg'))
                        .borderRadius(6)
                        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                        .margin({ left: 6 })
                    }
                  }

                  Text(`${item.categories.length} 个分类 · ${this.getBillCount(item.id)} 笔账单`)
                    .fontSize(13)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ top: 3 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                .margin({ left: 12 })

                // 编辑
                Image($r('sys.media.ohos_ic_public_edit'))
                  .width(20)
                  .height(20)
                  .fillColor(this.brandMain)
                  .margin({ right: 12 })
                  .onClick(() => { this.openEditDialog(item); })

                // 删除（默认账本隐藏）
                if (!item.isDefault) {
                  Image($r('sys.media.ohos_ic_public_remove'))
                    .width(20)
                    .height(20)
                    .fillColor($r('app.color.expense_red'))
                    .onClick(() => { this.deleteLedger(item); })
                }
              }
              .width('100%')

              // 分类管理入口
              Row() {
                Text('分类管理')
                  .fontSize(14)
                  .fontColor($r('app.color.text_secondary'))
                Blank()
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(14)
                  .fontColor([$r('app.color.text_secondary')])
              }
              .width('100%')
              .padding({ top: 10 })
              .margin({ top: 10 })
              .border({ width: { top: 1 }, color: $r('app.color.border_color') })
              .onClick(() => { this.goCategoryManage(item); })

              // 一键清空该账本账单
              Row() {
                Text('清空账单')
                  .fontSize(14)
                  .fontColor($r('app.color.expense_red'))
                Blank()
                Image($r('sys.media.ohos_ic_public_remove'))
                  .width(16)
                  .height(16)
                  .fillColor($r('app.color.expense_red'))
              }
              .width('100%')
              .padding({ top: 10 })
              .margin({ top: 10 })
              .border({ width: { top: 1 }, color: $r('app.color.border_color') })
              .onClick(() => { this.clearLedgerBills(item); })
            }
            .width('100%')
            .padding(16)
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(16)
            .margin({ bottom: 12 })
            .transition(TransitionEffect.OPACITY
              .combine(TransitionEffect.scale({ x: 0.9, y: 0.9 }))
              .animation({ curve: AnimationConfig.SPRING }))
            .scale({ x: this.pressedChipKey === 'item_' + index ? 0.96 : 1, y: this.pressedChipKey === 'item_' + index ? 0.96 : 1 })
            .animation({ curve: MotionCurves.PRESS })
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) {
                this.pressedChipKey = 'item_' + index;
              } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                this.pressedChipKey = '';
              }
            })
          }
        }, (item: LedgerItem) => item.id.toString() + item.name + item.icon + item.color)
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 16, right: 16, top: 14 })
      .scrollBar(BarState.Off)

      // 新建账本按钮
      Button('新建账本')
        .backgroundColor(this.brandMain)
        .fontColor($r('app.color.text_white'))
        .borderRadius(24)
        .height(48)
        .width('90%')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .margin({ bottom: this.navBarVp + 20 })
        .scale({ x: this.pressedChipKey === 'create' ? 0.94 : 1, y: this.pressedChipKey === 'create' ? 0.94 : 1 })
        .animation({ curve: MotionCurves.PRESS })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.pressedChipKey = 'create';
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.pressedChipKey = '';
          }
        })
        .onClick(() => { this.openCreateDialog(); })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_main'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .constraintSize({ maxWidth: this.isWideScreen ? 640 : '100%' })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.bg_main'))
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.bg_main'))
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
    })
  }

}

// 系统路由表（router_map.json）构建入口：导航栈按 name 路由到此页
@Builder
export function LedgerManagePageBuilder(name: string, param: object) {
  if (name === 'LedgerManagePage') {
    LedgerManagePage()
  }
}
