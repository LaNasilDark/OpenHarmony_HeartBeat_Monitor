import hilog from '@ohos.hilog';
import socket from '@ohos.net.socket';
import wifi from '@ohos.wifi';
import systemDateTime from '@ohos.systemDateTime';
import util from '@ohos.util';
import { fileIo as fs } from '@kit.CoreFileKit';
import ethernet from '@ohos.net.ethernet';
import { process } from '@kit.ArkTS';
import storageStatistics from '@ohos.file.storageStatistics'
import connection from '@ohos.net.connection';

// 接口定义
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

interface ParsedNetStats {
  rxBytes: number;
  txBytes: number;
}

interface MemInfoParsed {
  memTotal: number;
  memAvailable: number;
}

interface CpuStat {
  idle: number;
  total: number;
}

interface ErrorLike {
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
  logCallback?: (message: string) => void; // 新增日志回调
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

export class DeviceMonitor {
  private static readonly TAG: string = 'DeviceMonitor';
  private static readonly DOMAIN: number = 0x0001;

  // 将系统文件路径定义为常量
  private static readonly FILE_PATH_MEM_INFO = '/proc/meminfo';
  private static readonly FILE_PATH_PROC_STAT = '/proc/stat';
  private static readonly FILE_PATH_NET_DEV = '/proc/net/dev';
  private static readonly FILE_PATH_SERIAL_NUMBER = '/proc/device-tree/serial-number';
  private static readonly FILE_PATH_CPU_TEMP = '/sys/class/thermal/thermal_zone0/temp';
  private static readonly FILE_PATH_MAC_ADDRESS_TPL = '/sys/class/net/{iface}/address';
  private static readonly FILE_PATH_DHCP_CACHE = "/data/service/el1/public/dhcp/dhcp_cache.conf";

  private config: MonitorConfig;
  private udpSocket: socket.UDPSocket;
  private udpSocketBound: boolean = false;
  private sendIntervalId: number = -1;
  private isRunning: boolean = false;

  // 设备信息缓存
  private deviceData: DeviceDataCache;

  constructor(config: MonitorConfig) {
    this.config = config;
    this.udpSocket = socket.constructUDPSocketInstance();

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

  // 系统文件读取工具方法
  private async readSystemFileContent(filePath: string): Promise<string> {
    let file: fs.File | null = null;
    try {
      file = await fs.open(filePath, fs.OpenMode.READ_ONLY);
      const buffer = new ArrayBuffer(1024);
      const bytesRead = await fs.read(file.fd, buffer);
      const decoder = new util.TextDecoder('utf-8');
      const content = decoder.decode(new Uint8Array(buffer, 0, bytesRead));
      return content.trim();
    } catch (error) {
      this.log(`Failed to read system file at ${filePath}: ${this.formatError(error)}`, 'error');
      return 'N/A';
    } finally {
      if (file) {
        try {
          await fs.close(file.fd);
        } catch (closeError) {
          this.log(`Failed to close file ${filePath}: ${this.formatError(closeError)}`, 'error');
        }
      }
    }
  }

  // 内存信息解析
  private parseMemInfo(content: string): MemInfoParsed {
    const lines = content.split('\n');
    let memTotal = 0;
    let memAvailable = 0;

    for (const line of lines) {
      const parts = line.split(/\s+/);
      if (parts.length >= 2) {
        const value = parseInt(parts[1], 10);
        if (!isNaN(value)) {
          if (line.startsWith('MemTotal:')) {
            memTotal = value * 1024;
          } else if (line.startsWith('MemAvailable:')) {
            memAvailable = value * 1024;
          }
        }
      }
    }
    return { memTotal, memAvailable };
  }

  // 获取内存信息
  private async fetchMemInfo(): Promise<MemObjectType> {
    const defaultErrorMemInfo: MemObjectType = {
      memTotal: 0,
      memLoad: 0,
      memUsed: 0,
      memAvailable: 0,
      unit: 'Byte'
    };

    try {
      const content = await this.readSystemFileContent(DeviceMonitor.FILE_PATH_MEM_INFO);
      if (content === 'N/A') {
        this.log("Failed to read meminfo.", 'error');
        return defaultErrorMemInfo;
      }

      const parsedInfo = this.parseMemInfo(content);
      const memTotal = parsedInfo.memTotal;
      const memAvailable = parsedInfo.memAvailable;

      if (memTotal > 0) {
        const memUsed = memTotal - memAvailable;
        const memLoad = (memUsed / memTotal) * 100;

        return {
          memTotal: memTotal,
          memLoad: parseFloat(memLoad.toFixed(1)),
          memUsed: memUsed,
          memAvailable: memAvailable,
          unit: 'Byte'
        };
      }
      this.log("Parsed MemTotal is 0.", 'warn');
      return defaultErrorMemInfo;

    } catch (error) {
      this.log(`Failed to fetch mem info: ${this.formatError(error)}`, 'error');
      return defaultErrorMemInfo;
    }
  }

  // CPU统计解析
  private parseCpuStat(stat: string): CpuStat {
    const lines = stat.split('\n');
    const cpuLine = lines[0];
    const parts = cpuLine.trim().split(/\s+/);
    const nums = parts.slice(1).map(v => parseInt(v, 10));
    const idle = nums[3] + (nums[4] || 0);
    const total = nums.reduce((a, b) => a + b, 0);
    return { idle, total };
  }

  // 获取CPU使用率
  private async getCpuPercent(interval: number = 1000): Promise<number> {
    const stat1 = await this.readSystemFileContent(DeviceMonitor.FILE_PATH_PROC_STAT);
    const cpu1 = this.parseCpuStat(stat1);

    await new Promise<void>(resolve => setTimeout(resolve, interval));

    const stat2 = await this.readSystemFileContent(DeviceMonitor.FILE_PATH_PROC_STAT);
    const cpu2 = this.parseCpuStat(stat2);

    const idleDelta = cpu2.idle - cpu1.idle;
    const totalDelta = cpu2.total - cpu1.total;

    if (totalDelta <= 0) {
      return 0;
    }
    const usage = (1 - idleDelta / totalDelta) * 100;
    return Number(usage.toFixed(1));
  }

  // 获取磁盘信息
  private async fetchDiskInfo(mountPath: string): Promise<DiskObjectType> {
    const defaultErrorDiskInfo: DiskObjectType = {
      mounted: mountPath,
      available: -1,
      total: -1,
      percent: -1,
      used: -1,
      unit: 'Byte'
    };

    try {
      const totalBytesNum: number = await storageStatistics.getTotalSize()
      const availableBytesNum: number = await storageStatistics.getFreeSize()

      const totalBytes = totalBytesNum;
      const availableBytes = availableBytesNum;
      const usedBytes = totalBytes - availableBytes;
      const percentNum = usedBytes > 0 && totalBytes > 0 ? Math.floor((usedBytes / totalBytes) * 100) : 0;

      return {
        mounted: mountPath,
        available: availableBytes,
        total: totalBytes,
        percent: percentNum,
        used: usedBytes,
        unit: 'Byte'
      };
    } catch (error) {
      this.log(`Failed to fetch disk info for ${mountPath}: ${this.formatError(error)}`, 'error');
      return defaultErrorDiskInfo;
    }
  }

  // 解析网络设备内容
  private parseNetDevContent(content: string, interfaceName: string): ParsedNetStats | null {
    try {
      const lines = content.split('\n');
      for (let i = 2; i < lines.length; i++) {
        const line = lines[i].trim();
        if (line.startsWith(interfaceName + ':')) {
          const parts = line.substring(line.indexOf(':') + 1).trim().split(/\s+/);
          if (parts.length >= 10) {
            const rxBytes = parseInt(parts[0], 10);
            const txBytes = parseInt(parts[8], 10);

            if (!isNaN(rxBytes) && !isNaN(txBytes)) {
              return { rxBytes, txBytes };
            }
          }
        }
      }
      this.log(`Interface ${interfaceName} not found in /proc/net/dev.`, 'warn');
      return null;
    } catch (e) {
      this.log(`Error parsing /proc/net/dev: ${this.formatError(e)}`, 'error');
      return null;
    }
  }

  // 获取网络信息
  private async fetchNetworkInfo(interfaceName: string): Promise<NetObjectType> {
    const defaultErrorNetInfo: NetObjectType = {
      netInterface: interfaceName,
      txByte: -1,
      txRate: -1,
      rxByte: -1,
      rxRate: -1,
      unit: 'Bytes/s'
    };

    try {
      const stats1Content = await this.readSystemFileContent(DeviceMonitor.FILE_PATH_NET_DEV);
      if (stats1Content === 'N/A') {
        return defaultErrorNetInfo;
      }

      const initialStats = this.parseNetDevContent(stats1Content, interfaceName);
      if (!initialStats) {
        return defaultErrorNetInfo;
      }

      await new Promise<void>(resolve => setTimeout(resolve, 1000));

      const stats2Content = await this.readSystemFileContent(DeviceMonitor.FILE_PATH_NET_DEV);
      if (stats2Content === 'N/A') {
        return defaultErrorNetInfo;
      }

      const finalStats = this.parseNetDevContent(stats2Content, interfaceName);
      if (!finalStats) {
        return defaultErrorNetInfo;
      }

      const deltaRxBytes = finalStats.rxBytes - initialStats.rxBytes;
      const deltaTxBytes = finalStats.txBytes - initialStats.txBytes;
      const rxRate = Math.max(0, deltaRxBytes);
      const txRate = Math.max(0, deltaTxBytes);

      return {
        netInterface: interfaceName,
        rxByte: finalStats.rxBytes,
        txByte: finalStats.txBytes,
        rxRate: rxRate,
        txRate: txRate,
        unit: 'Bytes/s'
      };
    } catch (error) {
      this.log(`Exception in fetchNetworkInfo: ${this.formatError(error)}`, 'error');
      return defaultErrorNetInfo;
    }
  }

  // 获取系统运行时间
  private async fetchUptime(): Promise<number | null> {
    try {
      const uptimeSeconds = process.uptime();
      if (!isNaN(uptimeSeconds)) {
        const upTimeDays = uptimeSeconds / 86400;
        return Number(upTimeDays.toFixed(2));
      }
      return null;
    } catch (e) {
      this.log(`Exception in fetchUptime: ${this.formatError(e)}`, 'error');
      return null;
    }
  }

  // 获取MAC地址
  private async fetchMacAddress(): Promise<string> {
    const macFilePath = DeviceMonitor.FILE_PATH_MAC_ADDRESS_TPL.replace('{iface}', this.config.networkInterface);
    return await this.readSystemFileContent(macFilePath);
  }

  // 获取系统时间
  private async fetchSystemTime(): Promise<number> {
    const currentTime = await systemDateTime.getCurrentTime(true);
    return currentTime / 1_000_000_000;
  }

  // 获取CPU温度
  private async fetchCpuTemperature(): Promise<number | string> {
    const tempStr = await this.readSystemFileContent(DeviceMonitor.FILE_PATH_CPU_TEMP);
    if (tempStr !== 'N/A' && tempStr !== 'Loading...') {
      const numericTemp = parseFloat(tempStr);
      if (!isNaN(numericTemp)) {
        return parseFloat((numericTemp / 1000).toFixed(1));
      }
    }
    return tempStr;
  }

  // 获取本地IP地址
  private async fetchLocalIp(): Promise<string> {
    const defaultIp = "0.0.0.0";
    try {
      const defaultNet = await connection.getDefaultNet();
      if (defaultNet) {
        const netCaps = await connection.getNetCapabilities(defaultNet);
        if (netCaps.bearerTypes.includes(connection.NetBearType.BEARER_WIFI)) {
          try {
            const wifiInfo = wifi.getIpInfo();
            if (wifiInfo && wifiInfo.ipAddress) {
              return this.manualIntToIp(wifiInfo.ipAddress);
            }
          } catch (e) {
            this.log(`Error fetching WiFi info: ${this.formatError(e)}`, 'error');
          }
        } else if (netCaps.bearerTypes.includes(connection.NetBearType.BEARER_ETHERNET)) {
          try {
            const ifaceConfig = await ethernet.getIfaceConfig(this.config.networkInterface);
            if (ifaceConfig && ifaceConfig.ipAddr) {
              this.log(`Ethernet IP found: ${ifaceConfig.ipAddr}`);
              return ifaceConfig.ipAddr;
            }
          } catch (error) {
            this.log(`getIfaceConfig promise error = ${this.formatError(error)}`, 'error');
          }
        }
      } else {
        this.log('No default network found', 'warn');
      }
    } catch (e) {
      this.log(`Error fetching default network: ${this.formatError(e)}`, 'error');
    }
    this.log('Could not determine IP. Returning default.', 'warn');
    return defaultIp;
  }

  // 获取设备序列号
  private async fetchSN(): Promise<string> {
    return await this.readSystemFileContent(DeviceMonitor.FILE_PATH_SERIAL_NUMBER);
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

  // 收集所有设备信息
  public async collectDeviceInfo(): Promise<DeviceInfo> {
    try {
      // 并行收集所有设备信息，提高效率
      const results = await Promise.all([
        this.fetchCpuTemperature(),
        this.fetchMacAddress(),
        this.fetchSN(),
        this.fetchSystemTime(),
        this.fetchUptime(),
        this.fetchLocalIp(),
        this.getCpuPercent(),
        this.fetchMemInfo(),
        this.fetchDiskInfo(this.config.diskMountPath),
        this.fetchNetworkInfo(this.config.networkInterface)
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

  // =================================================================
  // 新增：网络管理和设备控制方法
  // =================================================================

  // 手动实现 IP 字符串到整数的转换
  private manualIpToInt(ip: string): number {
    const parts = ip.split('.').map(part => parseInt(part, 10));
    if (parts.length !== 4 || parts.some(isNaN)) {
      return 0; // Invalid format
    }
    return ((parts[3] << 24) | (parts[2] << 16) | (parts[1] << 8) | parts[0]) >>> 0;
  }

  // 手动实现整数到 IP 字符串的转换
  private manualIntToIp(ipInt: number): string {
    const part1 = ipInt & 255;
    const part2 = (ipInt >> 8) & 255;
    const part3 = (ipInt >> 16) & 255;
    const part4 = (ipInt >> 24) & 255;
    return `${part1}.${part2}.${part3}.${part4}`;
  }

  private ipToInt(ip: string): number {
    try {
      // 使用手动实现替换 connection.convertIpToInt
      return this.manualIpToInt(ip);
    } catch (e) {
      this.log(`Invalid IP format for ipToInt: ${ip}`, 'error');
      return 0;
    }
  }

  public async autoDetectNetworkInterface(): Promise<void> {
    this.log('Auto-detecting network interface...');
    try {
      const defaultNet = await connection.getDefaultNet();
      if (defaultNet) {
        const netCaps = await connection.getNetCapabilities(defaultNet);
        if (netCaps.bearerTypes.includes(connection.NetBearType.BEARER_WIFI)) {
          this.config.networkInterface = 'wlan0';
          this.log('Default network is Wi-Fi, using interface wlan0');
        } else if (netCaps.bearerTypes.includes(connection.NetBearType.BEARER_ETHERNET)) {
          this.config.networkInterface = 'eth0';
          this.log('Default network is Ethernet, using interface eth0');
        }
      } else {
        this.log('No default network connection detected. Using default wlan0.', 'warn');
      }
    } catch (e) {
      this.log(`Failed to detect network interface: ${this.formatError(e)}`, 'error');
    }
  }

  public async configureEthernet(iface: string, config: EthernetConfig): Promise<void> {
    this.log(`Configuring Ethernet interface ${iface}...`);
    try {
      const ethConfig: ethernet.InterfaceConfiguration = {
        mode: ethernet.IPSetMode.STATIC,
        ipAddr: config.ipAddress,
        route: "0.0.0.0", // 通常设为0.0.0.0，由网关决定
        gateway: config.gateway,
        netMask: config.netmask,
        dnsServers: config.dns // dnsServers 需要一个字符串
      };
      await ethernet.setIfaceConfig(iface, ethConfig);
      this.log(`Successfully set Ethernet configuration for ${iface}.`);
    } catch (error) {
      const errMsg = `Failed to configure Ethernet: ${this.formatError(error)}`;
      this.log(errMsg, 'error');
      throw new Error(errMsg);
    }
  }

  public async configureWifi(config: WifiConfig): Promise<void> {
    this.log('Starting Wi-Fi configuration...');
    try {
      // 1. 确保Wi-Fi已激活
      if (!wifi.isWifiActive()) {
        this.log('Wi-Fi is not active, enabling...');
        wifi.enableWifi();
        await new Promise<void>(resolve => setTimeout(resolve, 2000)); // 等待启动
        this.log('Wi-Fi enabled.');
      } else {
        this.log('Wi-Fi is already active.');
      }

      // 2. IP地址转换
      const ipAddressInt = this.ipToInt(config.ipAddress);
      const gatewayInt = this.ipToInt(config.gateway);
      const dnsInt = this.ipToInt(config.dns);
      if (ipAddressInt === 0 || gatewayInt === 0 || dnsInt === 0) {
        throw new Error('Invalid IP, gateway, or DNS address format.');
      }

      // 3. 断开当前连接并移除旧配置
      this.log('Disconnecting current Wi-Fi...');
      wifi.disconnect();
      await new Promise<void>(resolve => setTimeout(resolve, 2000));

      const existingConfigs = wifi.getDeviceConfigs();
      const oldConfig = existingConfigs.find(c => c.ssid === config.ssid);
      if (oldConfig) {
        this.log(`Found and removing old config for ${config.ssid} (NetId: ${oldConfig.netId})`);
        wifi.disableNetwork(oldConfig.netId);
        wifi.removeDevice(oldConfig.netId);
        this.log('Old config removed.');
      }

      // 4. 清除DHCP缓存
      try {
        await fs.unlink(DeviceMonitor.FILE_PATH_DHCP_CACHE);
        this.log('DHCP cache cleared.');
      } catch (unlinkError) {
        this.log(`Could not clear DHCP cache (this may be expected): ${this.formatError(unlinkError)}`, 'warn');
      }

      // 5. 创建并添加新配置
      const deviceConfig: wifi.WifiDeviceConfig = {
        ssid: config.ssid,
        bssid: config.bssid,
        preSharedKey: config.preSharedKey,
        isHiddenSsid: config.isHiddenSsid,
        securityType: config.securityType,
        creatorUid: 0,
        disableReason: 0,
        netId: 0,
        randomMacType: 0,
        randomMacAddr: "00:00:00:00:00:00",
        ipType: wifi.IpType.STATIC,
        staticIp: {
          ipAddress: ipAddressInt,
          gateway: gatewayInt,
          dnsServers: [dnsInt],
          domains: ["dc.com"]
        }
      };

      this.log('Adding new Wi-Fi configuration...');
      const newNetId = await wifi.addDeviceConfig(deviceConfig);
      this.log(`New config added with NetId: ${newNetId}`);

      // 6. 连接到新网络
      this.log(`Connecting to ${config.ssid}...`);
      await new Promise<void>(resolve => setTimeout(resolve, 1000));
      const connectResult = wifi.connectToNetwork(newNetId);
      if (connectResult) {
        this.log(`Successfully sent connection command for ${config.ssid}.`);
      } else {
        throw new Error('Failed to send connection command.');
      }
    } catch (error) {
      const errMsg = `Wi-Fi configuration failed: ${this.formatError(error)}`;
      this.log(errMsg, 'error');
      throw new Error(errMsg);
    }
  }

  public async forgetAllWifiNetworks(): Promise<void> {
    this.log('Clearing all saved Wi-Fi networks...');
    try {
      if (!wifi.isWifiActive()) {
        this.log('Wi-Fi is not active. Please enable Wi-Fi first.', 'warn');
        return;
      }

      const savedNetworks = wifi.getDeviceConfigs();
      if (savedNetworks.length === 0) {
        this.log('No saved Wi-Fi networks found.');
        return;
      }

      this.log(`Found ${savedNetworks.length} networks. Removing them...`);
      let successCount = 0;
      let failCount = 0;

      for (const network of savedNetworks) {
        try {
          this.log(`Removing: ${network.ssid} (NetId: ${network.netId})`);
          wifi.disableNetwork(network.netId);
          wifi.removeDevice(network.netId);
          successCount++;
        } catch (innerError) {
          this.log(`Failed to remove ${network.ssid}: ${this.formatError(innerError)}`, 'error');
          failCount++;
        }
      }
      this.log(`Operation complete. Succeeded: ${successCount}, Failed: ${failCount}.`);
      wifi.disconnect();
    } catch (error) {
      const errMsg = `Failed to clear all Wi-Fi networks: ${this.formatError(error)}`;
      this.log(errMsg, 'error');
      throw new Error(errMsg);
    }
  }

  /**
   * 网络配置统一入口
   * @param mode 0: Ethernet, 1: Wi-Fi
   * @param ethConfig EthernetConfig, wifiConfig WifiConfig
   */
  public async configureNetwork(mode: number, ethConfig?: EthernetConfig, wifiConfig?: WifiConfig): Promise<void> {
    switch (mode) {
      case 0: // 以太网
        if (!ethConfig) throw new Error('EthernetConfig 参数缺失');
        await this.configureEthernet('eth0', ethConfig);
        break;
      case 1: // Wi-Fi
        if (!wifiConfig) throw new Error('WifiConfig 参数缺失');
        await this.configureWifi(wifiConfig);
        break;
      default:
        throw new Error(`未知的配置模式: ${mode}`);
    }
  }
}