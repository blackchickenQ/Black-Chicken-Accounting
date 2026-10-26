// pages/CategoryManagePage.ets
import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import dataPreferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import { LedgerItem, BillItem, DEFAULT_LEDGER_ID, getCategoryColor, AnimationConfig } from './Index';
import { MotionCurves } from '../common/Motion';

// 路由参数：目标账本 id
export interface CategoryManageParams {
  ledgerId: number;
}

@Entry
@Component
struct CategoryManagePage {
  @StorageProp('brand_main') brandMain: string = '#4E6EF2';
  @State ledgerId: number = DEFAULT_LEDGER_ID;
  @State ledgerName: string = '';
  @State categories: string[] = [];
  @State billList: BillItem[] = [];
  @State newCategoryName: string = '';
  @State editingCategory: string = '';
  @State editCategoryName: string = '';
  @State pressedChipKey: string = '';

  async aboutToAppear() {
    const params = router.getParams() as CategoryManageParams;
    if (params !== undefined && params !== null && params.ledgerId !== undefined) {
      this.ledgerId = params.ledgerId;
    }
    await this.loadData();
  }

  // ---------- 数据加载 ----------
  async loadData(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');

      const ledgersData = await prefs.get('ledgers_key', '[]') as string;
      const ledgers = JSON.parse(ledgersData) as LedgerItem[];
      const found = ledgers.find((item: LedgerItem) => item.id === this.ledgerId);
      if (found !== undefined) {
        this.ledgerName = found.name;
        this.categories = found.categories;
      }

      const billsData = await prefs.get('bills_key', '[]') as string;
      this.billList = JSON.parse(billsData) as BillItem[];
    } catch (e) {
      console.error('加载分类数据失败: ' + JSON.stringify(e));
    }
  }

  // 分类使用次数（仅当前账本）
  getCategoryUsage(name: string): number {
    let count: number = 0;
    this.billList.forEach((bill: BillItem) => {
      if ((bill.ledgerId ?? DEFAULT_LEDGER_ID) === this.ledgerId && bill.category === name) {
        count++;
      }
    });
    return count;
  }

  // ---------- 保存 ----------
  async saveCategories(categories: string[]): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');
      const ledgersData = await prefs.get('ledgers_key', '[]') as string;
      const ledgers = JSON.parse(ledgersData) as LedgerItem[];
      const updated = ledgers.map((item: LedgerItem) => {
        if (item.id === this.ledgerId) {
          const copy: LedgerItem = {
            id: item.id,
            name: item.name,
            icon: item.icon,
            color: item.color,
            categories: categories,
            createdAt: item.createdAt,
            isDefault: item.isDefault
          };
          return copy;
        }
        return item;
      });
      await prefs.put('ledgers_key', JSON.stringify(updated));
      await prefs.flush();
      this.categories = categories;
      // 通知 Index 页面刷新账本数据
      AppStorage.setOrCreate('shouldRefreshLedgers', Date.now());
    } catch (e) {
      console.error('保存分类失败: ' + JSON.stringify(e));
      promptAction.showToast({ message: '保存失败', duration: 1500 });
    }
  }

  // ---------- 增 ----------
  async addCategory(): Promise<void> {
    const name = this.newCategoryName.trim();
    if (name.length === 0) {
      promptAction.showToast({ message: '请输入分类名称', duration: 1500 });
      return;
    }
    if (this.categories.indexOf(name) !== -1) {
      promptAction.showToast({ message: '该分类已存在', duration: 1500 });
      return;
    }
    const updated: string[] = [...this.categories, name];
    this.newCategoryName = '';
    await this.saveCategories(updated);
    promptAction.showToast({ message: '分类已添加', duration: 1200 });
  }

  // ---------- 改 ----------
  async renameCategory(oldName: string, newName: string): Promise<void> {
    const name = newName.trim();
    if (name.length === 0) {
      promptAction.showToast({ message: '请输入分类名称', duration: 1500 });
      return;
    }
    if (name === oldName) {
      animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
        this.editingCategory = '';
      });
      return;
    }
    if (this.categories.indexOf(name) !== -1) {
      promptAction.showToast({ message: '该分类已存在', duration: 1500 });
      return;
    }

    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');

      // 1. 联动改写该账本账单的分类名
      const billsData = await prefs.get('bills_key', '[]') as string;
      const bills = JSON.parse(billsData) as BillItem[];
      let billsChanged = false;
      bills.forEach((bill: BillItem) => {
        if ((bill.ledgerId ?? DEFAULT_LEDGER_ID) === this.ledgerId && bill.category === oldName) {
          bill.category = name;
          billsChanged = true;
        }
      });
      if (billsChanged) {
        await prefs.put('bills_key', JSON.stringify(bills));
        AppStorage.setOrCreate('bills', bills);
      }

      // 2. 更新账本分类列表
      const updated = this.categories.map((item: string) => item === oldName ? name : item);
      await this.saveCategories(updated);
      await prefs.flush();

      // 3. 通知账单刷新
      if (billsChanged) {
        AppStorage.setOrCreate('shouldRefreshBills', Date.now());
      }

      animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
        this.editingCategory = '';
      });
      await this.loadData();
      promptAction.showToast({ message: '分类已更新', duration: 1200 });
    } catch (e) {
      console.error('重命名分类失败: ' + JSON.stringify(e));
      promptAction.showToast({ message: '更新失败', duration: 1500 });
    }
  }

  // ---------- 删 ----------
  async deleteCategory(name: string): Promise<void> {
    const usage = this.getCategoryUsage(name);
    if (usage > 0) {
      promptAction.showToast({
        message: `有 ${usage} 笔账单正在使用「${name}」，无法删除`,
        duration: 2000
      });
      return;
    }
    if (this.categories.length <= 1) {
      promptAction.showToast({ message: '至少保留一个分类', duration: 1500 });
      return;
    }

    const result = await promptAction.showDialog({
      title: '确认删除',
      message: `确定删除分类「${name}」吗？`,
      buttons: [
        { text: '取消', color: $r('app.color.text_secondary') },
        { text: '删除', color: $r('app.color.expense_red') }
      ]
    });
    if (result.index !== 1) {
      return;
    }

    const updated = this.categories.filter((item: string) => item !== name);
    await this.saveCategories(updated);
    promptAction.showToast({ message: '分类已删除', duration: 1200 });
  }

  // 宽屏断点（全局）：平板/折叠屏下内容限宽居中
  @StorageProp('isWideScreen') isWideScreen: boolean = false;

  // 全屏沉浸式布局：状态栏/手势条避让高度由 EntryAbility 发布到 AppStorage，页面据此留白避让
  @StorageProp('statusBarVp') statusBarVp: number = 46;
  @StorageProp('navBarVp') navBarVp: number = 28;

  build() {
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
            router.back();
          })
          .margin({ right: 8 })

        Column() {
          Text('分类管理')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          if (this.ledgerName.length > 0) {
            Text(this.ledgerName)
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 2 })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: this.statusBarVp + 20, bottom: 16 })

      Divider()
        .color($r('app.color.border_color'))
        .height(1)

      // 新增分类输入
      Row() {
        TextInput({ placeholder: '输入新分类名称', text: this.newCategoryName })
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius(12)
          .border({ width: 1, color: $r('app.color.border_color') })
          .padding({ left: 16, right: 16 })
          .height(44)
          .fontSize(15)
          .layoutWeight(1)
          .onChange((val: string) => { this.newCategoryName = val; })
          .onSubmit(() => { this.addCategory(); })

        Button('添加')
          .backgroundColor(this.brandMain)
          .fontColor($r('app.color.text_white'))
          .borderRadius(12)
          .height(44)
          .padding({ left: 16, right: 16 })
          .fontSize(15)
          .margin({ left: 10 })
          .onClick(() => { this.addCategory(); })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 6 })

      // 分类列表
      List() {
        ForEach(this.categories, (cat: string, index: number) => {
          ListItem() {
            Row() {
              if (this.editingCategory === cat) {
                // ========== 编辑模式 ==========
                TextInput({ text: cat })
                  .fontColor($r('app.color.text_primary'))
                  .backgroundColor($r('app.color.card_bg'))
                  .borderRadius(8)
                  .border({ width: 1, color: $r('app.color.border_color') })
                  .padding({ left: 12, right: 12 })
                  .height(36)
                  .fontSize(15)
                  .layoutWeight(1)
                  .onChange((val: string) => { this.editCategoryName = val; })
                  .onSubmit(() => { this.renameCategory(cat, this.editCategoryName); })

                Button('保存')
                  .backgroundColor(this.brandMain)
                  .fontColor($r('app.color.text_white'))
                  .borderRadius(8)
                  .height(36)
                  .padding({ left: 12, right: 12 })
                  .fontSize(14)
                  .margin({ left: 8 })
                  .onClick(() => { this.renameCategory(cat, this.editCategoryName); })

                Button('取消')
                  .backgroundColor('transparent')
                  .fontColor($r('app.color.text_secondary'))
                  .borderRadius(8)
                  .height(36)
                  .padding({ left: 12, right: 12 })
                  .fontSize(14)
                  .margin({ left: 4 })
                  .onClick(() => {
                    animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
                      this.editingCategory = '';
                    });
                  })
              } else {
                // ========== 查看模式 ==========
                Column() {
                  Text(cat.substring(0, 1))
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(getCategoryColor(cat))
                }
                .width(32)
                .height(32)
                .borderRadius(16)
                .backgroundColor(getCategoryColor(cat) + '1A')
                .justifyContent(FlexAlign.Center)
                .margin({ right: 10 })

                Text(cat)
                  .fontSize(16)
                  .fontColor($r('app.color.text_primary'))
                  .layoutWeight(1)

                Text(this.getCategoryUsage(cat) + '笔')
                  .fontSize(14)
                  .fontColor($r('app.color.text_secondary'))
                  .margin({ right: 12 })

                Image($r('sys.media.ohos_ic_public_edit'))
                  .width(20)
                  .height(20)
                  .fillColor(this.brandMain)
                  .onClick(() => {
                    animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
                      this.editingCategory = cat;
                      this.editCategoryName = cat;
                    });
                  })
                  .margin({ right: 10 })

                Image($r('sys.media.ohos_ic_public_remove'))
                  .width(20)
                  .height(20)
                  .fillColor($r('app.color.expense_red'))
                  .onClick(() => { this.deleteCategory(cat); })
              }
            }
            .width('100%')
            .padding({ top: 12, bottom: 12, left: 16, right: 16 })
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(12)
            .margin({ bottom: 8 })
            .shadow({ radius: 6, color: $r('app.color.shadow_color'), offsetX: 0, offsetY: 2 })
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
        }, (cat: string) => cat + this.editingCategory)

        // 尾部占位：列表可滚入底部手势条区域，最后一项仍可完整停在手势条上方
        ListItem() {
          Column().height(this.navBarVp + 8)
        }
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 16, right: 16, top: 8 })
      .scrollBar(BarState.Off)
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

}
