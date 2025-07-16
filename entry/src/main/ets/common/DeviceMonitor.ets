import hilog from '@ohos.hilog';
import socket from '@ohos.net.socket';
import util from '@ohos.util';
import { SystemInfoCollector } from './SystemInfoCollector';
import { NetworkManager } from './NetworkManager';
import {
  DeviceInfo,
  WifiConfig,
  EthernetConfig,
  MonitorConfig,
  DeviceDataCache,
  ErrorLike,
  MemObjectType,
  DiskObjectType,
  NetObjectType
} from './types';

// 重新导出类型定义，保持向后兼容性
export { 
  DeviceInfo, 
  WifiConfig, 
  EthernetConfig, 
  NetObjectType, 
  DiskObjectType, 
  MemObjectType, 
  MonitorConfig, 
  DeviceDataCache 
} from './types';

export class DeviceMonitor {
  private static readonly TAG: string = 'DeviceMonitor';
  private static readonly DOMAIN: number = 0x0001;
  private static readonly INTERVAL: number = 3000;
  private static readonly TIME_OUT: number = 10000;

  private config: MonitorConfig;
  private udpSocket: socket.UDPSocket;
  private udpSocketBound: boolean = false;
  private sendIntervalId: number = -1;
  private isRunning: boolean = false;
  private intervalId: number | null = null;
  private timeoutId: number | null = null;

  // 设备信息缓存
  private deviceData: DeviceDataCache;

  // 组合新的服务类
  private infoCollector: SystemInfoCollector;
  private networkManager: NetworkManager;

  constructor(config: MonitorConfig) {
    this.config = config;
    this.udpSocket = socket.constructUDPSocketInstance();

    // 绑定 this 上下文，以便作为回调传递
    const boundLog: (message: string, level?: 'info' | 'warn' | 'error') => void = this.log.bind(this);
    const boundFormatError: (error: Object) => string = this.formatError.bind(this);

    // 初始化服务类
    this.infoCollector = new SystemInfoCollector(boundLog, boundFormatError);
    this.networkManager = new NetworkManager(boundLog, boundFormatError);

    // 初始化设备数据
    this.deviceData = {
      cpuTemp: 'Loading...',
      sn: 'Loading...',
      time: 'Loading...',
      mac: 'Loading...',
      upTime: 'Loading...',
      localIp: '0.0.0.0',
      net: {
        netInterface: this.config.networkInterface,
        txByte: -1,
        txRate: -1,
        rxByte: -1,
        rxRate: -1,
        unit: 'Bytes/s'
      },
      disk: {
        mounted: this.config.diskMountPath,
        available: -1,
        total: -1,
        percent: -1,
        used: -1,
        unit: 'Byte'
      },
      cpuLoad: 'Loading...',
      mem: {
        memTotal: -1,
        memLoad: -1,
        memUsed: -1,
        memAvailable: -1,
        unit: 'Byte'
      }
    };
  }

  // 日志记录工具
  private log(message: string, level: 'info' | 'warn' | 'error' = 'info'): void {
    // 优先使用回调将日志发送到UI
    if (this.config.logCallback) {
      this.config.logCallback(message);
    }

    // 同时记录到 hilog
    switch (level) {
      case 'info':
        hilog.info(DeviceMonitor.DOMAIN, DeviceMonitor.TAG, message);
        break;
      case 'warn':
        hilog.warn(DeviceMonitor.DOMAIN, DeviceMonitor.TAG, message);
        break;
      case 'error':
        hilog.error(DeviceMonitor.DOMAIN, DeviceMonitor.TAG, message);
        break;
    }
  }

  // 统一的错误格式化方法
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  private formatError(error: Object): string {
    // 使用属性检查替代 instanceof BusinessError，因为 BusinessError 是一个接口
    if (typeof error === 'object' && error !== null) {
      // ArkTS 不支持 'in' 操作符或对象字面量类型，所以我们使用一个接口
      const err = error as ErrorLike;
      if (err.code !== undefined && err.message !== undefined) {
        return `BusinessError: code=${err.code}, message=${err.message}`;
      }
    }
    if (error instanceof Error) {
      return `Error: ${error.message}`;
    }
    return JSON.stringify(error);
  }

  // 收集所有设备信息
  public async collectDeviceInfo(): Promise<DeviceInfo> {
    try {
      const collector = this.infoCollector;
      const iface = this.config.networkInterface;

      // 并行收集所有设备信息，提高效率
      const results = await Promise.all([
        collector.fetchCpuTemperature(),
        collector.fetchMacAddress(iface),
        collector.fetchSN(),
        collector.fetchSystemTime(),
        collector.fetchUptime(),
        collector.fetchLocalIp(iface),
        collector.getCpuPercent(),
        collector.fetchMemInfo(),
        collector.fetchDiskInfo(this.config.diskMountPath),
        collector.fetchNetworkInfo(iface)
      ]);

      const cpuTemp = results[0] as number | string;
      const mac = results[1] as string;
      const sn = results[2] as string;
      const time = results[3] as number;
      const upTime = results[4] as number | null;
      const localIp = results[5] as string;
      const cpuLoad = results[6] as number;
      const memInfo = results[7] as MemObjectType;
      const diskInfo = results[8] as DiskObjectType;
      const netInfo = results[9] as NetObjectType;

      // 更新内部缓存数据
      this.deviceData = {
        cpuTemp: cpuTemp.toString(),
        mac: mac === 'N/A' ? 'NoMAC' : mac,
        sn: sn,
        time: time.toString(),
        upTime: upTime?.toString() || 'ErrorFetchingUptime',
        localIp: localIp,
        cpuLoad: cpuLoad.toString(),
        mem: memInfo,
        disk: diskInfo,
        net: netInfo
      };

      // 构建并返回设备信息对象
      const deviceInfo: DeviceInfo = {
        cpuLoad: cpuLoad,
        memInfo: memInfo,
        disk: diskInfo,
        net: netInfo,
        mac: this.deviceData.mac,
        ipAddress: localIp,
        upTime: upTime || -1, // 如果获取失败则返回-1
        time: time,
        sn: sn,
        cpuTemperature: typeof cpuTemp === 'number' ? cpuTemp : -1, // 如果获取失败则返回-1
        agentVersion: this.config.agentVersion
      };

      this.log('Device info collected successfully');
      return deviceInfo;
    } catch (error) {
      this.log(`Failed to collect device info: ${this.formatError(error)}`, 'error');
      throw new Error(`Failed to collect device info: ${this.formatError(error)}`);
    }
  }

  // 计算校验和
  private calculateChecksum(data: Uint8Array): number {
    let sum = 0;
    const len = data.length;
    const n = len % 2;

    for (let i = 0; i < len - n; i += 2) {
      sum += data[i] + (data[i + 1] << 8);
    }

    if (n) {
      sum += data[len - 1];
    }

    while (sum >> 16) {
      sum = (sum & 0xFFFF) + (sum >> 16);
    }

    return ~sum & 0xFFFF;
  }

  // 发送设备信息via UDP
  public async sendDeviceInfoViaUDP(): Promise<void> {
    try {
      const deviceInfo = await this.collectDeviceInfo();
      const messageString = JSON.stringify(deviceInfo);
      const encoder = new util.TextEncoder();
      const messageBytes = encoder.encode(messageString);

      // 计算校验和
      const checksum = this.calculateChecksum(messageBytes);
      const checksumBuffer = new ArrayBuffer(2);
      const view = new DataView(checksumBuffer);
      view.setUint16(0, checksum, false);
      const checksumBytes = new Uint8Array(checksumBuffer);

      // 构建数据包
      const packetBytes = new Uint8Array(checksumBytes.length + messageBytes.length);
      packetBytes.set(checksumBytes, 0);
      packetBytes.set(messageBytes, checksumBytes.length);

      const remoteAddress: socket.NetAddress = {
        address: this.config.targetUdpIp,
        port: this.config.targetUdpPort,
        family: 0
      };

      await this.udpSocket.send({
        data: packetBytes.buffer,
        address: remoteAddress
      });

      this.log(`Device info sent to ${this.config.targetUdpIp}:${this.config.targetUdpPort}`);
    } catch (error) {
      this.log(`Failed to send device info via UDP: ${this.formatError(error)}`, 'error');
      throw new Error(`Failed to send device info via UDP: ${this.formatError(error)}`);
    }
  }

  // =================================================================
  // 网络管理委托方法
  // =================================================================

  // 自动检测网络接口
  public async autoDetectNetworkInterface(): Promise<void> {
    this.config.networkInterface = await this.networkManager.autoDetectNetworkInterface();
  }

  // 配置网络 (委托给 NetworkManager)
  public async configureNetwork(mode: number, ethConfig?: EthernetConfig, wifiConfig?: WifiConfig): Promise<void> {
    await this.networkManager.configureNetwork(mode, ethConfig, wifiConfig);
  }

  // 忘记所有Wi-Fi网络 (委托给 NetworkManager)
  public async forgetAllWifiNetworks(): Promise<void> {
    await this.networkManager.forgetAllWifiNetworks();
  }

  // 启动监控服务
  public async startMonitoring(): Promise<void> {
    if (this.isRunning) {
      this.log('Monitor is already running', 'warn');
      return;
    }

    try {
      // 绑定UDP套接字
      if (!this.udpSocketBound) {
        await this.udpSocket.bind({
          address: '0.0.0.0',
          port: this.config.localUdpPort,
          family: 0
        });
        this.udpSocketBound = true;
        this.log(`UDP socket bound to port ${this.config.localUdpPort}`);
      }

      // 发送初始设备信息
      await this.sendDeviceInfoViaUDP();

      // 启动定期发送
      this.sendIntervalId = setInterval(async () => {
        try {
          await this.sendDeviceInfoViaUDP();
        } catch (e) {
          this.log(`Error in periodic UDP send: ${this.formatError(e)}`, 'error');
        }
      }, this.config.collectInterval);

      this.isRunning = true;
      this.log('Device monitoring started successfully');
    } catch (error) {
      this.log(`Failed to start monitoring: ${this.formatError(error)}`, 'error');
      throw new Error(`Failed to start monitoring: ${this.formatError(error)}`);
    }
  }

  // 停止监控服务
  public stopMonitoring(): void {
    if (!this.isRunning) {
      this.log('Monitor is not running', 'warn');
      return;
    }

    try {
      // 停止定时器
      if (this.sendIntervalId !== -1) {
        clearInterval(this.sendIntervalId);
        this.sendIntervalId = -1;
      }

      this.isRunning = false;
      this.log('Device monitoring stopped successfully');
    } catch (error) {
      this.log(`Failed to stop monitoring: ${this.formatError(error)}`, 'error');
    }
  }

  // 检查监控状态
  public isMonitoringRunning(): boolean {
    return this.isRunning;
  }

  // 获取当前设备数据快照
  public getDeviceDataSnapshot(): DeviceDataCache {
    // Manually copy properties to avoid Object.assign
    const snapshot: DeviceDataCache = {
      cpuTemp: this.deviceData.cpuTemp,
      sn: this.deviceData.sn,
      time: this.deviceData.time,
      mac: this.deviceData.mac,
      upTime: this.deviceData.upTime,
      localIp: this.deviceData.localIp,
      net: this.deviceData.net,
      disk: this.deviceData.disk,
      cpuLoad: this.deviceData.cpuLoad,
      mem: this.deviceData.mem
    };
    return snapshot;
  }

  // 更新配置
  public updateConfig(newConfig: Partial<MonitorConfig>): void {
    // Manually update properties to avoid Object.assign
    if (newConfig.targetUdpIp !== undefined) this.config.targetUdpIp = newConfig.targetUdpIp;
    if (newConfig.targetUdpPort !== undefined) this.config.targetUdpPort = newConfig.targetUdpPort;
    if (newConfig.localUdpPort !== undefined) this.config.localUdpPort = newConfig.localUdpPort;
    if (newConfig.agentVersion !== undefined) this.config.agentVersion = newConfig.agentVersion;
    if (newConfig.networkInterface !== undefined) this.config.networkInterface = newConfig.networkInterface;
    if (newConfig.diskMountPath !== undefined) this.config.diskMountPath = newConfig.diskMountPath;
    if (newConfig.collectInterval !== undefined) this.config.collectInterval = newConfig.collectInterval;
    if (newConfig.logCallback !== undefined) this.config.logCallback = newConfig.logCallback;
    this.log('Monitor configuration updated');
  }

  // 清理资源
  public dispose(): void {
    this.stopMonitoring();
    if (this.udpSocketBound) {
      this.udpSocket.close().catch((e: Object) => {
        this.log(`Error closing UDP socket: ${this.formatError(e)}`, 'error');
      });
      this.udpSocketBound = false;
    }
  }

}