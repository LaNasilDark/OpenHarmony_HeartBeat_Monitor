import hilog from '@ohos.hilog';
import socket from '@ohos.net.socket';
import wifiManager from '@ohos.wifiManager';
import systemDateTime from '@ohos.systemDateTime';
import util from '@ohos.util';
import fs from '@ohos.file.fs';
import { statfs } from '@kit.CoreFileKit';
import ethernet from '@ohos.net.ethernet';
import { process } from '@kit.ArkTS';

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

export interface MonitorConfig {
  targetUdpIp: string;
  targetUdpPort: number;
  localUdpPort: number;
  agentVersion: string;
  networkInterface: string;
  diskMountPath: string;
  collectInterval: number;
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
      hilog.error(DeviceMonitor.DOMAIN, DeviceMonitor.TAG, `Failed to read system file at ${filePath}: ${JSON.stringify(error)}`);
      return 'N/A';
    } finally {
      if (file) {
        try {
          await fs.close(file.fd);
        } catch (closeError) {
          hilog.error(DeviceMonitor.DOMAIN, DeviceMonitor.TAG, `Failed to close file ${filePath}: ${JSON.stringify(closeError)}`);
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
      const content = await this.readSystemFileContent('/proc/meminfo');
      if (content === 'N/A') {
        hilog.error(DeviceMonitor.DOMAIN, DeviceMonitor.TAG, "Failed to read /proc/meminfo.");
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
      hilog.warn(DeviceMonitor.DOMAIN, DeviceMonitor.TAG, "Parsed MemTotal is 0.");
      return defaultErrorMemInfo;

    } catch (error) {
      hilog.error(DeviceMonitor.DOMAIN, DeviceMonitor.TAG, `Failed to fetch mem info: ${JSON.stringify(error)}`);
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
    const stat1 = await this.readSystemFileContent('/proc/stat');
    const cpu1 = this.parseCpuStat(stat1);

    await new Promise<void>(resolve => setTimeout(resolve, interval));

    const stat2 = await this.readSystemFileContent('/proc/stat');
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
      const totalBytesNum: number = await statfs.getTotalSize(mountPath);
      const availableBytesNum: number = await statfs.getFreeSize(mountPath);

      const totalBytes = totalBytesNum;
      const availableBytes = availableBytesNum;
      const usedBytes = totalBytes - availableBytes;
      const percentNum = usedBytes > 0 && totalBytes > 0 ? (usedBytes / totalBytes) * 100 : 0;

      return {
        mounted: mountPath,
        available: availableBytes,
        total: totalBytes,
        percent: percentNum,
        used: usedBytes,
        unit: 'Byte'
      };
    } catch (error) {
      hilog.error(DeviceMonitor.DOMAIN, DeviceMonitor.TAG, `Failed to fetch disk info for ${mountPath}: ${JSON.stringify(error)}`);
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
      hilog.warn(DeviceMonitor.DOMAIN, DeviceMonitor.TAG, `Interface ${interfaceName} not found in /proc/net/dev.`);
      return null;
    } catch (e) {
      hilog.error(DeviceMonitor.DOMAIN, DeviceMonitor.TAG, `Error parsing /proc/net/dev: ${JSON.stringify(e)}`);
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
      const stats1Content = await this.readSystemFileContent('/proc/net/dev');
      if (stats1Content === 'N/A') {
        return defaultErrorNetInfo;
      }
      
      const initialStats = this.parseNetDevContent(stats1Content, interfaceName);
      if (!initialStats) {
        return defaultErrorNetInfo;
      }

      await new Promise<void>(resolve => setTimeout(resolve, 1000));

      const stats2Content = await this.readSystemFileContent('/proc/net/dev');
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
      hilog.error(DeviceMonitor.DOMAIN, DeviceMonitor.TAG, `Exception in fetchNetworkInfo: ${JSON.stringify(error)}`);
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
      hilog.error(DeviceMonitor.DOMAIN, DeviceMonitor.TAG, `Exception in fetchUptime: ${JSON.stringify(e)}`);
      return null;
    }
  }

  // 获取MAC地址
  private async fetchMacAddress(): Promise<string> {
    const macFilePath = `/sys/class/net/${this.config.networkInterface}/address`;
    return await this.readSystemFileContent(macFilePath);
  }

  // 获取系统时间
  private async fetchSystemTime(): Promise<number> {
    const currentTime = await systemDateTime.getCurrentTime(true);
    return currentTime / 1_000_000_000;
  }

  // 获取CPU温度
  private async fetchCpuTemperature(): Promise<number | string> {
    const thermalFilePath = '/sys/class/thermal/thermal_zone0/temp';
    const tempStr = await this.readSystemFileContent(thermalFilePath);
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
    try {
      const ipInfo = await wifiManager.getIpInfo();
      const currentIpNum = ipInfo.ipAddress;
      if (currentIpNum !== 0) {
        return (currentIpNum >>> 24) + '.' + (currentIpNum >> 16 & 0xFF) + '.' + (currentIpNum >> 8 & 0xFF) + '.' + (currentIpNum & 0xFF);
      }
      return "0.0.0.0";
    } catch (error) {
      hilog.error(DeviceMonitor.DOMAIN, DeviceMonitor.TAG, `Error fetching local IP: ${JSON.stringify(error)}`);
      return "0.0.0.0";
    }
  }

  // 获取设备序列号
  private async fetchSN(): Promise<string> {
    const snFilePath = '/proc/device-tree/serial-number';
    return await this.readSystemFileContent(snFilePath);
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

      hilog.info(DeviceMonitor.DOMAIN, DeviceMonitor.TAG, 'Device info collected successfully');
      return deviceInfo;
    } catch (error) {
      hilog.error(DeviceMonitor.DOMAIN, DeviceMonitor.TAG, `Failed to collect device info: ${JSON.stringify(error)}`);
      // 重新抛出包装为Error对象的错误，以符合ArkTS规范
      throw new Error(`Failed to collect device info: ${JSON.stringify(error)}`);
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

      hilog.info(DeviceMonitor.DOMAIN, DeviceMonitor.TAG, `Device info sent to ${this.config.targetUdpIp}:${this.config.targetUdpPort}`);
    } catch (error) {
      hilog.error(DeviceMonitor.DOMAIN, DeviceMonitor.TAG, `Failed to send device info via UDP: ${JSON.stringify(error)}`);
      throw new Error(`Failed to send device info via UDP: ${JSON.stringify(error)}`);
    }
  }

  // 启动监控服务
  public async startMonitoring(): Promise<void> {
    if (this.isRunning) {
      hilog.warn(DeviceMonitor.DOMAIN, DeviceMonitor.TAG, 'Monitor is already running');
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
        hilog.info(DeviceMonitor.DOMAIN, DeviceMonitor.TAG, `UDP socket bound to port ${this.config.localUdpPort}`);
      }

      // 发送初始设备信息
      await this.sendDeviceInfoViaUDP();

      // 启动定期发送
      this.sendIntervalId = setInterval(async () => {
        try {
          await this.sendDeviceInfoViaUDP();
        } catch (e) {
          hilog.error(DeviceMonitor.DOMAIN, DeviceMonitor.TAG, `Error in periodic UDP send: ${JSON.stringify(e)}`);
        }
      }, this.config.collectInterval);

      this.isRunning = true;
      hilog.info(DeviceMonitor.DOMAIN, DeviceMonitor.TAG, 'Device monitoring started successfully');
    } catch (error) {
      hilog.error(DeviceMonitor.DOMAIN, DeviceMonitor.TAG, `Failed to start monitoring: ${JSON.stringify(error)}`);
      throw new Error(`Failed to start monitoring: ${JSON.stringify(error)}`);
    }
  }

  // 停止监控服务
  public stopMonitoring(): void {
    if (!this.isRunning) {
      hilog.warn(DeviceMonitor.DOMAIN, DeviceMonitor.TAG, 'Monitor is not running');
      return;
    }

    try {
      // 停止定时器
      if (this.sendIntervalId !== -1) {
        clearInterval(this.sendIntervalId);
        this.sendIntervalId = -1;
      }

      this.isRunning = false;
      hilog.info(DeviceMonitor.DOMAIN, DeviceMonitor.TAG, 'Device monitoring stopped successfully');
    } catch (error) {
      hilog.error(DeviceMonitor.DOMAIN, DeviceMonitor.TAG, `Failed to stop monitoring: ${JSON.stringify(error)}`);
    }
  }

  // 检查监控状态
  public isMonitoringRunning(): boolean {
    return this.isRunning;
  }

  // 获取当前设备数据快照
  public getDeviceDataSnapshot(): DeviceDataCache {
    return {
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
  }

  // 更新配置
  public updateConfig(newConfig: Partial<MonitorConfig>): void {
    if (newConfig.targetUdpIp !== undefined) {
      this.config.targetUdpIp = newConfig.targetUdpIp;
    }
    if (newConfig.targetUdpPort !== undefined) {
      this.config.targetUdpPort = newConfig.targetUdpPort;
    }
    if (newConfig.localUdpPort !== undefined) {
      this.config.localUdpPort = newConfig.localUdpPort;
    }
    if (newConfig.agentVersion !== undefined) {
      this.config.agentVersion = newConfig.agentVersion;
    }
    if (newConfig.networkInterface !== undefined) {
      this.config.networkInterface = newConfig.networkInterface;
    }
    if (newConfig.diskMountPath !== undefined) {
      this.config.diskMountPath = newConfig.diskMountPath;
    }
    if (newConfig.collectInterval !== undefined) {
      this.config.collectInterval = newConfig.collectInterval;
    }
    hilog.info(DeviceMonitor.DOMAIN, DeviceMonitor.TAG, 'Monitor configuration updated');
  }

  // 清理资源
  public dispose(): void {
    this.stopMonitoring();
    if (this.udpSocketBound) {
      this.udpSocket.close().catch((e: Object) => {
        hilog.error(DeviceMonitor.DOMAIN, DeviceMonitor.TAG, `Error closing UDP socket: ${JSON.stringify(e)}`);
      });
      this.udpSocketBound = false;
    }
  }
}
