import { BillItem, getCategoryColor, AnimationConfig } from './Index';


interface CalendarDay {
  day: number;
  isCurrentMonth: boolean;
  isToday: boolean;
  hasBill: boolean;
}

@Component
export struct CalendarTab {
  @Link bills: BillItem[];

  @State currentYear: number = 0;
  @State currentMonth: number = 0;
  @State selectedDay: number = 0;
  @State selectedDateStr: string = '';
  @State dayBills: BillItem[] = [];
  @State calendarDays: CalendarDay[] = [];
  @State refreshKey: number = 0;

  // 日历网格动画状态
  @State gridOpacity: number = 0;
  @State gridScale: number = 0.85;

  // ✅ 新增：账单列表动画状态
  @State listOpacity: number = 0;
  @State listScale: number = 0.9;

  // 按压的日期格索引
  @State pressedDayIdx: number = -1;

  @State touchStartY: number = 0;

  private weekDays: string[] = ['日', '一', '二', '三', '四', '五', '六'];

  aboutToAppear(): void {
    const today = new Date();
    this.currentYear = today.getFullYear();
    this.currentMonth = today.getMonth();
    this.selectedDay = today.getDate();
    this.selectedDateStr = this.formatDateStr(this.currentYear, this.currentMonth, this.selectedDay);
    this.updateCalendar();
    this.updateDayBills(this.selectedDateStr);
    // 初始动画
    animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
      this.gridScale = 1;
      this.gridOpacity = 1;
      this.listScale = 1;
      this.listOpacity = 1;
    });
  }

  formatDateStr(year: number, month: number, day: number): string {
    const m = String(month + 1).padStart(2, '0');
    const d = String(day).padStart(2, '0');
    return `${year}-${m}-${d}`;
  }

  updateCalendar(): void {
    const year = this.currentYear;
    const month = this.currentMonth;
    const firstDate = new Date(year, month, 1);
    const firstDayOfWeek = firstDate.getDay();

    const startDate = new Date(firstDate);
    startDate.setDate(startDate.getDate() - firstDayOfWeek);

    const today = new Date();
    const days: CalendarDay[] = [];

    for (let i = 0; i < 42; i++) {
      const d = new Date(startDate);
      d.setDate(startDate.getDate() + i);
      const y = d.getFullYear();
      const m = d.getMonth();
      const day = d.getDate();

      days.push({
        day,
        isCurrentMonth: (y === year && m === month),
        isToday: (y === today.getFullYear() && m === today.getMonth() && day === today.getDate()),
        hasBill: this.hasBillOnDate(y, m, day)
      });
    }

    this.calendarDays = days;
    this.refreshKey++;
  }

  hasBillOnDate(year: number, month: number, day: number): boolean {
    return this.bills.some(bill => {
      const d = new Date(bill.date);
      return d.getFullYear() === year && d.getMonth() === month && d.getDate() === day;
    });
  }

  switchMonth(delta: number): void {
    if (this.gridOpacity < 0.5) return;

    animateTo({ duration: 100, curve: Curve.EaseIn }, () => {
      this.gridOpacity = 0;
      this.gridScale = 0.85;
      this.listOpacity = 0;    // ✅ 新增
      this.listScale = 0.9;
    });

    setTimeout(() => {
      let newYear = this.currentYear;
      let newMonth = this.currentMonth + delta;
      if (newMonth < 0) {
        newMonth = 11;
        newYear--;
      } else if (newMonth > 11) {
        newMonth = 0;
        newYear++;
      }
      this.currentYear = newYear;
      this.currentMonth = newMonth;

      const maxDay = new Date(this.currentYear, this.currentMonth + 1, 0).getDate();
      if (this.selectedDay > maxDay) this.selectedDay = maxDay;
      this.selectedDateStr = this.formatDateStr(this.currentYear, this.currentMonth, this.selectedDay);

      this.updateCalendar();
      this.updateDayBills(this.selectedDateStr);

      animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
        this.gridOpacity = 1;
        this.gridScale = 1;
        this.listOpacity = 1;   // ✅ 新增
        this.listScale = 1;     // ✅ 新增
      });
    }, 120);
  }

  prevMonth(): void {
    this.switchMonth(-1);
  }

  nextMonth(): void {
    this.switchMonth(1);
  }

  // ✅ 修改：点击日期时对账单列表做动画
  selectDay(day: number): void {
    // 1. 列表淡出缩小
    animateTo({ duration: 150, curve: Curve.EaseIn }, () => {
      this.listOpacity = 0;
      this.listScale = 0.9;
    });

    // 2. 更新数据（延迟，等待淡出完成）
    setTimeout(() => {
      this.selectedDay = day;
      this.selectedDateStr = this.formatDateStr(this.currentYear, this.currentMonth, day);
      this.updateDayBills(this.selectedDateStr);
      this.updateCalendar();

      // 3. 列表弹性弹入
      animateTo({ curve: AnimationConfig.SPRING }, () => {
        this.listOpacity = 1;
        this.listScale = 1;
      });
    }, 160);
  }

  updateDayBills(dateStr: string): void {
    const parts = dateStr.split('-');
    const year = parseInt(parts[0]);
    const month = parseInt(parts[1]) - 1;
    const day = parseInt(parts[2]);

    this.dayBills = this.bills.filter(bill => {
      const d = new Date(bill.date);
      return d.getFullYear() === year && d.getMonth() === month && d.getDate() === day;
    });
    this.dayBills.sort((a, b) => b.date - a.date);
  }

  formatAmount(bill: BillItem): string {
    return (bill.type === '收入' ? '+' : '-') + '¥' + bill.amount.toFixed(2);
  }

  getAmountColor(bill: BillItem): ResourceColor {
    return bill.type === '收入' ? $r('app.color.income_gold') : $r('app.color.expense_red');
  }

  build() {
    Column() {
      // 日历卡片（不变）
      Column() {
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(22)
            .fontColor([$r('app.color.brand_blue')])
            .onClick(() => this.prevMonth())
            .padding({ left: 8, right: 8, top: 9, bottom: 9 })

          Text(`${this.currentYear}年${this.currentMonth + 1}月`)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(22)
            .fontColor([$r('app.color.brand_blue')])
            .onClick(() => this.nextMonth())
            .padding({ left: 8, right: 8, top: 9, bottom: 9 })
        }
        .width('100%')
        .height(56)
        .padding({ left: 8, right: 8 })

        Divider()
          .color($r('app.color.border_color'))
          .width('100%')
          .margin({ top: 4, bottom: 4 })

        Row() {
          ForEach(this.weekDays, (day: string, index: number) => {
            Text(day)
              .fontSize(14)
              .fontColor(index === 0 || index === 6 ? $r('app.color.brand_blue') : $r('app.color.text_secondary'))
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
          }, (day: string) => day)
        }
        .width('100%')
        .height(36)

        Grid() {
          ForEach(
            this.calendarDays,
            (item: CalendarDay, index: number) => {
              GridItem() {
                Column() {
                  Text(`${item.day}`)
                    .fontSize(16)
                    .fontWeight(item.isToday ? FontWeight.Bold : FontWeight.Normal)
                    .fontColor(
                      item.isToday ? $r('app.color.calendar_today_text') :
                        item.isCurrentMonth ? $r('app.color.calendar_text') :
                          $r('app.color.calendar_other_text')
                    )
                    .margin({ bottom: item.hasBill ? 2 : 0 })

                  if (item.hasBill) {
                    Column()
                      .width(6)
                      .height(6)
                      .borderRadius(3)
                      .backgroundColor(item.isToday ? $r('app.color.calendar_today_text') : $r('app.color.brand_blue'))
                  } else {
                    Column()
                      .width(6)
                      .height(6)
                      .borderRadius(3)
                      .backgroundColor(Color.Transparent)
                  }
                }
                .width('100%')
                .height('100%')
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
                .borderRadius(20)
                .backgroundColor(
                  item.isToday ? $r('app.color.calendar_today_bg') :
                    item.isCurrentMonth && item.day === this.selectedDay ? $r('app.color.calendar_selected_bg') :
                      Color.Transparent
                )
                .onClick(() => {
                  if (item.isCurrentMonth) {
                    this.selectDay(item.day);
                  }
                })
                .scale({
                  x: this.pressedDayIdx === index && item.isCurrentMonth ? 0.85 : 1,
                  y: this.pressedDayIdx === index && item.isCurrentMonth ? 0.85 : 1
                })
                .animation({ curve: AnimationConfig.SPRING })
                .onTouch((event: TouchEvent) => {
                  if (event.type === TouchType.Down) {
                    this.pressedDayIdx = index;
                  } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                    this.pressedDayIdx = -1;
                  }
                })
              }
            },
            (item: CalendarDay, index: number) => `${this.refreshKey}_${index}`
          )
        }
        .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr')
        .rowsTemplate('1fr 1fr 1fr 1fr 1fr 1fr')
        .width('100%')
        .height(300)
        .opacity(this.gridOpacity)
        .scale({ x: this.gridScale, y: this.gridScale })
      }
      .width('100%')
      .backgroundColor($r('app.color.calendar_bg'))
      .borderRadius(16)
      .padding({ top: 8, bottom: 12, left: 8, right: 8 })
      .margin({ bottom: 12 })

      Divider()
        .width('100%')
        .height(1)
        .color($r('app.color.border_color'))
        .margin({ top: 4, bottom: 12 })

      // ✅ 账单列表区域（带有动画）
      Column() {
        Row() {
          Text(`${this.selectedDateStr} 的账单`)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Blank()
          Text(`${this.dayBills.length} 笔`)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .padding({ left: 4, right: 4 })
        .margin({ bottom: 8 })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            // 记录触摸起始位置
            this.touchStartY = event.touches[0].y;
          } else if (event.type === TouchType.Up) {
            const deltaY = event.touches[0].y - this.touchStartY;
            // 滑动距离超过 30vp 才触发切换
            if (Math.abs(deltaY) > 30) {
              if (deltaY > 0) {
                // 向下滑 → 上个月
                this.prevMonth();
              } else {
                // 向上滑 → 下个月
                this.nextMonth();
              }
            }
          }
        })

        if (this.dayBills.length === 0) {
          Column() {
            SymbolGlyph($r('sys.symbol.calendar'))
              .fontSize(48)
              .fontColor([$r('app.color.text_secondary')])
              .margin({ bottom: 8 })
            Text('当天没有账单')
              .fontSize(16)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .layoutWeight(1)
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.scale({ x: 0.88, y: 0.88 }))
            .animation({ curve: AnimationConfig.SPRING_SOFT }))
        } else {
          List() {
            ForEach(this.dayBills, (item: BillItem) => {
              ListItem() {
                Row() {
                  Column()
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

                  Text(this.formatAmount(item))
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.getAmountColor(item))
                }
                .width('100%')
                .padding({ top: 12, left: 16, bottom: 12, right: 8 })
                .backgroundColor($r('app.color.card_bg'))
                .borderRadius(12)
                .margin({ bottom: 8 })
              }
            }, (item: BillItem) => item.id.toString())
          }
          .width('100%')
          .layoutWeight(1)
          .backgroundColor(Color.Transparent)
          .transition(TransitionEffect.OPACITY.animation({ curve: AnimationConfig.SPRING_SOFT }))
        }
      }
      .width('100%')
      .layoutWeight(1)
      .opacity(this.listOpacity)
      .scale({ x: this.listScale, y: this.listScale })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_main'))
    .padding({ left: 20, right: 20, top: 12, bottom: 50 }) // ✅ 底部增加 80vp 空白
  }
}