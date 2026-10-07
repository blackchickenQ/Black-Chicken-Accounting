import { BillItem, AnimationConfig, Padding } from './Index';


interface CalendarDay {
  day: number;
  isCurrentMonth: boolean;
  isToday: boolean;
  hasBill: boolean;
}

@Component
export struct CalendarTab {
  @StorageProp('brand_main') brandMain: string = '#4E6EF2';
  @Link bills: BillItem[];
  // 嵌入账单页模式：去掉自身左右边距与背景（由外层容器提供）
  @Prop embedded: boolean = false;

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

  // 是否已定位到今天
  isOnToday(): boolean {
    const today = new Date();
    return this.currentYear === today.getFullYear() &&
      this.currentMonth === today.getMonth() &&
      this.selectedDay === today.getDate();
  }

  // 回到今天
  goToday(): void {
    if (this.gridOpacity < 0.5) return;
    if (this.isOnToday()) return;

    animateTo({ duration: 100, curve: Curve.EaseIn }, () => {
      this.gridOpacity = 0;
      this.gridScale = 0.85;
      this.listOpacity = 0;
      this.listScale = 0.9;
    });

    setTimeout(() => {
      const today = new Date();
      this.currentYear = today.getFullYear();
      this.currentMonth = today.getMonth();
      this.selectedDay = today.getDate();
      this.selectedDateStr = this.formatDateStr(this.currentYear, this.currentMonth, this.selectedDay);

      this.updateCalendar();
      this.updateDayBills(this.selectedDateStr);

      animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
        this.gridOpacity = 1;
        this.gridScale = 1;
        this.listOpacity = 1;
        this.listScale = 1;
      });
    }, 120);
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

  getRootPadding(): Padding {
    if (this.embedded) {
      return { top: 0, bottom: 20, left: 0, right: 0 };
    }
    return { left: 20, right: 20, top: 12, bottom: 50 };
  }

  // ---------- 账单面板放大弹层 ----------
  @State billPanelExpanded: boolean = false;
  // 弹层转场起始偏移（原位置 → 视野中央）
  @State panelFlyX: number = 0;
  @State panelFlyY: number = 0;
  // 弹层转场起始缩放（起始尺寸 = 原账单区域尺寸）
  @State panelScaleX: number = 1;
  @State panelScaleY: number = 1;
  private billAreaX: number = 0;
  private billAreaY: number = 0;
  private billAreaW: number = 0;
  private billAreaH: number = 0;
  private rootX: number = 0;
  private rootY: number = 0;
  private rootW: number = 0;
  private rootH: number = 0;

  // ---------- 卡片弹性间距（内嵌列表 / 放大面板各自独立） ----------
  @State inlineGapStretch: number = 0;
  @State panelGapStretch: number = 0;
  private inlineCenterIdx: number = 0;
  private panelCenterIdx: number = 0;

  openBillPanel(): void {
    const panelW = this.rootW * 0.88;
    const panelH = this.rootH * 0.68;
    const origCX = this.billAreaX + this.billAreaW / 2;
    const origCY = this.billAreaY + this.billAreaH / 2;
    animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
      this.panelFlyX = origCX - (this.rootX + this.rootW / 2);
      this.panelFlyY = origCY - (this.rootY + this.rootH / 2);
      this.panelScaleX = panelW > 0 ? this.billAreaW / panelW : 1;
      this.panelScaleY = panelH > 0 ? this.billAreaH / panelH : 1;
      this.billPanelExpanded = true;
    });
  }

  closeBillPanel(): void {
    animateTo({ curve: AnimationConfig.SPRING_SOFT }, () => {
      this.billPanelExpanded = false;
    });
  }

  @Builder
  DayBillRow(item: BillItem, isPanel: boolean, idx: number) {
    Row() {
      // 收支色点：红=支出 橙黄=收入（与列表模式一致）
      Column() { }
      .width(8)
      .height(8)
      .borderRadius(4)
      .backgroundColor(item.type === '收入' ?
        $r('app.color.income_gold') : $r('app.color.expense_red'))
      .margin({ right: 10 })

      Text(item.name)
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)

      Text(this.formatAmount(item))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.getAmountColor(item))
    }
    .width('100%')
    .padding({ top: 14, left: 16, bottom: 14, right: 12 })
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(12)
    .shadow({
      radius: 4,
      color: $r('app.color.shadow_color'),
      offsetX: 0,
      offsetY: 1
    })
    .translate({
      // 距中心越远的卡片偏移越大 → 卡片间距随滚动弹性伸缩
      y: Math.max(-4, Math.min(4, idx - (isPanel ? this.panelCenterIdx : this.inlineCenterIdx))) *
        (isPanel ? this.panelGapStretch : this.inlineGapStretch)
    })
    .animation({ curve: AnimationConfig.SPRING })
    .margin({ bottom: 8 })
  }

  @Builder
  DayBillListBody(isPanel: boolean) {
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
    } else {
      List() {
        ForEach(this.dayBills, (item: BillItem, idx: number) => {
          ListItem() {
            this.DayBillRow(item, isPanel, idx)
          }
        }, (item: BillItem) => item.id.toString())
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor(Color.Transparent)
      .onScrollIndex((first: number, last: number, center: number) => {
        if (isPanel) {
          this.panelCenterIdx = center;
        } else {
          this.inlineCenterIdx = center;
        }
      })
      .onDidScroll((scrollOffset: number, scrollState: ScrollState) => {
        // 滚动速度越大间距拉伸越明显，限制最大幅度
        const target: number = Math.max(-6, Math.min(6, scrollOffset * 0.45));
        if (isPanel) {
          this.panelGapStretch = this.panelGapStretch * 0.5 + target * 0.5;
        } else {
          this.inlineGapStretch = this.inlineGapStretch * 0.5 + target * 0.5;
        }
      })
      .onScrollStop(() => {
        // 停止滚动时间距弹回原状
        if (isPanel) {
          this.panelGapStretch = 0;
        } else {
          this.inlineGapStretch = 0;
        }
      })
    }
  }

  build() {
    Stack() {
      Column() {
      // 日历卡片（不变）
      Column() {
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(22)
            .fontColor([this.brandMain])
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
            .fontColor([this.brandMain])
            .onClick(() => this.nextMonth())
            .padding({ left: 8, right: 14, top: 9, bottom: 9 })

          // 回到今天（已在今天时隐藏）
          if (!this.isOnToday()) {
            Text('今天')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.brandMain)
              .backgroundColor($r('app.color.category_btn_bg'))
              .borderRadius(8)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .margin({ left: 14 })
              .onClick(() => this.goToday())
          }
        }
        .width('100%')
        .height(44)
        .padding({ left: 8, right: 8 })

        Divider()
          .color($r('app.color.border_color'))
          .width('100%')
          .margin({ top: 4, bottom: 4 })

        Row() {
          ForEach(this.weekDays, (day: string, index: number) => {
            Text(day)
              .fontSize(14)
              .fontColor(index === 0 || index === 6 ? this.brandMain : $r('app.color.text_secondary'))
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
          }, (day: string) => day)
        }
        .width('100%')
        .height(30)

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
                      .backgroundColor(item.isToday ? $r('app.color.calendar_today_text') : this.brandMain)
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
                  item.isToday ? this.brandMain :
                    item.isCurrentMonth && item.day === this.selectedDay ? this.brandMain + '1A' :
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
        .height(252)
        .opacity(this.gridOpacity)
        .scale({ x: this.gridScale, y: this.gridScale })
      }
      .width('100%')
      .backgroundColor($r('app.color.calendar_bg'))
      .borderRadius(16)
      .padding({ top: 4, bottom: 8, left: 8, right: 8 })
      .margin({ bottom: 8 })

      Divider()
        .width('100%')
        .height(1)
        .color($r('app.color.border_color'))
        .margin({ top: 2, bottom: 8 })

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
          Text('放大')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.brandMain)
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .backgroundColor($r('app.color.category_btn_bg'))
            .borderRadius(8)
            .margin({ left: 8 })
            .onClick(() => { this.openBillPanel(); })
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

        this.DayBillListBody(false)
      }
      .width('100%')
      .layoutWeight(1)
      .opacity(this.listOpacity)
      .scale({ x: this.listScale, y: this.listScale })
      .onAreaChange((oldArea: Area, newArea: Area) => {
        this.billAreaX = (newArea.globalPosition.x ?? 0) as number;
        this.billAreaY = (newArea.globalPosition.y ?? 0) as number;
        this.billAreaW = newArea.width as number;
        this.billAreaH = newArea.height as number;
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.embedded ? Color.Transparent : $r('app.color.bg_main'))
    .padding(this.getRootPadding()) // ✅ 底部增加 50vp 空白

    // ===== 放大弹层：遮罩 + 居中账单面板（从原位置飞入视野中央） =====
    if (this.billPanelExpanded) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.mask_bg'))
        .transition(TransitionEffect.OPACITY.animation({ duration: 240, curve: Curve.EaseInOut }))
        .onClick(() => { this.closeBillPanel(); })

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
          Text('收起')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.brandMain)
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .backgroundColor($r('app.color.category_btn_bg'))
            .borderRadius(8)
            .margin({ left: 8 })
            .onClick(() => { this.closeBillPanel(); })
        }
        .width('100%')
        .margin({ bottom: 12 })

        this.DayBillListBody(true)
      }
      .width('88%')
      .height('68%')
      .padding(16)
      .backgroundColor($r('app.color.card_bg'))
      .borderRadius(20)
      .shadow({ radius: 16, color: 'rgba(0, 0, 0, 0.12)', offsetX: 0, offsetY: 6 })
      .zIndex(1)
      .transition(TransitionEffect.asymmetric(
        // 出现：从原位置原尺寸弹性放大飞入中央
        TransitionEffect.translate({ x: this.panelFlyX, y: this.panelFlyY })
          .combine(TransitionEffect.scale({ x: this.panelScaleX, y: this.panelScaleY }))
          .animation({ curve: AnimationConfig.SPRING_SOFT }),
        // 消失：飞回原位置原尺寸的同时淡出，短时长避免尾帧滞留
        TransitionEffect.translate({ x: this.panelFlyX, y: this.panelFlyY })
          .combine(TransitionEffect.scale({ x: this.panelScaleX, y: this.panelScaleY }))
          .combine(TransitionEffect.OPACITY)
          .animation({ duration: 240, curve: Curve.EaseInOut })
      ))
    }
    }
    .width('100%')
    .height('100%')
    .onAreaChange((oldArea: Area, newArea: Area) => {
      this.rootX = (newArea.globalPosition.x ?? 0) as number;
      this.rootY = (newArea.globalPosition.y ?? 0) as number;
      this.rootW = newArea.width as number;
      this.rootH = newArea.height as number;
    })
  }
}