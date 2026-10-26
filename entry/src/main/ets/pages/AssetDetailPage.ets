import dataPreferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import { AnimationConfig } from './Index';
import { ASSET_PALETTE } from '../common/AppTheme';
import { MotionCurves } from '../common/Motion';

interface AssetCategory {
  name: string;
  amount: number;
}

// ========== 输入弹窗（保留 controller 但不使用 close） ==========
@CustomDialog
struct InputDialog {
  @StorageProp('brand_main') brandMain: string = '#4E6EF2';
  controller: CustomDialogController = new CustomDialogController({
    builder: () => {}
  });
  @State inputName: string = '';
  @State inputAmount: string = '';
  title: string = '添加分类';
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

      TextInput({ placeholder: '分类名称（如：微信）', text: this.inputName })
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

      TextInput({ placeholder: '金额', text: this.inputAmount })
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
              this.getUIContext().getPromptAction().showToast({ message: '请输入分类名称', duration: 2000 });
              return;
            }
            if (isNaN(amount) || amount < 0) {
              this.getUIContext().getPromptAction().showToast({ message: '请输入有效金额', duration: 2000 });
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

@Component
struct AssetDetailPage {
  // 所在导航栈：由 NavDestination.onReady 注入
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('brand_main') brandMain: string = '#4E6EF2';
  @State assetList: AssetCategory[] = [];
  @State refreshKey: number = 0;   // ✅ 新增刷新标志
  @State pressedSummary: boolean = false;
  @State pressedChipKey: string = '';
  // 小眼睛：控制金额显示/隐藏（隐藏时显示 ¥****）
  @State amountVisible: boolean = true;
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;
  private inputDialogController: CustomDialogController | null = null;

  aboutToAppear() {
    this.loadAssetData();
  }

  async loadAssetData() {
    try {
      const prefs = await dataPreferences.getPreferences(this.context, 'bill_data');
      const data = await prefs.get('asset_categories', '[]') as string;
      const parsed = JSON.parse(data) as AssetCategory[];
      if (parsed.length === 0) {
        this.assetList = [
          { name: '现金', amount: 0 },
          { name: '微信', amount: 0 },
          { name: '支付宝', amount: 0 },
          { name: '银行卡', amount: 0 }
        ];
        await this.saveAssetData();
      } else {
        this.assetList = parsed;
      }
    } catch (e) {
      console.error('加载资产数据失败', e);
    }
  }

  async saveAssetData() {
    try {
      const prefs = await dataPreferences.getPreferences(this.context, 'bill_data');
      await prefs.put('asset_categories', JSON.stringify(this.assetList));
      await prefs.flush();
    } catch (e) {
      console.error('保存资产数据失败', e);
    }
  }

  getTotal(): number {
    return this.assetList.reduce((sum, item) => sum + item.amount, 0);
  }

  // 添加分类
  openAddDialog() {
    this.inputDialogController = new CustomDialogController({
      builder: InputDialog({
        title: '添加资产分类',
        confirmText: '添加',
        onConfirm: (name: string, amount: number) => {
          if (this.assetList.some(item => item.name === name)) {
            this.getUIContext().getPromptAction().showToast({ message: '分类已存在', duration: 2000 });
            return;
          }
          animateTo({ curve: AnimationConfig.SPRING }, () => {
            this.assetList.push({ name, amount });
            this.assetList = [...this.assetList];
          });
          this.saveAssetData();
          this.inputDialogController?.close();
        },
        onCancel: () => {
          this.inputDialogController?.close();
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true,
      maskColor: 'rgba(0, 0, 0, 0.4)'
    });
    this.inputDialogController.open();
  }

  // 编辑分类
  // 注意：ForEach 项的 key 不含位置，删除/移动后 itemGenerator 不会重跑，
  // 闭包里捕获的下标会过期，因此这里传 item 引用、操作时实时定位下标
  openEditDialog(item: AssetCategory) {
    const controller = new CustomDialogController({
      builder: InputDialog({
        title: '修改金额',
        confirmText: '保存',
        inputName: item.name,
        inputAmount: item.amount.toString(),
        onConfirm: (name: string, amount: number) => {
          if (name !== item.name && this.assetList.some(i => i.name === name)) {
            this.getUIContext().getPromptAction().showToast({ message: '分类名已存在', duration: 2000 });
            return;
          }
          const idx: number = this.assetList.indexOf(item);
          if (idx < 0 || idx >= this.assetList.length) {
            controller.close();
            return;
          }
          animateTo({ curve: AnimationConfig.SPRING }, () => {
            this.assetList[idx] = { name, amount };
            this.assetList = [...this.assetList];
          });
          this.saveAssetData();
          controller.close();
        },
        onCancel: () => {
          controller.close();
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true,
      maskColor: 'rgba(0, 0, 0, 0.4)'
    });
    controller.open();
  }

  // 删除分类（传 item 引用而非下标，弹窗确认后重新定位，避免列表变化导致越界）
  deleteCategory(item: AssetCategory) {
    const index: number = this.assetList.indexOf(item);
    if (index < 0 || index >= this.assetList.length) {
      return;
    }
    this.getUIContext().getPromptAction().showDialog({
      title: '确认删除',
      message: `删除分类“${item.name}”？`,
      buttons: [
        { text: '取消', color: $r('app.color.text_secondary') },
        { text: '删除', color: $r('app.color.expense_red') }
      ]
    }).then((result) => {
      if (result.index === 1) {
        // 列表可能在弹窗期间被修改，删除前重新定位
        const idx: number = this.assetList.indexOf(item);
        if (idx < 0 || idx >= this.assetList.length) {
          return;
        }
        animateTo({ curve: AnimationConfig.SPRING }, () => {
          this.assetList.splice(idx, 1);
          this.assetList = [...this.assetList];
        });
        this.saveAssetData();
      }
    });
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

        Text('总资产明细')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        Row() {
          Text('资产管理')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.brandMain)
          Image($r('sys.media.ohos_ic_public_arrow_right'))
            .width(16)
            .height(16)
            .fillColor(this.brandMain)
        }
        .padding({ left: 8, right: 4, top: 4, bottom: 4 })
        .scale({ x: this.pressedChipKey === 'manage' ? 0.9 : 1, y: this.pressedChipKey === 'manage' ? 0.9 : 1 })
        .animation({ curve: MotionCurves.PRESS })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.pressedChipKey = 'manage';
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.pressedChipKey = '';
          }
        })
        .onClick(() => {
          // 返回主页并切换到财富页资产界面
          AppStorage.setOrCreate('wealth_mode', 'asset');
          AppStorage.setOrCreate('jump_to_wealth_asset', true);
          this.pathStack.pop();
        })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: this.statusBarVp + 20, bottom: 16 })

      Divider()
        .color($r('app.color.border_color'))
        .height(1)

      // 总资产汇总（右侧小眼睛切换金额显示/隐藏）
      Row() {
        Row() {
          Column() {
            Text('总资产合计')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
            Text(this.amountVisible ? '¥' + this.getTotal().toFixed(2) : '¥****')
              .fontSize(32)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .margin({ top: 4 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          SymbolGlyph(this.amountVisible ? $r('sys.symbol.eye') : $r('sys.symbol.eye_slash'))
            .fontSize(22)
            .fontColor([$r('app.color.text_secondary')])
            .margin({ left: 12 })
            .onClick(() => {
              this.amountVisible = !this.amountVisible;
            })
        }
        .width('100%')
        .padding({ top: 16, bottom: 16, left: 16, right: 16 })
        .backgroundColor($r('app.color.card_bg'))
        .borderRadius(16)
        .shadow({ radius: 8, color: $r('app.color.shadow_color'), offsetX: 0, offsetY: 2 })
        .scale({ x: this.pressedSummary ? 0.97 : 1, y: this.pressedSummary ? 0.97 : 1 })
        .animation({ curve: AnimationConfig.SPRING })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.pressedSummary = true;
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.pressedSummary = false;
          }
        })
        .onClick(() => { this.loadAssetData(); })
      }
      .width('100%')
      .padding({ left: 20, right: 20 })
      .margin({ bottom: 16 })

      // 列表
      List() {
        ForEach(
          this.assetList,
          (item: AssetCategory, index: number) => {
            ListItem() {
              Row() {
                Column()
                  .width(8)
                  .height(8)
                  .borderRadius(4)
                  .backgroundColor(this.colorPalette[index % this.colorPalette.length])
                  .margin({ right: 12 })

                Text(item.name)
                  .fontSize(16)
                  .fontColor($r('app.color.text_primary'))
                  .layoutWeight(1)

                Text(this.amountVisible ? '¥' + item.amount.toFixed(2) : '¥****')
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                  .margin({ right: 12 })

                Image($r('sys.media.ohos_ic_public_edit'))
                  .width(20)
                  .height(20)
                  .fillColor(this.brandMain)
                  .onClick(() => {
                    this.openEditDialog(item);
                  })
                  .margin({ right: 8 })

                Image($r('sys.media.ohos_ic_public_remove'))
                  .width(20)
                  .height(20)
                  .fillColor($r('app.color.expense_red'))
                  .onClick(() => {
                    this.deleteCategory(item);
                  })
              }
              .width('100%')
              .padding({ top: 14, left: 16, bottom: 14, right: 8 })
              .backgroundColor($r('app.color.card_bg'))
              .borderRadius(12)
              .shadow({ radius: 4, color: $r('app.color.shadow_color'), offsetX: 0, offsetY: 1 })
              .margin({ bottom: 8 })
              .transition(TransitionEffect.OPACITY
                .combine(TransitionEffect.scale({ x: 0.9, y: 0.9 }))
                .animation({ curve: AnimationConfig.SPRING }))
            }
          },
          (item: AssetCategory, index: number) => item.name + '_' + item.amount + '_' + this.refreshKey   // ✅ 复合 key（含金额，金额变化时触发该行刷新）
        )
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 20, right: 20 })

      // 底部添加按钮
      Row() {
        Button('添加分类')
          .width('100%')
          .height(48)
          .backgroundColor(this.brandMain)
          .fontColor($r('app.color.text_white'))
          .borderRadius(24)
          .fontSize(16)
          .scale({ x: this.pressedChipKey === 'create' ? 0.94 : 1, y: this.pressedChipKey === 'create' ? 0.94 : 1 })
          .animation({ curve: MotionCurves.PRESS })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              this.pressedChipKey = 'create';
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.pressedChipKey = '';
            }
          })
          .onClick(() => {
            this.openAddDialog();
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20 })
      .margin({ bottom: this.navBarVp + 20 })
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


  private colorPalette: string[] = ASSET_PALETTE;
}

// 系统路由表（router_map.json）构建入口：导航栈按 name 路由到此页
@Builder
export function AssetDetailPageBuilder(name: string, param: object) {
  if (name === 'AssetDetailPage') {
    AssetDetailPage()
  }
}
