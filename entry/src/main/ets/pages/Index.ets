import { promptAction } from '@kit.ArkUI';
import { window } from '@kit.ArkUI';
import { ConfigurationConstant, Configuration } from '@kit.AbilityKit';
import dataPreferences from '@ohos.data.preferences';

// ---------- 1. 全局动画配置 ----------
class AnimationConfig {
  static DURATION: number = 350;
  static CURVE: Curve = Curve.EaseInOut;
  static LIST_DURATION: number = 300;
}

// ---------- 2. 分类定义 ----------
const CATEGORIES: string[] = ['餐饮', '交通', '购物', '娱乐', '医疗', '教育', '其他'];
const CATEGORY_COLORS: Record<string, string> = {
  '餐饮': '#FF6B6B',
  '交通': '#4ECDC4',
  '购物': '#45B7D1',
  '娱乐': '#FFA94D',
  '医疗': '#A29BFE',
  '教育': '#FD79A8',
  '其他': '#B2BEC3'
};

// ========== 添加账单弹窗 ==========
@CustomDialog
struct AddBillDialog {
  controller: CustomDialogController = new CustomDialogController({
    builder: () => {}
  });
  @State inputName: string = '';
  @State inputAmount: string = '';
  @State selectedType: '收入' | '支出' = '支出';
  @State selectedDate: Date = new Date();
  @State selectedCategory: string = CATEGORIES[0];

  onAddBill: (name: string, amount: number, type: '收入' | '支出', date: Date, category: string) => void = () => {};

  build() {
    Column() {
      Text('记一笔')
        .fontSize(24)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .margin({ bottom: 24 })
        .alignSelf(ItemAlign.Center)

      Row() {
        Text('日期：')
          .fontSize(16)
          .fontColor($r('app.color.text_secondary'))
        DatePicker({
          selected: this.selectedDate
        })
          .onChange((value: DatePickerResult) => {
            const year = value.year ?? new Date().getFullYear();
            const month = value.month ?? new Date().getMonth();
            const day = value.day ?? new Date().getDate();
            this.selectedDate = new Date(year, month, day);
          })
          .layoutWeight(1)
      }
      .width('100%')
      .margin({ bottom: 16 })

      TextInput({ placeholder: '用途（如：午餐）' })
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .backgroundColor($r('app.color.card_bg'))
        .borderRadius(12)
        .borderColor($r('app.color.border_color'))
        .borderWidth(1)
        .padding({ left: 16, right: 16 })
        .height(48)
        .onChange((val: string) => { this.inputName = val; })
        .margin({ bottom: 16 })

      TextInput({ placeholder: '金额' })
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .backgroundColor($r('app.color.card_bg'))
        .borderRadius(12)
        .borderColor($r('app.color.border_color'))
        .borderWidth(1)
        .padding({ left: 16, right: 16 })
        .height(48)
        .type(InputType.Number)
        .onChange((val: string) => { this.inputAmount = val; })
        .margin({ bottom: 16 })

      Column() {
        Text('分类')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .alignSelf(ItemAlign.Start)
          .margin({ bottom: 10 })

        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(CATEGORIES, (cat: string) => {
            Button(cat)
              .type(ButtonType.Capsule)
              .backgroundColor(this.selectedCategory === cat ? CATEGORY_COLORS[cat] : $r('app.color.category_btn_bg'))
              .fontColor(this.selectedCategory === cat ? $r('app.color.text_white') : $r('app.color.text_primary'))
              .borderColor(this.selectedCategory === cat ? CATEGORY_COLORS[cat] : 'transparent')
              .borderWidth(1)
              .padding({ left: 16, right: 16 })
              .height(34)
              .margin({ right: 8, bottom: 8 })
              .onClick(() => {
                this.selectedCategory = cat;
              })
          }, (cat: string) => cat)
        }
        .width('100%')
      }
      .width('100%')
      .margin({ bottom: 20 })

      Row() {
        Button('支出')
          .type(ButtonType.Capsule)
          .backgroundColor(this.selectedType === '支出' ? $r('app.color.expense_red') : Color.Transparent)
          .fontColor(this.selectedType === '支出' ? $r('app.color.text_white') : $r('app.color.expense_red'))
          .borderColor($r('app.color.expense_red'))
          .borderWidth(1.5)
          .padding({ left: 24, right: 24 })
          .height(40)
          .onClick(() => { this.selectedType = '支出'; })

        Button('收入')
          .type(ButtonType.Capsule)
          .backgroundColor(this.selectedType === '收入' ? $r('app.color.income_gold') : Color.Transparent)
          .fontColor(this.selectedType === '收入' ? $r('app.color.text_white') : $r('app.color.income_gold'))
          .borderColor($r('app.color.income_gold'))
          .borderWidth(1.5)
          .padding({ left: 24, right: 24 })
          .height(40)
          .onClick(() => { this.selectedType = '收入'; })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .margin({ bottom: 28 })

      Row() {
        Button('取消')
          .backgroundColor('transparent')
          .fontColor($r('app.color.text_secondary'))
          .borderRadius(20)
          .height(44)
          .layoutWeight(1)
          .onClick(() => { this.controller.close(); })

        Blank()
          .width(16)

        Button('添加')
          .backgroundColor($r('app.color.brand_blue'))
          .fontColor($r('app.color.text_white'))
          .borderRadius(22)
          .height(44)
          .layoutWeight(1)
          .onClick(() => {
            this.handleAddBill();
          })
      }
      .width('100%')
    }
    .padding(24)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(24)
    .shadow({
      radius: 20,
      color: 'rgba(0, 0, 0, 0.08)',
      offsetX: 0,
      offsetY: 4
    })
  }

  private handleAddBill() {
    if (this.inputName.length === 0 || this.inputAmount.length === 0) {
      promptAction.showToast({ message: '请填写完整信息！', duration: 2000 });
      return;
    }
    const amountNum = parseFloat(this.inputAmount);
    if (isNaN(amountNum) || amountNum <= 0) {
      promptAction.showToast({ message: '金额必须是大于0的数字！', duration: 2000 });
      return;
    }
    this.onAddBill(
      this.inputName,
      amountNum,
      this.selectedType,
      this.selectedDate,
      this.selectedCategory
    );
    this.controller.close();
  }
}

// ========== 编辑账单弹窗 ==========
@CustomDialog
struct EditBillDialog {
  controller: CustomDialogController = new CustomDialogController({
    builder: () => {}
  });

  billId: number = 0;
  paramName: string = '';
  paramAmount: string = '';
  paramType: '收入' | '支出' = '支出';
  paramDate: Date = new Date();
  paramCategory: string = CATEGORIES[0];
  onUpdateBill: (id: number, name: string, amount: number, type: '收入' | '支出', date: Date, category: string) => void = () => {};

  @State internalName: string = '';
  @State internalAmount: string = '';
  @State internalType: '收入' | '支出' = '支出';
  @State internalDate: Date = new Date();
  @State internalCategory: string = CATEGORIES[0];

  aboutToAppear() {
    this.internalName = this.paramName;
    this.internalAmount = this.paramAmount;
    this.internalType = this.paramType;
    this.internalDate = this.paramDate;
    this.internalCategory = this.paramCategory;
  }

  build() {
    Column() {
      Text('编辑账单')
        .fontSize(24)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .margin({ bottom: 24 })
        .alignSelf(ItemAlign.Center)

      Row() {
        Text('日期：')
          .fontSize(16)
          .fontColor($r('app.color.text_secondary'))
        DatePicker({
          selected: this.internalDate
        })
          .onChange((value: DatePickerResult) => {
            const year = value.year ?? new Date().getFullYear();
            const month = value.month ?? new Date().getMonth();
            const day = value.day ?? new Date().getDate();
            this.internalDate = new Date(year, month, day);
          })
          .layoutWeight(1)
      }
      .width('100%')
      .margin({ bottom: 16 })

      TextInput({ placeholder: '用途（如：午餐）', text: this.internalName })
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .backgroundColor($r('app.color.card_bg'))
        .borderRadius(12)
        .borderColor($r('app.color.border_color'))
        .borderWidth(1)
        .padding({ left: 16, right: 16 })
        .height(48)
        .onChange((val: string) => { this.internalName = val; })
        .margin({ bottom: 16 })

      TextInput({ placeholder: '金额', text: this.internalAmount })
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .backgroundColor($r('app.color.card_bg'))
        .borderRadius(12)
        .borderColor($r('app.color.border_color'))
        .borderWidth(1)
        .padding({ left: 16, right: 16 })
        .height(48)
        .type(InputType.Number)
        .onChange((val: string) => { this.internalAmount = val; })
        .margin({ bottom: 16 })

      Column() {
        Text('分类')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .alignSelf(ItemAlign.Start)
          .margin({ bottom: 10 })

        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(CATEGORIES, (cat: string) => {
            Button(cat)
              .type(ButtonType.Capsule)
              .backgroundColor(this.internalCategory === cat ? CATEGORY_COLORS[cat] : $r('app.color.category_btn_bg'))
              .fontColor(this.internalCategory === cat ? $r('app.color.text_white') : $r('app.color.text_primary'))
              .borderColor(this.internalCategory === cat ? CATEGORY_COLORS[cat] : 'transparent')
              .borderWidth(1)
              .padding({ left: 16, right: 16 })
              .height(34)
              .margin({ right: 8, bottom: 8 })
              .onClick(() => {
                this.internalCategory = cat;
              })
          }, (cat: string) => cat)
        }
        .width('100%')
      }
      .width('100%')
      .margin({ bottom: 20 })

      Row() {
        Button('支出')
          .type(ButtonType.Capsule)
          .backgroundColor(this.internalType === '支出' ? $r('app.color.expense_red') : Color.Transparent)
          .fontColor(this.internalType === '支出' ? $r('app.color.text_white') : $r('app.color.expense_red'))
          .borderColor($r('app.color.expense_red'))
          .borderWidth(1.5)
          .padding({ left: 24, right: 24 })
          .height(40)
          .onClick(() => { this.internalType = '支出'; })

        Button('收入')
          .type(ButtonType.Capsule)
          .backgroundColor(this.internalType === '收入' ? $r('app.color.income_gold') : Color.Transparent)
          .fontColor(this.internalType === '收入' ? $r('app.color.text_white') : $r('app.color.income_gold'))
          .borderColor($r('app.color.income_gold'))
          .borderWidth(1.5)
          .padding({ left: 24, right: 24 })
          .height(40)
          .onClick(() => { this.internalType = '收入'; })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .margin({ bottom: 28 })

      Row() {
        Button('取消')
          .backgroundColor('transparent')
          .fontColor($r('app.color.text_secondary'))
          .borderRadius(20)
          .height(44)
          .layoutWeight(1)
          .onClick(() => { this.controller.close(); })

        Blank()
          .width(16)

        Button('保存')
          .backgroundColor($r('app.color.brand_blue'))
          .fontColor($r('app.color.text_white'))
          .borderRadius(22)
          .height(44)
          .layoutWeight(1)
          .onClick(() => {
            this.handleUpdateBill();
          })
      }
      .width('100%')
    }
    .padding(24)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(24)
    .shadow({
      radius: 20,
      color: 'rgba(0, 0, 0, 0.08)',
      offsetX: 0,
      offsetY: 4
    })
  }

  private handleUpdateBill() {
    if (this.internalName.length === 0 || this.internalAmount.length === 0) {
      promptAction.showToast({ message: '请填写完整信息！', duration: 2000 });
      return;
    }
    const amountNum = parseFloat(this.internalAmount);
    if (isNaN(amountNum) || amountNum <= 0) {
      promptAction.showToast({ message: '金额必须是大于0的数字！', duration: 2000 });
      return;
    }
    this.onUpdateBill(
      this.billId,
      this.internalName,
      amountNum,
      this.internalType,
      this.internalDate,
      this.internalCategory
    );
    this.controller.close();
  }
}

// ====================================================================
// 主页面
// ====================================================================
interface BillItem {
  id: number;
  name: string;
  amount: number;
  type: '收入' | '支出';
  date: number;
  category: string;
}

interface ExpenseStat {
  category: string;
  total: number;
  color: string;
}

@Entry
@Component
struct Index {
  @StorageLink('currentColorMode') @Watch('onColorModeChange') currentColorMode: number =
    ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  // 颜色模式变化时，刷新图表（如果需要）
  onColorModeChange(): void {
    // 如果当前在统计页，刷新图表
    if (this.currentTabIndex === 1) {
      this.updateChartIfNeeded();
    }
  }

  @StorageLink('bills') bills: BillItem[] = [];
  @State currentTabIndex: number = 0;
  @State currentYear: number = new Date().getFullYear();
  @State currentMonth: number = new Date().getMonth() + 1;
  @State refreshKey: number = 0;
  private dialogController: CustomDialogController | null = null;
  private editDialogController: CustomDialogController | null = null;
  private colorPalette: string[] = [
    '#FF6B6B', '#4ECDC4', '#45B7D1', '#FFA94D', '#A29BFE',
    '#FD79A8', '#00B894', '#E17055', '#6C5CE7', '#FDCB6E',
    '#00CEC9', '#D63031', '#0984E3', '#F368E0', '#FF9FF3'
  ];
  private canvasCtx: CanvasRenderingContext2D | null = null;

  // 从 Preferences 加载账单数据
  async loadBillsFromPreferences() {
    try {
      const prefs = await dataPreferences.getPreferences(getContext(this), 'bill_data');
      const data = await prefs.get('bills_key', '[]');
      const parsed = JSON.parse(data as string) as BillItem[];  // ✅ 添加类型断言
      if (parsed && parsed.length > 0) {
        this.bills = parsed;
        console.info('✅ 从 Preferences 加载了 ' + parsed.length + ' 条账单');
      } else {
        console.info('📭 Preferences 中没有账单数据');
      }
    } catch (e) {
      console.error('❌ 从 Preferences 加载失败: ' + JSON.stringify(e));
    }
  }

  // 保存账单数据到 Preferences
  async saveBillsToPreferences() {
    try {
      const prefs = await dataPreferences.getPreferences(getContext(this), 'bill_data');
      await prefs.put('bills_key', JSON.stringify(this.bills));
      await prefs.flush();
      console.info('✅ 账单已保存到 Preferences，共 ' + this.bills.length + ' 条');
    } catch (e) {
      console.error('❌ 保存到 Preferences 失败: ' + JSON.stringify(e));
    }
  }

  aboutToAppear() {
    // 初始化 PersistentStorage（保留，但不作为主要存储）
    try {
      PersistentStorage.persistProp('bills', []);
    } catch (e) {
      console.error('PersistentStorage 初始化失败: ' + JSON.stringify(e));
    }

    // ✅ 主要存储：从 Preferences 加载数据
    this.loadBillsFromPreferences();

    this.canvasCtx = new CanvasRenderingContext2D();
    setTimeout(() => {
      this.drawPieChart();
    }, 200);

    this.dialogController = new CustomDialogController({
      builder: AddBillDialog({
        onAddBill: (name, amount, type, date, category) => {
          this.addBill(name, amount, type, date, category);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true,
      maskColor: 'rgba(0, 0, 0, 0.4)'
    });

    this.editDialogController = new CustomDialogController({
      builder: EditBillDialog({
        onUpdateBill: (id, name, amount, type, date, category) => {
          this.updateBill(id, name, amount, type, date, category);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true,
      maskColor: 'rgba(0, 0, 0, 0.4)'
    });

    AppStorage.setOrCreate('currentColorMode', ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    this.updateStatusBar();
  }

  // ✅ 监听系统配置变化
  onConfigurationUpdate(newConfig: Configuration) {
    if (newConfig.colorMode !== undefined) {
      // 将颜色模式存入 AppStorage（供其他地方使用）
      AppStorage.setOrCreate('currentColorMode', newConfig.colorMode);
      // 重新设置状态栏（但这次在 EntryAbility 中已经设置，所以这里只是备用）
      this.updateStatusBar();
    }
  }

  // ---------- 状态栏适配（使用 getContext(this) 获取上下文，无 any 类型） ----------
  async updateStatusBar() {

    try {
      const win = await window.getLastWindow(getContext(this));
      const colorMode = AppStorage.get<number>('currentColorMode') ?? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
      const isDark = colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      await win.setWindowSystemBarProperties({
        statusBarColor: 'rgba(0,0,0,0)', // ✅ 顶部透明
        statusBarContentColor: isDark ? '#FFFFFF' : '#000000',
        navigationBarColor: 'rgba(0,0,0,0)', // ✅ 底部透明
        navigationBarContentColor: isDark ? '#FFFFFF' : '#000000'
      });
      console.info('✅ 系统栏已适配: ' + (isDark ? '深色' : '浅色'));
    } catch (e) {
      console.error('更新系统栏失败: ' + JSON.stringify(e));
    }
  }

  // ---------- 工具 ----------
  getFilteredBills(): BillItem[] {
    return this.bills.filter(item => {
      const d = new Date(item.date);
      return d.getFullYear() === this.currentYear && (d.getMonth() + 1) === this.currentMonth;
    });
  }

  getTotal(): number {
    let total = 0;
    for (let item of this.getFilteredBills()) {
      if (item.type === '收入') total += item.amount; else total -= item.amount;
    }
    return total;
  }

  getTotalExpense(): number {
    let sum = 0;
    for (let item of this.getFilteredBills()) {
      if (item.type === '支出') sum += item.amount;
    }
    return sum;
  }

  getExpenseStats(): ExpenseStat[] {
    const map = new Map<string, number>();
    this.getFilteredBills()
      .filter(item => item.type === '支出')
      .forEach(item => {
        const cat = item.category || '其他';
        const current = map.get(cat) || 0;
        map.set(cat, current + item.amount);
      });

    const result: ExpenseStat[] = [];
    map.forEach((total, category) => {
      const color = CATEGORY_COLORS[category] || this.colorPalette[result.length % this.colorPalette.length];
      result.push({ category, total, color });
    });
    result.sort((a, b) => b.total - a.total);
    return result;
  }

  // ---------- 月份切换 ----------
  goPreviousMonth() {
    if (this.currentMonth === 1) {
      this.currentMonth = 12;
      this.currentYear--;
    } else {
      this.currentMonth--;
    }
    this.updateChartIfNeeded();
  }

  goNextMonth() {
    if (this.currentMonth === 12) {
      this.currentMonth = 1;
      this.currentYear++;
    } else {
      this.currentMonth++;
    }
    this.updateChartIfNeeded();
  }

  // ---------- 增删改账单 ----------
  addBill(name: string, amount: number, type: '收入' | '支出', date: Date, category: string) {
    const newBill: BillItem = {
      id: Date.now(),
      name: name,
      amount: amount,
      type: type,
      date: date.getTime(),
      category: category || '其他'
    };
    animateTo({ duration: AnimationConfig.DURATION, curve: AnimationConfig.CURVE }, () => {
      this.bills = [newBill, ...this.bills];
    });
    const d = new Date(newBill.date);
    if (d.getFullYear() !== this.currentYear || (d.getMonth() + 1) !== this.currentMonth) {
      animateTo({ duration: AnimationConfig.DURATION, curve: AnimationConfig.CURVE }, () => {
        this.currentYear = d.getFullYear();
        this.currentMonth = d.getMonth() + 1;
      });
    }
    this.updateChartIfNeeded();
    this.saveBillsToPreferences();
  }

  deleteBill(id: number) {
    animateTo({ duration: AnimationConfig.DURATION, curve: AnimationConfig.CURVE }, () => {
      this.bills = this.bills.filter(item => item.id !== id);
    });
    this.updateChartIfNeeded();
    this.saveBillsToPreferences();
  }

  updateBill(id: number, name: string, amount: number, type: '收入' | '支出', date: Date, category: string) {
    const index = this.bills.findIndex(item => item.id === id);
    if (index === -1) return;

    const updatedBill: BillItem = {
      id: id,
      name: name,
      amount: amount,
      type: type,
      date: date.getTime(),
      category: category || '其他'
    };

    animateTo({ duration: AnimationConfig.DURATION, curve: AnimationConfig.CURVE }, () => {
      this.bills = [updatedBill, ...this.bills.filter(item => item.id !== id)];
    });

    const d = new Date(updatedBill.date);
    if (d.getFullYear() !== this.currentYear || (d.getMonth() + 1) !== this.currentMonth) {
      animateTo({ duration: AnimationConfig.DURATION, curve: AnimationConfig.CURVE }, () => {
        this.currentYear = d.getFullYear();
        this.currentMonth = d.getMonth() + 1;
      });
    }

    this.refreshKey++;
    this.updateChartIfNeeded();
    promptAction.showToast({ message: '✅ 账单已更新', duration: 1500 });
    this.saveBillsToPreferences();  // ✅ 添加
  }

  // ---------- 打开编辑弹窗 ----------
  openEditDialog(bill: BillItem) {
    this.editDialogController = new CustomDialogController({
      builder: EditBillDialog({
        billId: bill.id,
        paramName: bill.name,
        paramAmount: bill.amount.toString(),
        paramType: bill.type,
        paramDate: new Date(bill.date),
        paramCategory: bill.category || '其他',
        onUpdateBill: (id, name, amount, type, date, category) => {
          this.updateBill(id, name, amount, type, date, category);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true,
      maskColor: 'rgba(0, 0, 0, 0.4)'
    });
    this.editDialogController.open();
  }

  // ---------- 图表 ----------
  drawPieChart() {
    if (!this.canvasCtx) return;
    const ctx = this.canvasCtx;
    const data = this.getExpenseStats();
    const totalExpense = data.reduce((sum, d) => sum + d.total, 0);

    const width = 300;
    const height = 300;
    const centerX = width / 2;
    const centerY = height / 2;
    const radius = 110;

    ctx.clearRect(0, 0, width, height);

    if (totalExpense === 0) {
      ctx.font = '18px sans-serif';
      ctx.fillStyle = '#999';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText('本月暂无支出', centerX, centerY);
      return;
    }

    let startAngle = -Math.PI / 2;
    for (let i = 0; i < data.length; i++) {
      const item = data[i];
      const sliceAngle = (item.total / totalExpense) * 2 * Math.PI;
      ctx.beginPath();
      ctx.moveTo(centerX, centerY);
      ctx.arc(centerX, centerY, radius, startAngle, startAngle + sliceAngle);
      ctx.closePath();
      ctx.fillStyle = item.color;
      ctx.fill();
      ctx.strokeStyle = '#FFFFFF';
      ctx.lineWidth = 2;
      ctx.stroke();
      startAngle += sliceAngle;
    }
  }

  updateChartIfNeeded() {
    if (this.currentTabIndex === 1) {
      setTimeout(() => {
        this.drawPieChart();
      }, 50);
    }
  }

  // ---------- 数据迁移 ----------
  migrateOldData() {
    let needUpdate = false;
    this.bills.forEach(item => {
      if (item.date === undefined) {
        needUpdate = true;
        item.date = item.id;
      }
      if (item.category === undefined) {
        needUpdate = true;
        item.category = '其他';
      }
    });
    if (needUpdate) {
      this.saveBillsToPreferences();
    }
  }

  // ---------- 打开记账弹窗 ----------
  openAddDialog() {
    if (this.dialogController) {
      this.dialogController.open();
    }
  }

  // ---------- Tab 构建器 ----------
  @Builder
  TabBuilder(title: string, icon: string, index: number) {
    Column() {
      Text(icon)
        .fontSize(24)
      Text(title)
        .fontSize(12)
        .fontColor(this.currentTabIndex === index ? $r('app.color.brand_blue') : $r('app.color.text_secondary'))
        .margin({ top: 2 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  // ---------- 主界面 ----------
  build() {
    Tabs({ barPosition: BarPosition.End, index: this.currentTabIndex }) {
      TabContent() {
        Column() {
          // 标题单独一行（与统计页完全一致）
          Text('乌鸡记账')
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .alignSelf(ItemAlign.Start)
            .margin({ bottom: 4 })

          // 月份切换行 + 手动记账按钮（右侧）
          Row() {
            Button('<')
              .fontSize(22)
              .backgroundColor(Color.Transparent)
              .fontColor($r('app.color.brand_blue'))
              .onClick(() => {
                this.goPreviousMonth();
              })

            Text(`${this.currentYear}年${this.currentMonth}月`)
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
              .textAlign(TextAlign.Center)

            Button('>')
              .fontSize(22)
              .backgroundColor(Color.Transparent)
              .fontColor($r('app.color.brand_blue'))
              .onClick(() => {
                this.goNextMonth();
              })

            Blank()
              .width(12)

            Button('手动记账')
              .backgroundColor($r('app.color.brand_blue'))
              .fontColor($r('app.color.text_white'))
              .borderRadius(22)
              .padding({ left: 14, right: 14 })
              .height(34)
              .fontSize(13)
              .onClick(() => {
                this.openAddDialog();
              })
          }
          .width('100%')
          .padding({ bottom: 16, left: 20, right: 20 })

          Column() {
            Text('当月总资产')
              .fontSize(16)
              .fontColor($r('app.color.text_secondary'))
            Text('¥' + this.getTotal().toFixed(2))
              .fontSize(48)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.getTotal() >= 0 ? $r('app.color.text_primary') : $r('app.color.expense_red'))
              .margin({ top: 4 })
          }
          .width('100%')
          .padding({ top: 24, bottom: 24 })
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius(20)
          .shadow({
            radius: 12,
            color: 'rgba(0, 0, 0, 0.04)',
            offsetX: 0,
            offsetY: 2
          })
          .margin({ bottom: 20 })

          Row() {
            Text('当月账单')
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Blank()
            Text('共 ' + this.getFilteredBills().length + ' 笔')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .margin({ bottom: 12 })

          List() {
            ForEach(
              this.getFilteredBills(),
              (item: BillItem) => {
                ListItem() {
                  Row() {
                    Column() {
                    }
                    .width(8)
                    .height(8)
                    .borderRadius(4)
                    .backgroundColor(CATEGORY_COLORS[item.category] || '#B2BEC3')
                    .margin({ right: 12 })

                    Text(item.type)
                      .fontSize(13)
                      .backgroundColor(
                        item.type === '收入' ? $r('app.color.income_tag_bg') : $r('app.color.expense_tag_bg'))
                      .fontColor(
                        item.type === '收入' ? $r('app.color.income_tag_text') : $r('app.color.expense_tag_text'))
                      .padding({
                        left: 12,
                        right: 12,
                        top: 4,
                        bottom: 4
                      })
                      .borderRadius(8)

                    Text(item.name)
                      .fontSize(16)
                      .fontColor($r('app.color.text_primary'))
                      .layoutWeight(1)
                      .margin({ left: 12 })

                    Text((item.type === '收入' ? '+' : '-') + item.amount.toFixed(2))
                      .fontSize(17)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(item.type === '收入' ? $r('app.color.income_gold') : $r('app.color.expense_red'))

                    Button('编辑')
                      .backgroundColor(Color.Transparent)
                      .fontSize(14)
                      .fontColor($r('app.color.brand_blue'))
                      .onClick(() => {
                        this.openEditDialog(item);
                      })
                      .margin({ right: 8 })

                    Button('删除')
                      .backgroundColor(Color.Transparent)
                      .fontColor($r('app.color.expense_red'))
                      .fontSize(14)
                      .onClick(() => {
                        this.deleteBill(item.id);
                      })
                  }
                  .width('100%')
                  .padding({
                    top: 14,
                    left: 16,
                    bottom: 14,
                    right: 8
                  })
                  .backgroundColor($r('app.color.card_bg'))
                  .borderRadius(16)
                  .shadow({
                    radius: 8,
                    color: 'rgba(0, 0, 0, 0.03)',
                    offsetX: 0,
                    offsetY: 2
                  })
                  .margin({ bottom: 10 })
                }
                .transition(
                  TransitionEffect.OPACITY
                    .combine(TransitionEffect.translate({ x: 50, y: 0 }))
                    .animation({ duration: AnimationConfig.LIST_DURATION, curve: Curve.EaseOut })
                )
              },
              (item: BillItem) => item.id + '_' + this.refreshKey
            )
          }
          .width('100%')
          .height('100%')
          .layoutWeight(1)
          .backgroundColor(Color.Transparent)
        }
        .width('100%')
        .height('100%')
        .padding(20)
        .backgroundColor($r('app.color.bg_main'))
      }
      .tabBar(this.TabBuilder('记账', '📒', 0))

      TabContent() {
        Column() {
          Text('支出统计')
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .alignSelf(ItemAlign.Start)
            .margin({ bottom: 4 })

          Text(`总支出（${this.currentYear}年${this.currentMonth}月）：¥` + this.getTotalExpense().toFixed(2))
            .fontSize(16)
            .fontColor($r('app.color.expense_red'))
            .alignSelf(ItemAlign.Start)
            .margin({ bottom: 24 })

          Column() {
            Canvas(this.canvasCtx)
              .width('100%')
              .height(300)
              .onAreaChange(() => {
                this.drawPieChart();
              })
              .margin({ bottom: 6 })
          }
          .width('100%')
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius(20)
          .padding({ top: 12, bottom: 12 })
          .shadow({
            radius: 12,
            color: 'rgba(0, 0, 0, 0.04)',
            offsetX: 0,
            offsetY: 2
          })
          .margin({ bottom: 20 })

          Column() {
            Text('各分类支出明细')
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .alignSelf(ItemAlign.Start)
              .margin({ bottom: 16 })

            ForEach(this.getExpenseStats(), (item: ExpenseStat) => {
              Row() {
                Text(item.category)
                  .fontSize(14)
                  .fontColor($r('app.color.stat_text_color'))
                  .width(60)

                Column() {
                }
                .width((item.total / this.getTotalExpense()) * 200 + 20)
                .height(20)
                .backgroundColor(item.color)
                .borderRadius(12)
                .margin({ left: 8, right: 8 })

                Text('¥' + item.total.toFixed(2))
                  .fontSize(14)
                  .fontColor($r('app.color.stat_text_light'))
                  .layoutWeight(1)
                  .textAlign(TextAlign.End)
              }
              .width('100%')
              .padding({ top: 6, bottom: 6 })
              .borderRadius(8)
            }, (item: ExpenseStat) => item.category + item.total)
          }
          .width('100%')
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius(20)
          .padding(18)
          .shadow({
            radius: 12,
            color: 'rgba(0, 0, 0, 0.04)',
            offsetX: 0,
            offsetY: 2
          })
          .layoutWeight(1)
        }
        .width('100%')
        .height('100%')
        .padding(20)
        .backgroundColor($r('app.color.bg_main'))
      }
      .tabBar(this.TabBuilder('统计', '📊', 1))
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_main'))
    .animationDuration(300)
    .divider({ strokeWidth: 0, color: Color.Transparent })
    .barBackgroundColor($r('app.color.bg_main')) // 底部 Tab 栏背景与页面一致
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]) // ✅ 上下都扩展
    .onChange((index: number) => {
      this.currentTabIndex = index;
      if (index === 1) {
        setTimeout(() => {
          this.drawPieChart();
        }, 50);
      }
    })
  }
}
