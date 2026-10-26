// pages/RecycleBinPage.ets
import dataPreferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import { BillItem, RecycleBillItem, getCategoryColor, AnimationConfig } from './Index';
import { deleteBillPhotos } from '../common/BillPhotos';
import { MotionCurves } from '../common/Motion';
import { BrandSignals, DeviceSignals } from '../common/V2Signals';

const RECYCLE_KEY: string = 'recycle_bills';
const RETENTION_DAYS: number = 30;
const DAY_MS: number = 24 * 60 * 60 * 1000;

interface AssetCategory {
  name: string;
  amount: number;
}

@ComponentV2
struct RecycleBinPage {
  // 所在导航栈：由 NavDestination.onReady 注入
  pathStack: NavPathStack = new NavPathStack();
  // V2 全局信号（AppStorageV2 桥接层，替代原 @StorageProp）
  @Local brandSignals: BrandSignals = BrandSignals.connect();
  @Computed get brandMain(): string { return this.brandSignals.main; }
  @Local devSignals: DeviceSignals = DeviceSignals.connect();
  @Computed get isWideScreen(): boolean { return this.devSignals.isWideScreen; }
  @Computed get statusBarVp(): number { return this.devSignals.statusBarVp; }
  @Computed get navBarVp(): number { return this.devSignals.navBarVp; }
  @Local recycleItems: RecycleBillItem[] = [];
  @Local pressedChipKey: string = '';

  aboutToAppear() {
    this.loadAndPurge();
  }

  async getPrefs(): Promise<dataPreferences.Preferences> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    return dataPreferences.getPreferences(context, 'bill_data');
  }

  async loadAndPurge(): Promise<void> {
    try {
      const prefs = await this.getPrefs();
      const data = await prefs.get(RECYCLE_KEY, '[]') as string;
      const items = JSON.parse(data) as RecycleBillItem[];
      const now = Date.now();
      const valid = items.filter((it: RecycleBillItem) => now - it.deletedAt < RETENTION_DAYS * DAY_MS);
      if (valid.length !== items.length) {
        // 过期条目被清理时，同步删除其小票图片文件
        items.filter((it: RecycleBillItem) => now - it.deletedAt >= RETENTION_DAYS * DAY_MS)
          .forEach((it: RecycleBillItem) => {
            if (it.bill.photoUris && it.bill.photoUris.length > 0) {
              deleteBillPhotos(it.bill.photoUris);
            }
          });
        await prefs.put(RECYCLE_KEY, JSON.stringify(valid));
        await prefs.flush();
      }
      this.recycleItems = valid;
    } catch (e) {
      console.error('加载回收站失败: ' + JSON.stringify(e));
    }
  }

  formatDateTime(ts: number): string {
    const d = new Date(ts);
    return `${d.getFullYear()}/${d.getMonth() + 1}/${d.getDate()} ${d.getHours()}:${String(d.getMinutes()).padStart(2, '0')}`;
  }

  remainingDays(item: RecycleBillItem): number {
    const elapsed = Math.floor((Date.now() - item.deletedAt) / DAY_MS);
    const left = RETENTION_DAYS - elapsed;
    return left > 0 ? left : 0;
  }

  async applyAssetOnRestore(bill: BillItem): Promise<void> {
    try {
      const prefs = await this.getPrefs();
      const data = await prefs.get('asset_categories', '[]') as string;
      const list = JSON.parse(data) as AssetCategory[];
      let item = list.find((i: AssetCategory) => i.name === bill.source);
      if (!item) {
        const created: AssetCategory = { name: bill.source, amount: 0 };
        list.push(created);
        item = created;
      }
      item.amount += bill.type === '收入' ? bill.amount : -bill.amount;
      if (item.amount < 0) {
        item.amount = 0;
      }
      await prefs.put('asset_categories', JSON.stringify(list));
      await prefs.flush();
    } catch (e) {
      console.error('恢复资产余额失败: ' + JSON.stringify(e));
    }
  }

  async saveRecycleItems(items: RecycleBillItem[]): Promise<void> {
    const prefs = await this.getPrefs();
    await prefs.put(RECYCLE_KEY, JSON.stringify(items));
    await prefs.flush();
  }

  async restoreBill(item: RecycleBillItem): Promise<void> {
    try {
      const prefs = await this.getPrefs();
      const billsData = await prefs.get('bills_key', '[]') as string;
      const bills = JSON.parse(billsData) as BillItem[];
      bills.push(item.bill);
      await prefs.put('bills_key', JSON.stringify(bills));

      const rest = this.recycleItems.filter((it: RecycleBillItem) => it.bill.id !== item.bill.id);
      await this.saveRecycleItems(rest);
      animateTo({ curve: AnimationConfig.SPRING }, () => {
        this.recycleItems = rest;
      });

      await this.applyAssetOnRestore(item.bill);
      AppStorage.setOrCreate('shouldRefreshBills', Date.now());
      this.getUIContext().getPromptAction().showToast({ message: '账单已恢复', duration: 1500 });
    } catch (e) {
      console.error('恢复账单失败: ' + JSON.stringify(e));
      this.getUIContext().getPromptAction().showToast({ message: '恢复失败', duration: 1500 });
    }
  }

  async permanentDelete(item: RecycleBillItem): Promise<void> {
    const result = await this.getUIContext().getPromptAction().showDialog({
      title: '确认删除',
      message: `将彻底删除「${item.bill.name}」，删除后无法恢复，确定吗？`,
      buttons: [
        { text: '取消', color: $r('app.color.text_secondary') },
        { text: '彻底删除', color: $r('app.color.expense_red') }
      ]
    });
    if (result.index !== 1) {
      return;
    }
    const rest = this.recycleItems.filter((it: RecycleBillItem) => it.bill.id !== item.bill.id);
    // 彻底删除时同步删除其小票图片文件
    if (item.bill.photoUris && item.bill.photoUris.length > 0) {
      deleteBillPhotos(item.bill.photoUris);
    }
    await this.saveRecycleItems(rest);
    animateTo({ curve: AnimationConfig.SPRING }, () => {
      this.recycleItems = rest;
    });
    this.getUIContext().getPromptAction().showToast({ message: '已彻底删除', duration: 1200 });
  }

  async clearAll(): Promise<void> {
    if (this.recycleItems.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '回收站已是空的', duration: 1500 });
      return;
    }
    const count = this.recycleItems.length;
    const result = await this.getUIContext().getPromptAction().showDialog({
      title: '确认清空',
      message: `将彻底删除回收站中的 ${count} 条账单，删除后无法恢复，确定吗？`,
      buttons: [
        { text: '取消', color: $r('app.color.text_secondary') },
        { text: '清空', color: $r('app.color.expense_red') }
      ]
    });
    if (result.index !== 1) {
      return;
    }
    // 清空时同步删除所有小票图片文件
    this.recycleItems.forEach((it: RecycleBillItem) => {
      if (it.bill.photoUris && it.bill.photoUris.length > 0) {
        deleteBillPhotos(it.bill.photoUris);
      }
    });
    await this.saveRecycleItems([]);
    animateTo({ curve: AnimationConfig.SPRING }, () => {
      this.recycleItems = [];
    });
    this.getUIContext().getPromptAction().showToast({ message: `已清空 ${count} 条账单`, duration: 1500 });
  }

  build() {
    NavDestination() {
    Row() {
    Column() {
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

        Text('回收站')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        if (this.recycleItems.length > 0) {
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
              this.clearAll();
            })
        } else {
          Blank()
            .width(40)
        }
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: this.statusBarVp + 20, bottom: 16 })

      Divider()
        .color($r('app.color.border_color'))
        .height(1)

      Text(`删除的账单将在此保留 ${RETENTION_DAYS} 天，到期自动清除`)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 10, bottom: 4 })

      if (this.recycleItems.length === 0) {
        Column() {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(48)
            .fontColor([$r('app.color.text_secondary')])
            .margin({ bottom: 16 })
          Text('回收站是空的')
            .fontSize(16)
            .fontColor($r('app.color.text_secondary'))
          Text('删除的账单会出现在这里，可随时恢复')
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
          ForEach(this.recycleItems, (item: RecycleBillItem, index: number) => {
            ListItem() {
              Column() {
                Row() {
                  Column() {
                    Text(item.bill.category.substring(0, 1))
                      .fontSize(14)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(getCategoryColor(item.bill.category))
                  }
                  .width(32)
                  .height(32)
                  .borderRadius(16)
                  .backgroundColor(getCategoryColor(item.bill.category) + '1A')
                  .justifyContent(FlexAlign.Center)
                  .margin({ right: 10 })

                  Column() {
                    Text(item.bill.name)
                      .fontSize(16)
                      .fontColor($r('app.color.text_primary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })

                    Text(`${item.bill.category} · ${item.bill.type} · 删除于 ${this.formatDateTime(item.deletedAt)}`)
                      .fontSize(12)
                      .fontColor($r('app.color.text_secondary'))
                      .margin({ top: 2 })
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })

                    Text(`${this.remainingDays(item)} 天后自动清除`)
                      .fontSize(11)
                      .fontColor($r('app.color.text_secondary'))
                      .margin({ top: 2 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Text((item.bill.type === '收入' ? '+' : '-') + item.bill.amount.toFixed(2))
                    .fontSize(17)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(item.bill.type === '收入' ? $r('app.color.income_gold') : $r('app.color.expense_red'))
                    .margin({ left: 8 })
                }
                .width('100%')

                Row() {
                  Button('恢复')
                    .backgroundColor(this.brandMain)
                    .fontColor($r('app.color.text_white'))
                    .borderRadius(14)
                    .height(28)
                    .padding({ left: 16, right: 16 })
                    .fontSize(13)
                    .scale({ x: this.pressedChipKey === 'restore_' + index ? 0.9 : 1, y: this.pressedChipKey === 'restore_' + index ? 0.9 : 1 })
                    .animation({ curve: MotionCurves.PRESS })
                    .onTouch((event: TouchEvent) => {
                      if (event.type === TouchType.Down) {
                        this.pressedChipKey = 'restore_' + index;
                      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                        this.pressedChipKey = '';
                      }
                    })
                    .onClick(() => {
                      this.restoreBill(item);
                    })

                  Image($r('sys.media.ohos_ic_public_remove'))
                    .width(20)
                    .height(20)
                    .fillColor($r('app.color.expense_red'))
                    .margin({ left: 16 })
                    .onClick(() => {
                      this.permanentDelete(item);
                    })
                }
                .width('100%')
                .justifyContent(FlexAlign.End)
                .margin({ top: 10 })
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
          }, (item: RecycleBillItem) => item.bill.id.toString() + '_' + item.deletedAt.toString())

          // 尾部占位：列表可滚入底部手势条区域，最后一项仍可完整停在手势条上方
          ListItem() {
            Column().height(this.navBarVp + 8)
          }
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, top: 12 })
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .scrollBar(BarState.Off)
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
export function RecycleBinPageBuilder(name: string, param: object) {
  if (name === 'RecycleBinPage') {
    RecycleBinPage()
  }
}
