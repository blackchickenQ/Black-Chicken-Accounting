// pages/LedgerManagePage.ets
import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
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

// 账本可选颜色
const LEDGER_COLORS: string[] = [
  '#45B7D1', '#FF6B6B', '#4ECDC4', '#FFA94D',
  '#A29BFE', '#FD79A8', '#00B894', '#E17055',
  '#6C5CE7', '#FDCB6E'
];

// ========== 账本编辑弹窗（新建/编辑共用） ==========
@CustomDialog
struct LedgerEditDialog {
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
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ bottom: 16 })

      // 名称输入
      TextInput({ placeholder: '账本名称（如：日常开销、旅行基金）', text: this.name })
        .fontColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.category_btn_bg'))
        .borderRadius(10)
        .padding({ left: 12, right: 12 })
        .height(42)
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
              .fontColor([this.selectedIcon === key ? $r('app.color.brand_blue') : $r('app.color.text_secondary')])
          }
          .width(46)
          .height(46)
          .borderRadius(14)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor(this.selectedIcon === key ? $r('app.color.category_btn_bg') : Color.Transparent)
          .border({
            width: 1,
            color: this.selectedIcon === key ? $r('app.color.brand_blue') : Color.Transparent
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
          .backgroundColor($r('app.color.category_btn_bg'))
          .fontColor($r('app.color.text_secondary'))
          .borderRadius(20)
          .height(40)
          .layoutWeight(1)
          .fontSize(15)
          .margin({ right: 8 })
          .onClick(() => { this.controller.close(); })

        Button('确定')
          .backgroundColor($r('app.color.brand_blue'))
          .fontColor($r('app.color.text_white'))
          .borderRadius(20)
          .height(40)
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
    .width('90%')
    .padding(20)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(24)
  }
}

@Entry
@Component
struct LedgerManagePage {
  @State ledgers: LedgerItem[] = [];
  @State billList: BillItem[] = [];
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
      promptAction.showToast({ message: '保存失败', duration: 1500 });
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
      promptAction.showToast({ message: '请输入账本名称', duration: 1500 });
      return;
    }
    const duplicate = this.ledgers.some((item: LedgerItem) => item.name === trimmed);
    if (duplicate) {
      promptAction.showToast({ message: '已存在同名账本', duration: 1500 });
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
    promptAction.showToast({ message: '账本已创建', duration: 1200 });
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
      promptAction.showToast({ message: '请输入账本名称', duration: 1500 });
      return;
    }
    const duplicate = this.ledgers.some((item: LedgerItem) => item.id !== ledger.id && item.name === trimmed);
    if (duplicate) {
      promptAction.showToast({ message: '已存在同名账本', duration: 1500 });
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
    promptAction.showToast({ message: '账本已更新', duration: 1200 });
  }

  // ---------- 删除 ----------
  async deleteLedger(ledger: LedgerItem): Promise<void> {
    if (ledger.isDefault) {
      promptAction.showToast({ message: '默认账本不可删除', duration: 1500 });
      return;
    }

    const billCount = this.getBillCount(ledger.id);
    const result = await promptAction.showDialog({
      title: '确认删除',
      message: `删除账本「${ledger.name}」后，其中 ${billCount} 笔账单将归入默认账本，确定吗？`,
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '删除', color: '#FF3B30' }
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
      promptAction.showToast({ message: '账本已删除', duration: 1200 });
    } catch (e) {
      console.error('删除账本失败: ' + JSON.stringify(e));
      promptAction.showToast({ message: '删除失败', duration: 1500 });
    }
  }

  // ---------- 分类管理入口 ----------
  goCategoryManage(ledger: LedgerItem) {
    router.pushUrl({
      url: 'pages/CategoryManagePage',
      params: { ledgerId: ledger.id } as CategoryManageParams
    });
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_backward'))
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor([$r('app.color.text_primary')])
          .onClick(() => {
            router.back();
          })
          .margin({ right: 8 })

        Text('账本管理')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(24)
          .fontColor([$r('app.color.brand_blue')])
          .onClick(() => { this.openCreateDialog(); })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 20, bottom: 16 })

      Divider()
        .color($r('app.color.border_color'))
        .height(1)

      // 账本列表
      List() {
        ForEach(this.ledgers, (item: LedgerItem) => {
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
                        .fontSize(11)
                        .fontColor($r('app.color.brand_blue'))
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
                  .fillColor($r('app.color.brand_blue'))
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
            }
            .width('100%')
            .padding(16)
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(16)
            .margin({ bottom: 12 })
            .transition(TransitionEffect.OPACITY
              .combine(TransitionEffect.scale({ x: 0.9, y: 0.9 }))
              .animation({ curve: AnimationConfig.SPRING }))
          }
        }, (item: LedgerItem) => item.id.toString() + item.name + item.icon + item.color)
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 16, right: 16, top: 14 })
      .scrollBar(BarState.Off)

      // 新建账本按钮
      Button('新建账本')
        .backgroundColor($r('app.color.brand_blue'))
        .fontColor($r('app.color.text_white'))
        .borderRadius(24)
        .height(48)
        .width('90%')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .margin({ bottom: 20 })
        .onClick(() => { this.openCreateDialog(); })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_main'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
