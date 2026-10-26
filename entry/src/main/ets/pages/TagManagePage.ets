// pages/TagManagePage.ets
import dataPreferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import { AnimationConfig } from './Index';
import { MotionCurves } from '../common/Motion';
import { BrandSignals, DeviceSignals } from '../common/V2Signals';


interface BillItem {
  id: number;
  name: string;
  amount: number;
  type: '收入' | '支出';
  date: number;
  category: string;
  source: string;
  tags?: string[];
}

interface TagItem {
  name: string;
  count: number;  // 使用次数
}

@ComponentV2
struct TagManagePage {
  // 所在导航栈：由 NavDestination.onReady 注入
  pathStack: NavPathStack = new NavPathStack();
  // V2 全局信号（AppStorageV2 桥接层，替代原 @StorageProp）
  @Local brandSignals: BrandSignals = BrandSignals.connect();
  @Computed get brandMain(): string { return this.brandSignals.main; }
  @Computed get brandTint(): string { return this.brandSignals.tint; }
  @Local devSignals: DeviceSignals = DeviceSignals.connect();
  @Computed get isWideScreen(): boolean { return this.devSignals.isWideScreen; }
  @Computed get statusBarVp(): number { return this.devSignals.statusBarVp; }
  @Computed get navBarVp(): number { return this.devSignals.navBarVp; }
  @Local tagList: TagItem[] = [];
  @Local editTagName: string = '';
  @Local editingTag: string = '';
  @Local pressedChipKey: string = '';

  async aboutToAppear() {
    await this.loadTags();
  }

  async loadTags() {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');

      const billsData = await prefs.get('bills_key', '[]') as string;
      const bills = JSON.parse(billsData) as BillItem[];

      const tagCountMap = new Map<string, number>();
      bills.forEach((bill: BillItem) => {
        if (bill.tags) {
          bill.tags.forEach((tag: string) => {
            const count = tagCountMap.get(tag) || 0;
            tagCountMap.set(tag, count + 1);
          });
        }
      });

      // ✅ 修复：不使用解构，显式声明类型
      const tagList: TagItem[] = [];
      tagCountMap.forEach((count: number, name: string) => {
        tagList.push({ name: name, count: count });
      });
      tagList.sort((a: TagItem, b: TagItem) => b.count - a.count);
      this.tagList = tagList;
    } catch (e) {
      console.error('加载标签失败', e);
    }
  }

  async deleteTag(tagName: string) {
    const result = await this.getUIContext().getPromptAction().showDialog({
      title: '确认删除',
      message: `删除标签「${tagName}」后，所有账单中的该标签将被移除，确定吗？`,
      buttons: [
        { text: '取消', color: $r('app.color.text_secondary') },
        { text: '删除', color: $r('app.color.expense_red') }
      ]
    });

    if (result.index !== 1) return;

    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');

      // 1. 更新 all_tags
      const allTagsData = await prefs.get('all_tags', '[]') as string;
      const allTags = JSON.parse(allTagsData) as string[];
      const updatedAllTags = allTags.filter(t => t !== tagName);
      await prefs.put('all_tags', JSON.stringify(updatedAllTags));

      // 2. 从账单中移除标签
      const billsData = await prefs.get('bills_key', '[]') as string;
      const bills = JSON.parse(billsData) as BillItem[];
      bills.forEach((bill: BillItem) => {
        if (bill.tags && bill.tags.includes(tagName)) {
          bill.tags = bill.tags.filter(t => t !== tagName);
        }
      });
      await prefs.put('bills_key', JSON.stringify(bills));
      await prefs.flush();

      // ✅ 3. 立即更新 AppStorage 中的 bills，让 Index 页面实时刷新
      const appBills = AppStorage.get<BillItem[]>('bills') || [];
      const updatedAppBills = appBills.map((bill: BillItem) => {
        if (bill.tags && bill.tags.includes(tagName)) {
          bill.tags = bill.tags.filter(t => t !== tagName);
        }
        return bill;
      });
      AppStorage.setOrCreate('bills', updatedAppBills);

      // ✅ 4. 本地列表删除（带动画）
      const index = this.tagList.findIndex(item => item.name === tagName);
      if (index !== -1) {
        animateTo({ curve: AnimationConfig.SPRING }, () => {
          this.tagList.splice(index, 1);
          this.tagList = [...this.tagList];
        });
      }

      // 5. 通知 Index 页面重新加载（可选，但保留）
      AppStorage.setOrCreate('shouldRefreshBills', Date.now());

      this.getUIContext().getPromptAction().showToast({ message: '标签已删除', duration: 1500 });
    } catch (e) {
      console.error('删除失败:', e);
      this.getUIContext().getPromptAction().showToast({ message: '删除失败', duration: 1500 });
    }
  }

  async renameTag(oldName: string, newName: string) {
    if (!newName || newName.trim().length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '请输入新标签名', duration: 1500 });
      return;
    }
    if (oldName === newName.trim()) {
      animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
        this.editingTag = '';
      });
      return;
    }

    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');

      const billsData = await prefs.get('bills_key', '[]') as string;
      const bills = JSON.parse(billsData) as BillItem[];

      let needUpdate = false;
      bills.forEach((bill: BillItem) => {
        if (bill.tags && bill.tags.includes(oldName)) {
          needUpdate = true;
          bill.tags = bill.tags.map(t => t === oldName ? newName.trim() : t);
        }
      });

      // 1. 同步 all_tags，避免记账页可选标签与实际脱节
      const allTagsData = await prefs.get('all_tags', '[]') as string;
      const allTags = JSON.parse(allTagsData) as string[];
      const trimmedNew = newName.trim();
      const updatedAllTags =
        allTags.map(t => (t === oldName ? trimmedNew : t)).filter((t, i, arr) => arr.indexOf(t) === i);
      await prefs.put('all_tags', JSON.stringify(updatedAllTags));

      if (needUpdate) {
        await prefs.put('bills_key', JSON.stringify(bills));
      }
      await prefs.flush();

      // 2. 同步 AppStorage 中的 bills，让 Index 页面实时刷新
      const appBills = AppStorage.get<BillItem[]>('bills') || [];
      const updatedAppBills = appBills.map((bill: BillItem) => {
        if (bill.tags && bill.tags.includes(oldName)) {
          bill.tags = bill.tags.map(t => t === oldName ? trimmedNew : t);
        }
        return bill;
      });
      AppStorage.setOrCreate('bills', updatedAppBills);
      AppStorage.setOrCreate('shouldRefreshBills', Date.now());

      // ✅ 保存成功后，用 animateTo 退出编辑模式
      animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
        this.editingTag = '';
      });

      await this.loadTags();
      this.getUIContext().getPromptAction().showToast({ message: '标签已更新', duration: 1500 });
    } catch (e) {
      console.error('重命名标签失败', e);
      this.getUIContext().getPromptAction().showToast({ message: '更新失败', duration: 1500 });
    }
  }


  // 清空所有标签
  async clearAllTags() {
    if (this.tagList.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '暂无标签可清空', duration: 1500 });
      return;
    }

    const result = await this.getUIContext().getPromptAction().showDialog({
      title: '确认清空',
      message: `将删除所有标签（共 ${this.tagList.length} 个），并从所有账单中移除，确定吗？`,
      buttons: [
        { text: '取消', color: $r('app.color.text_secondary') },
        { text: '清空', color: $r('app.color.expense_red') }
      ]
    });

    if (result.index !== 1) return;

    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const prefs = await dataPreferences.getPreferences(context, 'bill_data');

      // 1. 清空 all_tags
      await prefs.put('all_tags', JSON.stringify([]));

      // 2. 从所有账单中移除标签
      const billsData = await prefs.get('bills_key', '[]') as string;
      const bills = JSON.parse(billsData) as BillItem[];
      bills.forEach((bill: BillItem) => {
        bill.tags = [];
      });
      await prefs.put('bills_key', JSON.stringify(bills));
      await prefs.flush();

      // 3. 更新 AppStorage 中的 bills
      const appBills = AppStorage.get<BillItem[]>('bills') || [];
      const updatedAppBills = appBills.map((bill: BillItem) => {
        bill.tags = [];
        return bill;
      });
      AppStorage.setOrCreate('bills', updatedAppBills);

      // ✅ 4. 保存当前标签数量，用于 Toast 提示
      const tagCount = this.tagList.length;

      // 5. 清空当前页面列表（带动画）
      animateTo({ curve: AnimationConfig.SPRING }, () => {
        this.tagList = [];
      });

      // 6. 通知 Index 页面刷新
      AppStorage.setOrCreate('shouldRefreshBills', Date.now());

      // ✅ 7. 使用 tagCount，而不是 this.tagList.length
      this.getUIContext().getPromptAction().showToast({ message: `已清空 ${tagCount} 个标签`, duration: 1500 });
    } catch (e) {
      console.error('清空标签失败:', e);
      this.getUIContext().getPromptAction().showToast({ message: '清空失败', duration: 1500 });
    }
  }

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

        Text('标签管理')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        if (this.tagList.length > 0) {
          Text('清空')
            .fontSize(16)
            .fontColor($r('app.color.expense_red'))
            .scale({ x: this.pressedChipKey === 'clear' ? 0.85 : 1, y: this.pressedChipKey === 'clear' ? 0.85 : 1 })
            .animation({ curve: MotionCurves.PRESS })
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) {
                this.pressedChipKey = 'clear';
              } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                this.pressedChipKey = '';
              }
            })
            .onClick(() => {
              this.clearAllTags();
            })
        } else {
          // 无标签时显示空白占位，保持标题居中
          Blank()
            .width(40)
        }
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: this.statusBarVp + 20, bottom: 16 })

      Divider()
        .color($r('app.color.border_color'))
        .height(1)

      // 标签列表
      if (this.tagList.length === 0) {
        Column() {
          SymbolGlyph($r('sys.symbol.label'))
            .fontSize(48)
            .fontColor([$r('app.color.text_secondary')])
            .margin({ bottom: 16 })
          Text('暂无标签')
            .fontSize(16)
            .fontColor($r('app.color.text_secondary'))
          Text('在记账时添加标签，这里会显示所有标签')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .width('100%')
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.scale({ x: 0.9, y: 0.9 }))
          .animation({ curve: AnimationConfig.SPRING_SOFT }))
      } else {
        List() {
          ForEach(this.tagList, (item: TagItem, index: number) => {
            ListItem() {
              Row() {
                if (this.editingTag === item.name) {
                  // ========== 编辑模式 ==========
                  TextInput({ text: item.name })
                    .fontColor($r('app.color.text_primary'))
                    .backgroundColor($r('app.color.card_bg'))
                    .borderRadius(8)
                    .border({ width: 1, color: $r('app.color.border_color') })
                    .padding({ left: 12, right: 12 })
                    .height(36)
                    .fontSize(15)
                    .layoutWeight(1)
                    .onChange((val: string) => { this.editTagName = val; })
                    .onSubmit(() => { this.renameTag(item.name, this.editTagName); })

                  Button('保存')
                    .backgroundColor(this.brandMain)
                    .fontColor($r('app.color.text_white'))
                    .borderRadius(8)
                    .height(36)
                    .padding({ left: 12, right: 12 })
                    .fontSize(14)
                    .margin({ left: 8 })
                    .onClick(() => { this.renameTag(item.name, this.editTagName); })

                  Button('取消')
                    .backgroundColor('transparent')
                    .fontColor($r('app.color.text_secondary'))
                    .borderRadius(8)
                    .height(36)
                    .padding({ left: 12, right: 12 })
                    .fontSize(14)
                    .margin({ left: 4 })
                    .onClick(() => {
                      // ✅ 退出编辑模式
                      animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
                        this.editingTag = '';
                      });
                    })
                } else {
                  // ========== 查看模式 ==========
                  Column() {
                    Text('#')
                      .fontSize(16)
                      .fontColor(this.brandMain)
                  }
                  .width(32)
                  .height(32)
                  .borderRadius(16)
                  .backgroundColor(this.brandTint)
                  .justifyContent(FlexAlign.Center)
                  .margin({ right: 10 })

                  Text('#' + item.name)
                    .fontSize(16)
                    .fontColor($r('app.color.text_primary'))
                    .layoutWeight(1)

                  Text(item.count + '次')
                    .fontSize(14)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ right: 12 })

                  // ✅ 修改：编辑图标 - 用 animateTo 包裹进入编辑模式
                  Image($r('sys.media.ohos_ic_public_edit'))
                    .width(20)
                    .height(20)
                    .fillColor(this.brandMain)
                    .onClick(() => {
                      animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
                        this.editingTag = item.name;
                        this.editTagName = item.name;
                      });
                    })
                    .margin({ right: 8 })

                  // ❌ 删除按钮不动（不需要动画）
                  Image($r('sys.media.ohos_ic_public_remove'))
                    .width(20)
                    .height(20)
                    .fillColor($r('app.color.expense_red'))
                    .onClick(() => { this.deleteTag(item.name); })
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
          }, (item: TagItem) => item.name)

          // 尾部占位：列表可滚入底部手势条区域，最后一项仍可完整停在手势条上方
          ListItem() {
            Column().height(this.navBarVp + 8)
          }
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, top: 12 })
      }
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
export function TagManagePageBuilder(name: string, param: object) {
  if (name === 'TagManagePage') {
    TagManagePage()
  }
}
