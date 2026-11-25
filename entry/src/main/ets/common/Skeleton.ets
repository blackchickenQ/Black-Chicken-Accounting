// ---------- 骨架屏 / 空状态通用组件 ----------
// SkeletonBlock：呼吸式占位块（明暗往复脉动，比闪烁更柔和、可访问性更好）
// BillListSkeleton：账单页首屏加载骨架（汇总卡 + 分组卡占位）
// EmptyState：无数据空状态（图标 + 标题 + 副标题），入场淡入上浮
@ComponentV2
export struct SkeletonBlock {
  @Param blockWidth: Length = '100%';
  @Param blockHeight: number = 16;
  @Param blockRadius: number = 8;
  @Local breathOpacity: number = 1;

  build() {
    Column()
      .width(this.blockWidth)
      .height(this.blockHeight)
      .borderRadius(this.blockRadius)
      .backgroundColor($r('app.color.skeleton_track'))
      .opacity(this.breathOpacity)
      .onAppear(() => {
        this.getUIContext().animateTo({
          duration: 850,
          curve: Curve.EaseInOut,
          iterations: -1,
          playMode: PlayMode.Alternate
        }, () => {
          this.breathOpacity = 0.45;
        });
      })
  }
}

// 账单页首屏加载骨架：结构与真实汇总卡/分组卡一致，加载完成切换无跳变感
@ComponentV2
export struct BillListSkeleton {
  @Builder
  GroupSkeleton() {
    Column({ space: 12 }) {
      Row() {
        SkeletonBlock({ blockWidth: 84, blockHeight: 13 })
        Blank()
        SkeletonBlock({ blockWidth: 100, blockHeight: 13 })
      }
      .width('100%')
      Row({ space: 10 }) {
        SkeletonBlock({ blockWidth: 30, blockHeight: 15 })
        SkeletonBlock({ blockWidth: 110, blockHeight: 15 })
        Blank()
        SkeletonBlock({ blockWidth: 64, blockHeight: 15 })
      }
      .width('100%')
      Row({ space: 10 }) {
        SkeletonBlock({ blockWidth: 26, blockHeight: 15 })
        SkeletonBlock({ blockWidth: 140, blockHeight: 15 })
        Blank()
        SkeletonBlock({ blockWidth: 56, blockHeight: 15 })
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(18)
    .border({ width: 1, color: $r('app.color.border_color') })
  }

  build() {
    Column({ space: 12 }) {
      // 汇总卡占位
      Column({ space: 14 }) {
        Row() {
          SkeletonBlock({ blockWidth: 72, blockHeight: 13 })
          Blank()
          SkeletonBlock({ blockWidth: 96, blockHeight: 22 })
        }
        .width('100%')
        Divider()
          .color($r('app.color.border_color'))
        Row() {
          SkeletonBlock({ blockWidth: 48, blockHeight: 13 })
          Blank()
          SkeletonBlock({ blockWidth: 88, blockHeight: 15 })
        }
        .width('100%')
      }
      .width('100%')
      .padding(16)
      .backgroundColor($r('app.color.card_bg'))
      .borderRadius(18)
      .border({ width: 1, color: $r('app.color.border_color') })

      // 分组卡占位 × 2
      this.GroupSkeleton()
      this.GroupSkeleton()
    }
    .width('100%')
    .padding({ top: 8 })
  }
}

// 无数据空状态：圆形底图标 + 标题 + 副标题
@ComponentV2
export struct EmptyState {
  @Param emptyIcon: Resource = $r('sys.symbol.doc_text');
  @Param emptyTitle: string = '暂无数据';
  @Param emptySubtitle: string = '';
  @Param iconTint: ResourceColor = '#B2BEC3';

  build() {
    Column({ space: 10 }) {
      Stack() {
        Column()
          .width(84)
          .height(84)
          .borderRadius(42)
          .backgroundColor($r('app.color.category_btn_bg'))
        SymbolGlyph(this.emptyIcon)
          .fontSize(34)
          .fontColor([this.iconTint])
      }
      .margin({ bottom: 4 })

      Text(this.emptyTitle)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))

      if (this.emptySubtitle.length > 0) {
        Text(this.emptySubtitle)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
      }
    }
    .width('100%')
    .padding({ top: 48, bottom: 48 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: 18 }))
      .animation({ duration: 380, curve: Curve.EaseOut }))
  }
}
