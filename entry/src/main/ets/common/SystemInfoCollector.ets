import util from '@ohos.util';
import { fileIo as fs } from '@kit.CoreFileKit';
import { process } from '@kit.ArkTS';
import storageStatistics from '@ohos.file.storageStatistics';
import systemDateTime from '@ohos.systemDateTime';
import connection from '@ohos.net.connection';
import wifi from '@ohos.wifi';
import ethernet from '@ohos.net.ethernet';
import { 
  MemObjectType, 
  DiskObjectType, 
  NetObjectType, 
  MemInfoParsed, 
  CpuStat, 
  ParsedNetStats,
  LogFunction 
} from './types';

export class SystemInfoCollector {
  // 系统文件路径
  private static readonly FILE_PATH_MEM_INFO = '/proc/meminfo';
  private static readonly FILE_PATH_PROC_STAT = '/proc/stat';
  private static readonly FILE_PATH_NET_DEV = '/proc/net/dev';
  private static readonly FILE_PATH_SERIAL_NUMBER = '/proc/device-tree/serial-number';
  private static readonly FILE_PATH_CPU_TEMP = '/sys/class/thermal/thermal_zone0/temp';
  private static readonly FILE_PATH_MAC_ADDRESS_TPL = '/sys/class/net/{iface}/address';

  private log: LogFunction;
  private formatError: (error: Object) => string;

  constructor(log: LogFunction, formatError: (error: Object) => string) {
    this.log = log;
    this.formatError = formatError;
  }

  // 手动实现整数到 IP 字符串的转换 (大端序)
  private manualIntToIp(ipInt: number): string {
    const part1 = (ipInt >> 24) & 255;
    const part2 = (ipInt >> 16) & 255;
    const part3 = (ipInt >> 8) & 255;
    const part4 = ipInt & 255;
    return `${part1}.${part2}.${part3}.${part4}`;
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

  // 获取本地IP地址
  public async fetchLocalIp(networkInterface: string): Promise<string> {
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
            const ifaceConfig = await ethernet.getIfaceConfig(networkInterface);
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

  // 获取MAC地址
  public async fetchMacAddress(networkInterface: string): Promise<string> {
    const macFilePath = SystemInfoCollector.FILE_PATH_MAC_ADDRESS_TPL.replace('{iface}', networkInterface);
    return await this.readSystemFileContent(macFilePath);
  }

  // 获取设备序列号
  public async fetchSN(): Promise<string> {
    return await this.readSystemFileContent(SystemInfoCollector.FILE_PATH_SERIAL_NUMBER);
  }

  // 获取系统时间
  public async fetchSystemTime(): Promise<number> {
    const currentTime = await systemDateTime.getCurrentTime(true);
    return currentTime / 1_000_000_000;
  }

  // 获取系统运行时间
  public async fetchUptime(): Promise<number | null> {
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

  // 获取CPU温度
  public async fetchCpuTemperature(): Promise<number | string> {
    const tempStr = await this.readSystemFileContent(SystemInfoCollector.FILE_PATH_CPU_TEMP);
    if (tempStr !== 'N/A' && tempStr !== 'Loading...') {
      const numericTemp = parseFloat(tempStr);
      if (!isNaN(numericTemp)) {
        return parseFloat((numericTemp / 1000).toFixed(1));
      }
    }
    return tempStr;
  }

  // 获取内存信息
  public async fetchMemInfo(): Promise<MemObjectType> {
    const defaultErrorMemInfo: MemObjectType = {
      memTotal: 0,
      memLoad: 0,
      memUsed: 0,
      memAvailable: 0,
      unit: 'Byte'
    };

    try {
      const content = await this.readSystemFileContent(SystemInfoCollector.FILE_PATH_MEM_INFO);
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

  // 获取CPU使用率
  public async getCpuPercent(interval: number = 1000): Promise<number> {
    const stat1 = await this.readSystemFileContent(SystemInfoCollector.FILE_PATH_PROC_STAT);
    const cpu1 = this.parseCpuStat(stat1);

    await new Promise<void>(resolve => setTimeout(resolve, interval));

    const stat2 = await this.readSystemFileContent(SystemInfoCollector.FILE_PATH_PROC_STAT);
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
  public async fetchDiskInfo(mountPath: string): Promise<DiskObjectType> {
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

  // 获取网络信息
  public async fetchNetworkInfo(interfaceName: string): Promise<NetObjectType> {
    const defaultErrorNetInfo: NetObjectType = {
      netInterface: interfaceName,
      txByte: -1,
      txRate: -1,
      rxByte: -1,
      rxRate: -1,
      unit: 'Bytes/s'
    };

    try {
      const stats1Content = await this.readSystemFileContent(SystemInfoCollector.FILE_PATH_NET_DEV);
      if (stats1Content === 'N/A') {
        return defaultErrorNetInfo;
      }

      const initialStats = this.parseNetDevContent(stats1Content, interfaceName);
      if (!initialStats) {
        return defaultErrorNetInfo;
      }

      await new Promise<void>(resolve => setTimeout(resolve, 1000));

      const stats2Content = await this.readSystemFileContent(SystemInfoCollector.FILE_PATH_NET_DEV);
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
}
