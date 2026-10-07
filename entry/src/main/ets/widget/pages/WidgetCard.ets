let storage = new LocalStorage();

@Entry(storage)
@Component
struct WidgetCard {
  @LocalStorageProp('todayExpense') todayExpense: string = '0.00';
  @LocalStorageProp('monthExpense') monthExpense: string = '0.00';
  @LocalStorageProp('hasBudget') hasBudget: boolean = false;
  @LocalStorageProp('budgetUsedPercent') budgetUsedPercent: number = 0;
  @LocalStorageProp('budgetLeftText') budgetLeftText: string = '';

  build() {
    Column() {
      Column() {
        Row() {
          Text('乌鸡记账')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary'))
          Blank()
          Text('今日支出')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')

        Row() {
          Text('¥')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.expense_red'))
            .margin({ right: 2 })
          Text(this.todayExpense)
            .fontSize(32)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
        }
        .alignItems(VerticalAlign.Bottom)
        .width('100%')
        .margin({ top: 8 })

        Row() {
          Text('本月支出')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
          Text('¥' + this.monthExpense)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .margin({ left: 6 })
        }
        .width('100%')
        .margin({ top: 8 })

        if (this.hasBudget) {
          Progress({ value: this.budgetUsedPercent, total: 100, type: ProgressType.Linear })
            .width('100%')
            .height(6)
            .color($r('app.color.brand_blue'))
            .margin({ top: 10 })

          Row() {
            Text(this.budgetLeftText)
              .fontSize(11)
              .fontColor(this.budgetUsedPercent >= 100 ? $r('app.color.expense_red') : $r('app.color.text_secondary'))
          }
          .width('100%')
          .margin({ top: 6 })
        } else {
          Row() {
            Text('点击卡片，记一笔')
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .margin({ top: 12 })
        }
      }
      .width('100%')
      .height('100%')
      .padding(16)
      .backgroundColor($r('app.color.card_bg'))
      .borderRadius(16)
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      postCardAction(this, {
        'action': 'router',
        'abilityName': 'EntryAbility',
        'params': {}
      });
    })
  }
}
