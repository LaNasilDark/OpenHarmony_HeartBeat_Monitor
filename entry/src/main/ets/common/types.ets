import wifi from '@ohos.wifi';

// 基础类型定义
export interface DeviceInfo {
  cpuLoad: number;
  memInfo: MemObjectType;
  disk: DiskObjectType;
  net: NetObjectType;
  mac: string;
  ipAddress: string;
  upTime: number;
  time: number;
  sn: string;
  cpuTemperature: number;
  agentVersion: string;
}

export interface UpdateTargetIpData {
  targetIp: string;
}

export interface RemoteCommand {
  type: 'configure_wifi' | 'configure_ethernet' | 'forget_wifi' | 'restart_monitor' | 'update_target_ip';
  data?: WifiConfigData | EthernetConfigData | UpdateTargetIpData;
  timestamp?: number;
}

export interface CommandResponse {
  success: boolean;
  message: string;
  timestamp?: number;
}

export interface WifiConfigData {
  ssid: string;
  password: string;
  ipAddress: string;
  gateway: string;
  dns: string;
  bssid?: string;
}

export interface EthernetConfigData {
  ipAddress: string;
  gateway: string;
  netmask: string;
  dns: string;
}

export interface WifiConfig {
  ssid: string;
  bssid: string;
  preSharedKey: string;
  isHiddenSsid: boolean;
  securityType: wifi.WifiSecurityType;
  ipAddress: string;
  gateway: string;
  dns: string;
}

export interface EthernetConfig {
  ipAddress: string;
  gateway: string;
  netmask: string;
  dns: string;
}

export interface NetObjectType {
  netInterface: string;
  txByte: number;
  txRate: number;
  rxByte: number;
  rxRate: number;
  unit: string;
}

export interface DiskObjectType {
  mounted: string;
  available: number;
  total: number;
  percent: number;
  used: number;
  unit: string;
}

export interface MemObjectType {
  memTotal: number;
  memLoad: number;
  memUsed: number;
  memAvailable: number;
  unit: string;
}

export interface ParsedNetStats {
  rxBytes: number;
  txBytes: number;
}

export interface MemInfoParsed {
  memTotal: number;
  memAvailable: number;
}

export interface CpuStat {
  idle: number;
  total: number;
}

export interface ErrorLike {
  code?: number;
  message?: string;
}

export interface MonitorConfig {
  targetUdpIp: string;
  targetUdpPort: number;
  localUdpPort: number;
  agentVersion: string;
  networkInterface: string;
  diskMountPath: string;
  collectInterval: number;
  logCallback?: (message: string) => void;
}

export interface DeviceDataCache {
  cpuTemp: string;
  sn: string;
  time: string;
  mac: string;
  upTime: string;
  localIp: string;
  net: NetObjectType;
  disk: DiskObjectType;
  cpuLoad: string;
  mem: MemObjectType;
}

// 日志回调函数类型
export type LogFunction = (message: string, level?: 'info' | 'warn' | 'error') => void;
