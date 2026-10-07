let budgetRingStorage = new LocalStorage();

@Entry(budgetRingStorage)
@Component
struct BudgetRingCard {
  @LocalStorageProp('monthExpense') monthExpense: string = '0.00';
  @LocalStorageProp('hasBudget') hasBudget: boolean = false;
  @LocalStorageProp('budgetUsedPercent') budgetUsedPercent: number = 0;
  @LocalStorageProp('budgetLeftText') budgetLeftText: string = '';
  @LocalStorageProp('budgetPercentText') budgetPercentText: string = '0%';
  @LocalStorageProp('budgetLevel') budgetLevel: number = 0;

  build() {
    Column() {
      Column() {
        Row() {
          Text('乌鸡记账')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary'))
          Blank()
          Text('预算进度')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')

        // 圆环进度 + 中心百分比（弹性占位，适配不同卡片高度）
        Column() {
          Stack() {
            Progress({
              value: this.hasBudget ? this.budgetUsedPercent : 0,
              total: 100,
              type: ProgressType.Ring
            })
            .width(66)
            .height(66)
            .style({ strokeWidth: 6 })
            .color(this.budgetLevel === 2 ? $r('app.color.expense_red') :
            (this.budgetLevel === 1 ? $r('app.color.budget_orange') : $r('app.color.brand_blue')))

            Column() {
              if (this.hasBudget) {
                Text(this.budgetPercentText)
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.budgetLevel === 2 ? $r('app.color.expense_red') :
                  $r('app.color.text_primary'))
                Text('已用预算')
                  .fontSize(9)
                  .fontColor($r('app.color.text_secondary'))
                  .margin({ top: 1 })
              } else {
                Text('--')
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_secondary'))
                Text('未设置预算')
                  .fontSize(9)
                  .fontColor($r('app.color.text_secondary'))
                  .margin({ top: 1 })
              }
            }
            .alignItems(HorizontalAlign.Center)
          }
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ top: 4 })

        if (this.hasBudget) {
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

          Row() {
            Text(this.budgetLeftText)
              .fontSize(11)
              .fontColor(this.budgetUsedPercent >= 100 ?
              $r('app.color.expense_red') : $r('app.color.text_secondary'))
          }
          .width('100%')
          .margin({ top: 3 })
        } else {
          Row() {
            Text('点击卡片，去设置预算')
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .margin({ top: 2 })
        }
      }
      .width('100%')
      .height('100%')
      .padding(14)
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
