// pages/SearchPage.ets
// 全屏搜索页（router_map.json 注册，Index 顶栏搜索图标进入）。
// 关键词（用途/分类/标签）+ 类型 / 账本范围 / 分类 / 金额区间 / 日期范围 组合筛选；
// 点击结果后经 AppStorage('pending_detail_bill_id') 通知 Index 打开账单详情。
import dataPreferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import { BillItem, DEFAULT_LEDGER_ID, getCategoryColor, AnimationConfig } from './Index';
import { BrandSignals, DeviceSignals } from '../common/V2Signals';
import { MotionCurves } from '../common/Motion';
import { hapticTick } from '../common/Haptics';

const DAY_MS: number = 24 * 60 * 60 * 1000;
const WEEK_LABELS: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];

// 按日分组的结果结构（List 的 ListItemGroup 使用）
interface SearchResultGroup {
  key: string;
  label: string;
  bills: BillItem[];
}

@ComponentV2
struct SearchPage {
  // 所在导航栈：由 NavDestination.onReady 注入
  pathStack: NavPathStack = new NavPathStack();
  // V2 全局信号（AppStorageV2 桥接层）
  @Local brandSignals: BrandSignals = BrandSignals.connect();
  @Computed get brandMain(): string { return this.brandSignals.main; }
  @Local devSignals: DeviceSignals = DeviceSignals.connect();
  @Computed get statusBarVp(): number { return this.devSignals.statusBarVp; }
  @Computed get isWideScreen(): boolean { return this.devSignals.isWideScreen; }

  @Local bills: BillItem[] = [];
  @Local currentLedgerId: number = DEFAULT_LEDGER_ID;
  @Local keyword: string = '';
  @Local debouncedKeyword: string = '';
  @Local typeFilter: string = '全部';        // '全部' | '支出' | '收入'
  @Local scopeFilter: string = '全部账本';   // '全部账本' | '当前账本'
  @Local categoryFilter: string = '全部';
  @Local amountMin: string = '';
  @Local amountMax: string = '';
  @Local dateStart: number = 0;
  @Local dateEnd: number = 0;
  @Local showAmountSheet: boolean = false;
  debounceTimerId: number = -1;

  aboutToAppear(): void {
    this.loadBills();
  }

  aboutToDisappear(): void {
    if (this.debounceTimerId >= 0) {
      clearTimeout(this.debounceTimerId);
      this.debounceTimerId = -1;
    }
  }

  async getPrefs(): Promise<dataPreferences.Preferences> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    return dataPreferences.getPreferences(context, 'bill_data');
  }

  async loadBills(): Promise<void> {
    try {
      const prefs = await this.getPrefs();
      const data = await prefs.get('bills_key', '[]') as string;
      this.bills = JSON.parse(data) as BillItem[];
      const curIdStr = await prefs.get('current_ledger_id', '') as string;
      const curId = parseInt(curIdStr, 10);
      if (!isNaN(curId) && curId > 0) {
        this.currentLedgerId = curId;
      }
    } catch (e) {
      console.error('搜索页加载账单失败', e);
    }
  }

  // 关键词防抖：300ms 内连续输入只触发一次结果刷新
  onKeywordChange(value: string): void {
    this.keyword = value;
    if (this.debounceTimerId >= 0) {
      clearTimeout(this.debounceTimerId);
    }
    this.debounceTimerId = setTimeout(() => {
      this.debouncedKeyword = this.keyword.trim();
    }, 300);
  }

  // 分类候选项：从账单数据动态提取（覆盖全部账本用到的分类）
  getCategoryOptions(): string[] {
    const options: string[] = ['全部'];
    if (this.categoryFilter !== '全部' && !this.bills.some((b: BillItem) => b.category === this.categoryFilter)) {
      options.push(this.categoryFilter);
    }
    for (const b of this.bills) {
      const c: string = b.category !== undefined ? b.category : '';
      if (c.length > 0 && !options.includes(c)) {
        options.push(c);
      }
    }
    return options;
  }

  dateRangeReady(): boolean {
    return this.dateStart > 0 && this.dateEnd > 0;
  }

  hasAnyCondition(): boolean {
    return this.debouncedKeyword.length > 0 || this.typeFilter !== '全部' ||
      this.scopeFilter !== '全部账本' || this.categoryFilter !== '全部' ||
      this.amountMin.length > 0 || this.amountMax.length > 0 || this.dateRangeReady();
  }

  getFilteredBills(): BillItem[] {
    return this.bills.filter((b: BillItem) => {
      // 账本范围
      if (this.scopeFilter === '当前账本' &&
        (b.ledgerId ?? DEFAULT_LEDGER_ID) !== this.currentLedgerId) {
        return false;
      }
      // 关键词（用途/分类/标签，大小写不敏感）
      if (this.debouncedKeyword.length > 0) {
        const kw: string = this.debouncedKeyword.toLowerCase();
        const inName: boolean = b.name.toLowerCase().includes(kw);
        const inCategory: boolean = b.category.toLowerCase().includes(kw);
        let inTags: boolean = false;
        if (b.tags && b.tags.length > 0) {
          for (const t of b.tags) {
            if (t.toLowerCase().includes(kw)) {
              inTags = true;
              break;
            }
          }
        }
        if (!inName && !inCategory && !inTags) {
          return false;
        }
      }
      // 类型
      if (this.typeFilter !== '全部' && b.type !== this.typeFilter) {
        return false;
      }
      // 分类
      if (this.categoryFilter !== '全部' && b.category !== this.categoryFilter) {
        return false;
      }
      // 金额区间
      const minAmount: number = parseFloat(this.amountMin);
      const maxAmount: number = parseFloat(this.amountMax);
      if (this.amountMin.length > 0 && !isNaN(minAmount) && b.amount < minAmount) {
        return false;
      }
      if (this.amountMax.length > 0 && !isNaN(maxAmount) && b.amount > maxAmount) {
        return false;
      }
      // 日期范围（含当日）
      if (this.dateRangeReady() &&
        (b.date < this.dateStart || b.date >= this.dateEnd + DAY_MS)) {
        return false;
      }
      return true;
    });
  }

  // 结果按日分组（倒序），供 ListItemGroup 渲染
  buildGroups(): SearchResultGroup[] {
    const filtered: BillItem[] = this.getFilteredBills().slice().sort((a: BillItem, b: BillItem) => b.date - a.date);
    const groups: SearchResultGroup[] = [];
    for (const b of filtered) {
      const d: Date = new Date(b.date);
      const key: string = d.getFullYear() + '-' + (d.getMonth() + 1) + '-' + d.getDate();
      const label: string = (d.getMonth() + 1) + '月' + d.getDate() + '日 ' + WEEK_LABELS[d.getDay()];
      const last: SearchResultGroup | undefined = groups.length > 0 ? groups[groups.length - 1] : undefined;
      if (last !== undefined && last.key === key) {
        last.bills.push(b);
      } else {
        const group: SearchResultGroup = { key: key, label: label, bills: [b] };
        groups.push(group);
      }
    }
    return groups;
  }

  getResultSummary(): string {
    const filtered: BillItem[] = this.getFilteredBills();
    let expense: number = 0;
    let income: number = 0;
    for (const b of filtered) {
      if (b.type === '收入') {
        income += b.amount;
      } else if (b.type === '支出') {
        expense += b.amount;
      }
    }
    return '共 ' + filtered.length + ' 笔 · 支出 ¥' + expense.toFixed(2) + ' · 收入 ¥' + income.toFixed(2);
  }

  shortDate(ms: number): string {
    const d = new Date(ms);
    return (d.getMonth() + 1) + '.' + d.getDate();
  }

  // 先选起点再选终点，复用统计页嵌套日期弹窗的交互
  pickDateRange(): void {
    const ui = this.getUIContext();
    const today = new Date();
    ui.showDatePickerDialog({
      start: new Date(2000, 0, 1),
      end: today,
      selected: this.dateStart > 0 ? new Date(this.dateStart) : today,
      onDateAccept: (value: Date) => {
        const start = new Date(value.getFullYear(), value.getMonth(), value.getDate()).getTime();
        ui.showDatePickerDialog({
          start: value,
          end: today,
          selected: this.dateEnd > 0 && this.dateEnd >= start ? new Date(this.dateEnd) : value,
          onDateAccept: (v2: Date) => {
            this.dateStart = start;
            this.dateEnd = new Date(v2.getFullYear(), v2.getMonth(), v2.getDate()).getTime();
          }
        });
      }
    });
  }

  resetAllFilters(): void {
    this.keyword = '';
    this.debouncedKeyword = '';
    this.typeFilter = '全部';
    this.scopeFilter = '全部账本';
    this.categoryFilter = '全部';
    this.amountMin = '';
    this.amountMax = '';
    this.dateStart = 0;
    this.dateEnd = 0;
    hapticTick();
  }

  // 点击结果：写入详情信号并出栈，Index.onPageShow 消费后打开账单详情
  openBillDetail(bill: BillItem): void {
    AppStorage.setOrCreate('pending_detail_bill_id', bill.id);
    hapticTick();
    this.pathStack.pop();
  }

  @Builder
  filterChip(label: string, selected: boolean, onTap: () => void) {
    Text(label)
      .fontSize(13)
      .fontWeight(selected ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(selected ? Color.White : $r('app.color.text_secondary'))
      .padding({ left: 14, right: 14, top: 7, bottom: 7 })
      .borderRadius(16)
      .backgroundColor(selected ? this.brandMain : $r('app.color.card_bg'))
      .border({ width: 1, color: selected ? this.brandMain : $r('app.color.border_color') })
      .margin({ right: 8 })
      .onClick(() => { onTap(); })
  }

  @Builder
  amountRangeSheet() {
    Column() {
      Text('金额区间')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 24, bottom: 20 })
        .alignSelf(ItemAlign.Start)

      Row({ space: 10 }) {
        TextInput({ placeholder: '最低金额', text: this.amountMin })
          .type(InputType.Number)
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .borderRadius(12)
          .backgroundColor($r('app.color.card_bg'))
          .border({ width: 1, color: $r('app.color.border_color') })
          .padding({ left: 12, right: 12 })
          .onChange((v: string) => { this.amountMin = v; })

        Text('至')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))

        TextInput({ placeholder: '最高金额', text: this.amountMax })
          .type(InputType.Number)
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .borderRadius(12)
          .backgroundColor($r('app.color.card_bg'))
          .border({ width: 1, color: $r('app.color.border_color') })
          .padding({ left: 12, right: 12 })
          .onChange((v: string) => { this.amountMax = v; })
      }
      .width('100%')
      .margin({ bottom: 24 })

      Button('确定')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .backgroundColor(this.brandMain)
        .borderRadius(24)
        .height(44)
        .width('100%')
        .margin({ bottom: 34 })
        .onClick(() => {
          this.showAmountSheet = false;
          hapticTick();
        })
    }
    .width('100%')
    .padding({ left: 20, right: 20 })
  }

  build() {
    NavDestination() {
      Column() {
        // 顶部搜索栏：返回 + 搜索输入 + 清空
        Row({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(22)
            .fontWeight(FontWeight.Medium)
            .fontColor([$r('app.color.text_primary')])
            .onClick(() => { this.pathStack.pop(); })

          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(16)
              .fontColor([$r('app.color.text_secondary')])
            TextInput({ placeholder: '搜索用途、分类或标签', text: this.keyword })
              .layoutWeight(1)
              .height(38)
              .fontSize(15)
              .padding({ left: 0, right: 0 })
              .borderRadius(12)
              .backgroundColor(Color.Transparent)
              .placeholderColor($r('app.color.text_secondary'))
              .defaultFocus(true)
              .onChange((v: string) => { this.onKeywordChange(v); })
            if (this.keyword.length > 0) {
              SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
                .fontSize(16)
                .fontColor([$r('app.color.text_secondary')])
                .opacity(0.6)
                .onClick(() => { this.onKeywordChange(''); })
            }
          }
          .layoutWeight(1)
          .height(40)
          .padding({ left: 12, right: 12 })
          .borderRadius(20)
          .backgroundColor($r('app.color.card_bg'))
          .border({ width: 1, color: $r('app.color.border_color') })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .margin({ top: this.statusBarVp + 8, bottom: 10 })

        // 筛选区：类型 + 账本范围
        Row() {
          this.filterChip('全部', this.typeFilter === '全部', () => { this.typeFilter = '全部'; })
          this.filterChip('支出', this.typeFilter === '支出', () => { this.typeFilter = '支出'; })
          this.filterChip('收入', this.typeFilter === '收入', () => { this.typeFilter = '收入'; })

          Divider()
            .vertical(true)
            .height(18)
            .color($r('app.color.border_color'))
            .margin({ left: 4, right: 12 })

          this.filterChip('全部账本', this.scopeFilter === '全部账本', () => { this.scopeFilter = '全部账本'; })
          this.filterChip('当前账本', this.scopeFilter === '当前账本', () => { this.scopeFilter = '当前账本'; })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .margin({ bottom: 8 })

        // 筛选区：分类（横向滚动）
        Scroll() {
          Row() {
            ForEach(this.getCategoryOptions(), (c: string) => {
              this.filterChip(c, this.categoryFilter === c, () => { this.categoryFilter = c; })
            }, (c: string) => c)
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .padding({ left: 16, right: 16 })
        .margin({ bottom: 8 })

        // 筛选区：金额区间 / 日期范围 / 重置
        Row({ space: 8 }) {
          Button(this.amountMin.length > 0 || this.amountMax.length > 0 ?
            '¥ ' + (this.amountMin.length > 0 ? this.amountMin : '0') + ' - ' +
            (this.amountMax.length > 0 ? this.amountMax : '∞') : '金额区间')
            .fontSize(12)
            .fontColor(this.amountMin.length > 0 || this.amountMax.length > 0 ?
              this.brandMain : $r('app.color.text_secondary'))
            .backgroundColor($r('app.color.card_bg'))
            .border({
              width: 1,
              color: this.amountMin.length > 0 || this.amountMax.length > 0 ?
                this.brandMain : $r('app.color.border_color')
            })
            .borderRadius(16)
            .height(32)
            .padding({ left: 12, right: 12 })
            .onClick(() => { this.showAmountSheet = true; })
            .bindSheet($$this.showAmountSheet, this.amountRangeSheet(), {
              detents: [SheetSize.MEDIUM]
            })

          Button(this.dateRangeReady() ?
            this.shortDate(this.dateStart) + ' - ' + this.shortDate(this.dateEnd) : '日期范围')
            .fontSize(12)
            .fontColor(this.dateRangeReady() ? this.brandMain : $r('app.color.text_secondary'))
            .backgroundColor($r('app.color.card_bg'))
            .border({
              width: 1,
              color: this.dateRangeReady() ? this.brandMain : $r('app.color.border_color')
            })
            .borderRadius(16)
            .height(32)
            .padding({ left: 12, right: 12 })
            .onClick(() => { this.pickDateRange(); })

          if (this.hasAnyCondition()) {
            Button() {
              SymbolGlyph($r('sys.symbol.arrow_counterclockwise'))
                .fontSize(14)
                .fontColor([$r('app.color.text_secondary')])
            }
            .backgroundColor($r('app.color.card_bg'))
            .border({ width: 1, color: $r('app.color.border_color') })
            .borderRadius(16)
            .height(32)
            .width(36)
            .padding({ left: 0, right: 0 })
            .onClick(() => { this.resetAllFilters(); })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .margin({ bottom: 10 })

        // 结果摘要
        Text(this.hasAnyCondition() || this.keyword.length > 0 ? this.getResultSummary() :
          '输入关键词或设置筛选条件开始搜索')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .padding({ left: 16, right: 16 })
          .margin({ bottom: 8 })

        // 结果列表（按日分组）
        if (this.hasAnyCondition()) {
          List({ space: 0 }) {
            ForEach(this.buildGroups(), (group: SearchResultGroup) => {
              ListItemGroup({ header: this.groupHeader(group) }) {
                ForEach(group.bills, (bill: BillItem) => {
                  ListItem() {
                    Row() {
                      Column() { }
                      .width(8)
                      .height(8)
                      .borderRadius(4)
                      .backgroundColor(getCategoryColor(bill.category))
                      .margin({ right: 12 })

                      Column({ space: 2 }) {
                        Text(bill.name)
                          .fontSize(16)
                          .fontColor($r('app.color.text_primary'))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        Text(bill.category + (bill.source !== undefined && bill.source.length > 0 ? ' · ' + bill.source : ''))
                          .fontSize(12)
                          .fontColor($r('app.color.text_secondary'))
                      }
                      .alignItems(HorizontalAlign.Start)
                      .layoutWeight(1)

                      Text((bill.type === '收入' ? '+' : '-') + bill.amount.toFixed(2))
                        .fontSize(16)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(bill.type === '收入' ? $r('app.color.income_gold') : $r('app.color.expense_red'))
                    }
                    .width('100%')
                    .padding({ top: 12, bottom: 12, left: 16, right: 16 })
                    .backgroundColor($r('app.color.card_bg'))
                    .borderRadius(12)
                    .margin({ bottom: 8 })
                  }
                  .onClick(() => { this.openBillDetail(bill); })
                }, (bill: BillItem) => bill.id.toString())
              }
            }, (group: SearchResultGroup) => group.key + '_' + group.bills.length.toString())
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 16, right: 16 })
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
        } else {
          // 空态引导
          Column({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(44)
              .fontColor([$r('app.color.text_secondary')])
              .opacity(0.4)
            Text('搜索全部账单')
              .fontSize(15)
              .fontColor($r('app.color.text_secondary'))
            Text('支持按用途、分类、标签搜索，可叠加类型、金额、日期筛选')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .opacity(0.7)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .padding({ bottom: 120 })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg_main'))
      .constraintSize({ maxWidth: this.isWideScreen ? 640 : '100%' })
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.bg_main'))
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
    })
  }

  // 分组头：日期 + 当日笔数
  @Builder
  groupHeader(group: SearchResultGroup) {
    Row() {
      Text(group.label)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
      Text(group.bills.length.toString() + ' 笔')
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .opacity(0.7)
        .margin({ left: 8 })
    }
    .width('100%')
    .padding({ top: 10, bottom: 8 })
  }
}

// 系统路由表（router_map.json）构建入口：导航栈按 name 路由到此页
@Builder
export function SearchPageBuilder(name: string, param: object) {
  if (name === 'SearchPage') {
    SearchPage()
  }
}
