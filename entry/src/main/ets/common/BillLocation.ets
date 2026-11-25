// ---------- 消费地点记录：定位 + 逆地理编码（Location Kit，端侧） ----------
// 记一笔时可选「记地点」：申请定位权限 → 获取当前经纬度 → 逆地理编码为可读地名（市/区/路）
import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { geoLocationManager } from '@kit.LocationKit';

// 申请精确定位+模糊定位权限（user_grant，需在 module.json5 声明并配 reason/usedScene）
export async function requestLocationPermission(context: common.UIAbilityContext): Promise<boolean> {
  try {
    const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    const result = await atManager.requestPermissionsFromUser(context,
      ['ohos.permission.LOCATION', 'ohos.permission.APPROXIMATELY_LOCATION']);
    if (result.authResults.length < 2) {
      return false;
    }
    return result.authResults[0] === 0 && result.authResults[1] === 0;
  } catch (e) {
    console.error('申请定位权限失败: ' + JSON.stringify(e));
    return false;
  }
}

// 逆地理编码结果的可读地名：市 + 区/县 + 路，全为空时回退到详细地址
function composeLocationName(addr: geoLocationManager.GeoAddress): string {
  const parts: string[] = [];
  if (addr.locality !== undefined && addr.locality.length > 0) {
    parts.push(addr.locality);
  }
  if (addr.subLocality !== undefined && addr.subLocality.length > 0) {
    parts.push(addr.subLocality);
  }
  if (addr.roadName !== undefined && addr.roadName.length > 0) {
    parts.push(addr.roadName);
  }
  if (parts.length > 0) {
    return parts.join('');
  }
  if (addr.placeName !== undefined && addr.placeName.length > 0) {
    return addr.placeName;
  }
  return '';
}

// 获取当前地点的可读名称（如「南京市玄武区中山路」）；失败返回 null（含未授权/未开定位开关）
export async function getCurrentLocationName(context: common.UIAbilityContext): Promise<string | null> {
  // 位置服务总开关未开时直接失败，避免长时间等待定位超时
  try {
    if (!geoLocationManager.isLocationEnabled()) {
      console.error('位置服务未开启');
      return null;
    }
  } catch (e) {
    console.error('检查位置服务状态失败: ' + JSON.stringify(e));
  }
  try {
    const location: geoLocationManager.Location =
      await geoLocationManager.getCurrentLocation();
    const request: geoLocationManager.ReverseGeoCodeRequest = {
      latitude: location.latitude,
      longitude: location.longitude,
      maxItems: 1
    };
    const addresses: Array<geoLocationManager.GeoAddress> =
      await geoLocationManager.getAddressesFromLocation(request);
    if (addresses.length === 0) {
      return null;
    }
    const name: string = composeLocationName(addresses[0]);
    return name.length > 0 ? name : null;
  } catch (e) {
    const err = e as BusinessError;
    console.error('获取当前位置失败: code=' + err.code + ', message=' + err.message);
    return null;
  }
}
