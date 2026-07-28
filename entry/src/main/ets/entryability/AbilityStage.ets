import { AbilityStage } from '@kit.AbilityKit';
import { Configuration } from '@kit.AbilityKit';

export default class MyAbilityStage extends AbilityStage {
  onCreate(): void {
    // 获取当前颜色模式并存储到 AppStorage
    AppStorage.setOrCreate('currentColorMode', this.context.config.colorMode);
    console.info('✅ AbilityStage: 初始颜色模式已存储');
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    if (newConfig.colorMode !== undefined) {
      AppStorage.setOrCreate('currentColorMode', newConfig.colorMode);
      console.info('🔄 AbilityStage: 颜色模式已更新: ' + newConfig.colorMode);
    }
  }
}