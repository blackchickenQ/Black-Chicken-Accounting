import { sensor } from '@kit.SensorServiceKit';

// 摇一摇检测：订阅加速度传感器，相邻两次采样三轴加速度差值之和超过阈值视为一次摇动
// 加速度传感器为普通权限（module.json5 声明 ohos.permission.ACCELEROMETER 即可），无需运行时申请
export class ShakeHelper {
  private lastX: number = 0;
  private lastY: number = 0;
  private lastZ: number = 0;
  private hasLast: boolean = false;
  private lastTriggerMs: number = 0;
  private listening: boolean = false;
  // 相邻采样三轴加速度差值之和阈值（m/s²）：日常拿放手机约 10~15，用力摇动可超过 30
  private static readonly TRIGGER_DELTA: number = 26;
  // 两次摇动触发的最小间隔（毫秒），避免一次连续摇动反复触发
  private static readonly MIN_INTERVAL_MS: number = 2000;

  // 开始监听摇动；重复调用安全（已监听时忽略）
  start(onShake: () => void): void {
    if (this.listening) {
      return;
    }
    this.listening = true;
    this.hasLast = false;
    this.lastTriggerMs = 0;
    try {
      sensor.on(sensor.SensorId.ACCELEROMETER, (data: sensor.AccelerometerResponse) => {
        if (!this.listening) {
          return;
        }
        if (!this.hasLast) {
          this.lastX = data.x;
          this.lastY = data.y;
          this.lastZ = data.z;
          this.hasLast = true;
          return;
        }
        const dx: number = Math.abs(data.x - this.lastX);
        const dy: number = Math.abs(data.y - this.lastY);
        const dz: number = Math.abs(data.z - this.lastZ);
        this.lastX = data.x;
        this.lastY = data.y;
        this.lastZ = data.z;
        const now: number = Date.now();
        if (dx + dy + dz > ShakeHelper.TRIGGER_DELTA &&
          now - this.lastTriggerMs > ShakeHelper.MIN_INTERVAL_MS) {
          this.lastTriggerMs = now;
          onShake();
        }
      });
    } catch (e) {
      // 设备不支持加速度传感器等场景：静默失败，不开启功能
      this.listening = false;
    }
  }

  // 停止监听并释放传感器资源；未监听时调用安全
  stop(): void {
    if (!this.listening) {
      return;
    }
    this.listening = false;
    this.hasLast = false;
    try {
      sensor.off(sensor.SensorId.ACCELEROMETER);
    } catch (e) {
      // 忽略关闭失败
    }
  }
}
