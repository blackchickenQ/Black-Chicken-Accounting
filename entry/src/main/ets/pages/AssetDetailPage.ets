import { promptAction } from '@kit.ArkUI';
import { router } from '@kit.ArkUI';
import dataPreferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import { AnimationConfig } from './Index';

interface AssetCategory {
  name: string;
  amount: number;
}

// ========== 输入弹窗（保留 controller 但不使用 close） ==========
@CustomDialog
struct InputDialog {
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
        .type(InputType.Number)
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
          .backgroundColor($r('app.color.brand_blue'))
          .fontColor($r('app.color.text_white'))
          .borderRadius(20)
          .height(40)
          .layoutWeight(1)
          .onClick(() => {
            const name = this.inputName.trim();
            const amount = parseFloat(this.inputAmount);
            if (!name) {
              promptAction.showToast({ message: '请输入分类名称', duration: 2000 });
              return;
            }
            if (isNaN(amount) || amount < 0) {
              promptAction.showToast({ message: '请输入有效金额', duration: 2000 });
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
    .borderRadius(20)
  }
}

@Entry
@Component
struct AssetDetailPage {
  @State assetList: AssetCategory[] = [];
  @State refreshKey: number = 0;   // ✅ 新增刷新标志
  @State pressedSummary: boolean = false;
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
            promptAction.showToast({ message: '分类已存在', duration: 2000 });
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
  openEditDialog(index: number) {
    const item = this.assetList[index];
    const controller = new CustomDialogController({
      builder: InputDialog({
        title: '修改金额',
        confirmText: '保存',
        inputName: item.name,
        inputAmount: item.amount.toString(),
        onConfirm: (name: string, amount: number) => {
          if (name !== item.name && this.assetList.some(i => i.name === name)) {
            promptAction.showToast({ message: '分类名已存在', duration: 2000 });
            return;
          }
          animateTo({ curve: AnimationConfig.SPRING }, () => {
            this.assetList[index] = { name, amount };
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

  // 删除分类
  deleteCategory(index: number) {
    promptAction.showDialog({
      title: '确认删除',
      message: `删除分类“${this.assetList[index].name}”？`,
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '删除', color: '#FF3B30' }
      ]
    }).then((result) => {
      if (result.index === 1) {
        animateTo({ curve: AnimationConfig.SPRING }, () => {
          this.assetList.splice(index, 1);
          this.assetList = [...this.assetList];
        });
        this.saveAssetData();
      }
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

        Text('总资产明细')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 20, bottom: 16 })

      // 总资产汇总
      Row() {
        Column() {
          Text('总资产合计')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
          Text('¥' + this.getTotal().toFixed(2))
            .fontSize(32)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .margin({ top: 4 })
        }
        .width('100%')
        .padding({ top: 16, bottom: 16 })
        .backgroundColor($r('app.color.card_bg'))
        .borderRadius(16)
        .shadow({ radius: 8, color: 'rgba(0, 0, 0, 0.04)', offsetX: 0, offsetY: 2 })
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

                Text('¥' + item.amount.toFixed(2))
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                  .margin({ right: 12 })

                Image($r('sys.media.ohos_ic_public_edit'))
                  .width(20)
                  .height(20)
                  .fillColor($r('app.color.brand_blue'))
                  .onClick(() => {
                    this.openEditDialog(index);
                  })
                  .margin({ right: 8 })

                Image($r('sys.media.ohos_ic_public_remove'))
                  .width(20)
                  .height(20)
                  .fillColor($r('app.color.expense_red'))
                  .onClick(() => {
                    this.deleteCategory(index);
                  })
              }
              .width('100%')
              .padding({ top: 14, left: 16, bottom: 14, right: 8 })
              .backgroundColor($r('app.color.card_bg'))
              .borderRadius(12)
              .shadow({ radius: 4, color: 'rgba(0, 0, 0, 0.02)', offsetX: 0, offsetY: 1 })
              .margin({ bottom: 8 })
              .transition(TransitionEffect.OPACITY
                .combine(TransitionEffect.scale({ x: 0.9, y: 0.9 }))
                .animation({ curve: AnimationConfig.SPRING }))
            }
          },
          (item: AssetCategory, index: number) => item.name + '_' + this.refreshKey   // ✅ 复合 key
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
          .backgroundColor($r('app.color.brand_blue'))
          .fontColor($r('app.color.text_white'))
          .borderRadius(24)
          .fontSize(16)
          .onClick(() => {
            this.openAddDialog();
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20 })
      .margin({ bottom: 20 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_main'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  private colorPalette: string[] = [
    '#FF6B6B', '#4ECDC4', '#45B7D1', '#FFA94D', '#A29BFE',
    '#FD79A8', '#00B894', '#E17055', '#6C5CE7', '#FDCB6E',
    '#00CEC9', '#D63031', '#0984E3', '#F368E0', '#FF9FF3'
  ];
}