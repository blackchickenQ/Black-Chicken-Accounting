import { AbilityStage, ConfigurationConstant } from '@kit.AbilityKit';
import { Configuration } from '@kit.AbilityKit';
import { ColorModeSignals } from '../common/V2Signals';

export default class MyAbilityStage extends AbilityStage {
  onCreate(): void {
    // 获取当前颜色模式并存储到 AppStorage（V1/V2 双写：V2 侧供已迁移 @ComponentV2 弹层组件订阅）
    const colorMode: ConfigurationConstant.ColorMode =
      this.context.config.colorMode ?? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    AppStorage.setOrCreate('currentColorMode', colorMode);
    ColorModeSignals.connect().mode = colorMode;
    console.info('✅ AbilityStage: 初始颜色模式已存储');
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    if (newConfig.colorMode !== undefined) {
      AppStorage.setOrCreate('currentColorMode', newConfig.colorMode);
      ColorModeSignals.connect().mode = newConfig.colorMode;
      console.info('🔄 AbilityStage: 颜色模式已更新: ' + newConfig.colorMode);
    }
  }
}