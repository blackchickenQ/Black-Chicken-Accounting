import { vibrator } from '@kit.SensorServiceKit';
import { BusinessError } from '@kit.BasicServicesKit';

// 设置页「触感反馈」开关/强度的 AppStorage 键；hapticTick 内部读取，各组件无需传递状态
const HAPTIC_ENABLED_KEY: string = 'haptic_enabled';
const HAPTIC_INTENSITY_KEY: string = 'haptic_intensity';

// 文档推荐的通用触觉效果（HapticFeedback），同时作为强度三档的效果池（轻/中/强）
const TICK_EFFECT_CANDIDATES: string[] = ['haptic.effect.soft', 'haptic.effect.hard', 'haptic.effect.sharp'];

// 缓存查询结果，避免每次交互都同步查询
let cachedTickEffect: string | null = null;
let effectResolved: boolean = false;
let cachedHdHaptic: boolean | null = null;

export function isHapticEnabled(): boolean {
  return AppStorage.get<boolean>(HAPTIC_ENABLED_KEY) ?? true;
}

// 振动强度：VibratePreset.intensity 取值 (0,100]，默认 100（最大）
export function getHapticIntensity(): number {
  const value: number = AppStorage.get<number>(HAPTIC_INTENSITY_KEY) ?? 100;
  if (isNaN(value) || value < 1) {
    return 1;
  }
  if (value > 100) {
    return 100;
  }
  return Math.round(value);
}

function resolveTickEffect(): string | null {
  if (effectResolved) {
    return cachedTickEffect;
  }
  effectResolved = true;
  for (const effectId of TICK_EFFECT_CANDIDATES) {
    try {
      if (vibrator.isSupportEffectSync(effectId)) {
        cachedTickEffect = effectId;
        console.info(`[Haptics] 使用预置效果: ${effectId}`);
        return cachedTickEffect;
      }
    } catch (e) {
      console.error(`[Haptics] 查询效果支持失败: ${effectId}`, JSON.stringify(e));
    }
  }
  console.warn('[Haptics] 设备不支持预置触觉效果，退回时长振动');
  return null;
}

// 是否支持高清振动（决定 intensity 参数是否生效），缓存查询结果
function isHdHapticSupportedCached(): boolean {
  if (cachedHdHaptic === null) {
    try {
      cachedHdHaptic = vibrator.isHdHapticSupported();
    } catch (e) {
      console.error('[Haptics] 查询高清振动支持失败', JSON.stringify(e));
      cachedHdHaptic = false;
    }
    console.info(`[Haptics] 高清振动支持: ${cachedHdHaptic}`);
  }
  return cachedHdHaptic;
}

// 非高清振动设备：预置效果不支持 intensity 连续调节，
// 按强度档位映射不同效果（轻=soft 中=hard 强=sharp）
function effectForIntensityTier(intensity: number): string | null {
  const tierIndex: number = intensity < 40 ? 0 : (intensity < 70 ? 1 : 2);
  const tierEffect: string = TICK_EFFECT_CANDIDATES[tierIndex];
  try {
    if (vibrator.isSupportEffectSync(tierEffect)) {
      return tierEffect;
    }
  } catch (e) {
    console.error(`[Haptics] 查询档位效果支持失败: ${tierEffect}`, JSON.stringify(e));
  }
  // 档位效果不支持时退回任一受支持的预置效果
  return resolveTickEffect();
}

// 点击/切换类交互的轻触感反馈：短促一次，与系统触觉风格一致
export function hapticTick(): void {
  if (!isHapticEnabled()) {
    return;
  }
  try {
    const intensity: number = getHapticIntensity();
    const hdHaptic: boolean = isHdHapticSupportedCached();
    // 高清振动设备：预置效果 + intensity 连续调节；
    // 普通设备：按强度档位切换 soft/hard/sharp 三种效果
    const effectId: string | null = hdHaptic ? resolveTickEffect() : effectForIntensityTier(intensity);
    if (effectId !== null) {
      let preset: vibrator.VibratePreset = {
        type: 'preset',
        effectId: effectId,
        count: 1
      };
      if (hdHaptic) {
        preset.intensity = intensity;
      }
      vibrator.startVibration(preset, {
        usage: 'touch'
      }).then(() => {
        console.info(`[Haptics] 振动成功: ${effectId} intensity=${intensity} hd=${hdHaptic}`);
      }).catch((e: BusinessError) => {
        console.error(`[Haptics] 预置振动失败 code=${e.code} msg=${e.message}`);
        fallbackVibrate(intensity);
      });
    } else {
      fallbackVibrate(intensity);
    }
  } catch (e) {
    console.error('[Haptics] 振动调用异常', JSON.stringify(e));
  }
}

function fallbackVibrate(intensity: number): void {
  try {
    // 时长振动不支持强度参数，按强度比例缩短时长
    const duration: number = Math.max(8, Math.round(20 * intensity / 100));
    vibrator.startVibration({ type: 'time', duration: duration }, { usage: 'touch' })
      .then(() => {
        console.info(`[Haptics] 时长振动成功 duration=${duration}`);
      })
      .catch((e: BusinessError) => {
        console.error(`[Haptics] 时长振动失败 code=${e.code} msg=${e.message}`);
      });
  } catch (e) {
    console.error('[Haptics] 时长振动调用异常', JSON.stringify(e));
  }
}
