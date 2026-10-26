// ---------- V2 全局信号包装类（AppStorageV2 桥接层） ----------
// AppStorageV2 仅支持 class 类型（不支持 string/number/boolean 等基本类型），
// 全局信号统一以 @ObservedV2 包装类接入，通过 AppStorageV2.connect(type, key, creator) 共享。
// 迁移期与 V1 AppStorage 双写：V1 侧供未迁移 @Component（@StorageProp）使用，
// V2 侧供已迁移 @ComponentV2（@Local + connect）使用；Index 主 struct（批次E）迁移完成后可移除 V1 侧。
import { AppStorageV2 } from '@kit.ArkUI';

// 设备/布局信号：宽屏断点 + 沉浸式安全区高度（EntryAbility 写入，各页面读取避让）
@ObservedV2
export class DeviceSignals {
  @Trace isWideScreen: boolean = false;
  @Trace statusBarVp: number = 46;
  @Trace navBarVp: number = 28;

  static connect(): DeviceSignals {
    return AppStorageV2.connect(DeviceSignals, 'deviceSignals', () => new DeviceSignals())!;
  }
}

// 品牌色信号：applyBrandTheme 写入（AppTheme.ets），各组件读取实现全局换色联动
@ObservedV2
export class BrandSignals {
  @Trace main: string = '#4E6EF2';
  @Trace light: string = '#7B93FF';
  @Trace deep: string = '#3A55E0';
  @Trace tint: string = '#EEF1FE';

  static connect(): BrandSignals {
    return AppStorageV2.connect(BrandSignals, 'brandSignals', () => new BrandSignals())!;
  }
}
