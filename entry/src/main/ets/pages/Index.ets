import hilog from '@ohos.hilog';
import socket from '@ohos.net.socket';
import wifiManager from '@ohos.wifiManager';
import systemDateTime from '@ohos.systemDateTime';
import util from '@ohos.util';
import fs from '@ohos.file.fs';
import { statfs } from '@kit.CoreFileKit';

interface DeviceInfo {
  cpuLoad: string; // 可选属性，CPU负载
  memInfo: MemObjectType; // 可选属性，内存信息
  disk: DiskObjectType;
  net: NetObjectType; 
  mac: string;
  ipAddress: string;
  upTime: string | number; // 可选属性，设备运行时间，可以是字符串或数字
  time: string | number; // 可选属性，当前时间，可以是字符串或数字
  sn: string;
  cpuTemperature: string | number;
  agentVersion: string // 可选属性，CPU温度，可以是字符串或数字 
}
interface NetObjectType {
  netInterface: string;
  txByte: number;
  txRate: number;
  rxByte: number;
  rxRate: number;
  unit: string; // 可选属性 
}
interface DiskObjectType {
  mounted: string;
  available: number;
  total: number;
  percent: number;
  used: number;
  unit: string;
}
interface MemObjectType {
  memTotal: number;
  memLoad: number;
  memUsed: number;
  memAvailable: number;
  unit: string; // 可选属性
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

let udpSocket = socket.constructUDPSocketInstance();

let ipNum = wifiManager.getIpInfo().ipAddress;
let localIp = (ipNum >>> 24) + '.' + (ipNum >> 16 & 0xFF) + '.' + (ipNum >> 8 & 0xFF) + '.' + (ipNum & 0xFF);

const TAG: string = 'IndexPage';
const DOMAIN: number = 0x0001;

// --- BEGIN: Added for UDP Sending ---
const TARGET_UDP_IP: string = "10.0.90.241"; // <-- 重要：请替换为您的目标IP地址
const TARGET_UDP_PORT: number = 9990; // 您可以根据需要更改目标端口
const LOCAL_UDP_PORT: number = 9991; // <-- 新增：定义本地UDP绑定的端口
// --- END: Added for UDP Sending ---

let cpuTemp: string = 'Loading...';
let sn: string = 'Loading...';
let time: string = 'Loading...';
let mac: string = 'Loading...';
let upTime: string = 'Loading...';
let net: NetObjectType = {
  netInterface: '0',
  txByte: -1,
  txRate: -1,
  rxByte: -1,
  rxRate: -1,
  unit: 'Bytes/s'
};
let disk: DiskObjectType = {
  mounted: '/',
  available: -1,
  total: -1,
  percent: -1,
  used: -1,
  unit: 'Byte'
};
let cpuLoad: string = 'Loading...';
let mem: MemObjectType = {
  memTotal: -1,
  memLoad: -1,
  memUsed: -1,
  memAvailable: -1,
  unit: 'Byte'
};

async function readSystemFileContent(filePath: string): Promise<string> {
  let file: fs.File | null = null;
  try {
    file = await fs.open(filePath, fs.OpenMode.READ_ONLY);
    const buffer = new ArrayBuffer(1024);
    const bytesRead = await fs.read(file.fd, buffer);
    const decoder = new util.TextDecoder('utf-8');
    const content = decoder.decode(new Uint8Array(buffer, 0, bytesRead));
    return content.trim();
  } catch (error) {
    hilog.error(DOMAIN, TAG, `Failed to read system file at ${filePath}: ${JSON.stringify(error)}`);
    return 'N/A';
  } finally {
    if (file) {
      try {
        await fs.close(file.fd);
      } catch (closeError) {
        hilog.error(DOMAIN, TAG, `Failed to close file ${filePath}: ${JSON.stringify(closeError)}`);
      }
    }
  }
}

// {'cpuLoad': bug:13900012, 'memInfo': {'memTotal': Done, 'memLoad': Done, 'memUsed': Done, 'memAvailable': Done, 'unit': 'Done'}, 'disk': {'mounted': 'bug', 'available': bug, 'total': bug, 'percent': bug, 'used': bug, 'unit': 'Byte'}, 'net': {'netInterface': 'Done', 'txByte': Done, 'txRate': Done, 'rxByte': Done, 'rxRate': Done, 'unit': 'Bytes/s'}, 'mac': Done, 'ip': Done, 'upTime': Done, 'time': Done, 'sn': Done, 'cpuTemp': Done, 'agentVersion': '1.14514'}
function parseMemInfo(content: string): MemInfoParsed { // FIX: 使用已定义的接口 MemInfoParsed 作为返回类型
  const lines = content.split('\n');
  let memTotal = 0;
  let memAvailable = 0;

  for (const line of lines) {
    const parts = line.split(/\s+/);
    if (parts.length >= 2) {
      const value = parseInt(parts[1], 10);
      if (!isNaN(value)) {
        if (line.startsWith('MemTotal:')) {
          memTotal = value * 1024; // kB to Bytes
        } else if (line.startsWith('MemAvailable:')) {
          memAvailable = value * 1024; // kB to Bytes
        }
      }
    }
  }
  return { memTotal, memAvailable };
}

async function fetchMemInfo(): Promise<MemObjectType> {
  const defaultErrorMemInfo: MemObjectType = {
    memTotal: 0,
    memLoad: 0,
    memUsed: 0,
    memAvailable: 0,
    unit: 'Byte'
  };

  try {
    const content = await readSystemFileContent('/proc/meminfo');
    if (content === 'N/A') {
      hilog.error(DOMAIN, TAG, "Failed to read /proc/meminfo.");
      return defaultErrorMemInfo;
    }

    const parsedInfo = parseMemInfo(content);
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
    hilog.warn(DOMAIN, TAG, "Parsed MemTotal is 0.");
    return defaultErrorMemInfo;

  } catch (error) {
    hilog.error(DOMAIN, TAG, `Failed to fetch mem info: ${JSON.stringify(error)}`);
    return defaultErrorMemInfo;
  }
}

async function updateMemGlobal(): Promise<void> {
  try {
    mem = await fetchMemInfo();
    hilog.info(DOMAIN, TAG, `Global mem info updated: Load=${mem.memLoad}%, Total=${mem.memTotal}B`);
  } catch (error) {
    hilog.error(DOMAIN, TAG, `Failed to update global mem info: ${JSON.stringify(error)}`);
    mem = { // Reset to error state
      memTotal: -1,
      memLoad: -1,
      memUsed: -1,
      memAvailable: -1,
      unit: 'Byte'
    };
  }
}

function parseCpuStat(stat: string): CpuStat {
  const lines = stat.split('\n');
  const cpuLine = lines[0];
  const parts = cpuLine.trim().split(/\s+/);
  const nums = parts.slice(1).map(v => parseInt(v, 10));
  const idle = nums[3] + (nums[4] || 0); // idle + iowait
  const total = nums.reduce((a, b) => a + b, 0);
  return { idle, total };
}
async function getCpuPercent(interval: number = 1000): Promise<number> {
  const stat1 = await readSystemFileContent('/proc/stat');
  const cpu1 = parseCpuStat(stat1);

  await new Promise<void>(resolve => setTimeout(resolve, interval));

  const stat2 = await readSystemFileContent('/proc/stat');
  const cpu2 = parseCpuStat(stat2);

  const idleDelta = cpu2.idle - cpu1.idle;
  const totalDelta = cpu2.total - cpu1.total;

  if (totalDelta <= 0) {
    return 0;
  }
  const usage = (1 - idleDelta / totalDelta) * 100;
  return Number(usage.toFixed(1));
}
async function updateCpuPercentGlobal(): Promise<void> {
  try {
    const cpuLoad = await getCpuPercent();
    hilog.info(DOMAIN, TAG, `Global CPU load updated: ${cpuLoad}%`);
    // 这里可以将 cpuLoad 存储到全局变量或状态中
  } catch (error) {
    hilog.error(DOMAIN, TAG, `Failed to update global CPU load: ${JSON.stringify(error)}`);
  }
}

async function fetchDiskInfo(mountPath: string = "/data"): Promise<DiskObjectType> {
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
    const availableBytesNum: number = await statfs.getFreeSize(mountPath); // This is free bytes, which might be equivalent to available for non-superuser

    // Convert to BigInt for consistent calculations, though numbers from API might be safe.
    const totalBytes = (totalBytesNum);
    const availableBytes = (availableBytesNum);
    hilog.info(DOMAIN, TAG, `Disk info for ${mountPath}: Total=${totalBytes}B, Available=${availableBytes}B`);

    // Used bytes calculation
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
    // It's good practice to check the error type if BusinessError is expected
    // import { BusinessError } from '@kit.BasicServicesKit';
    // if (error instanceof BusinessError) { ... }
    hilog.error(DOMAIN, TAG, `Failed to fetch disk info for ${mountPath} using @kit.CoreFileKit/statfs: ${JSON.stringify(error)}, Code: ${error.code}, Msg: ${error.message}`);
    return defaultErrorDiskInfo;
  }
}
async function updateDiskGlobal(mountPath: string = "/data"): Promise<void> {
  try {
    disk = await fetchDiskInfo(mountPath);
    hilog.info(DOMAIN, TAG, `Global disk info updated for ${disk.mounted}: Total=${disk.total}B, Used=${disk.used}B (${disk.percent}%)`);
  } catch (error) {
    hilog.error(DOMAIN, TAG, `Failed to update global disk info: ${JSON.stringify(error)}`);
    disk = { // Reset to error state
      mounted: mountPath,
      available: -1,
      total: -1,
      percent: -1,
      used: -1,
      unit: 'Byte'
    };
  }
}

function parseNetDevContent(content: string, interfaceName: string): ParsedNetStats | null {
  try {
    const lines = content.split('\n');
    // Skip the first two header lines
    for (let i = 2; i < lines.length; i++) {
      const line = lines[i].trim();
      if (line.startsWith(interfaceName + ':')) {
        // Line format: Interface: RcvBytes Pkts Errs Drop Fifo Frame Compr Multicast | TransBytes Pkts Errs Drop Fifo Colls Carrier Compr
        // Example: wlan0: 109441483    3689    0    0    0     0          0         0   803350     109    0   72    0     0       0          0
        const parts = line.substring(line.indexOf(':') + 1).trim().split(/\s+/);
        if (parts.length >= 10) { // Need at least up to Transmit_bytes
          const rxBytes = parseInt(parts[0], 10); // Receive bytes
          const txBytes = parseInt(parts[8], 10); // Transmit bytes

          if (!isNaN(rxBytes) && !isNaN(txBytes)) {
            return { rxBytes, txBytes };
          }
        }
      }
    }
    hilog.warn(DOMAIN, TAG, `Interface ${interfaceName} not found or malformed in /proc/net/dev content.`);
    return null;
  } catch (e) {
    hilog.error(DOMAIN, TAG, `Error parsing /proc/net/dev content: ${JSON.stringify(e)}`);
    return null;
  }
}
async function fetchNetworkInfo(interfaceName: string = "wlan0"): Promise<NetObjectType> {
  const defaultErrorNetInfo: NetObjectType = {
    netInterface: interfaceName,
    txByte: -1,
    txRate: -1,
    rxByte: -1,
    rxRate: -1,
    unit: 'Bytes/s'
  };

  try {
    const stats1Content = await readSystemFileContent('/proc/net/dev');
    if (stats1Content === 'N/A') {
      hilog.error(DOMAIN, TAG, "fetchNetworkInfo: Failed to read /proc/net/dev (1st attempt)");
      return defaultErrorNetInfo;
    }
    const initialStats = parseNetDevContent(stats1Content, interfaceName);
    if (!initialStats) {
      hilog.error(DOMAIN, TAG, `fetchNetworkInfo: Failed to parse initial stats for ${interfaceName}`);
      return defaultErrorNetInfo;
    }

    // Wait for 1 second
    await new Promise<void>(resolve => setTimeout(resolve, 1000));

    const stats2Content = await readSystemFileContent('/proc/net/dev');
    if (stats2Content === 'N/A') {
      hilog.error(DOMAIN, TAG, "fetchNetworkInfo: Failed to read /proc/net/dev (2nd attempt)");
      return defaultErrorNetInfo;
    }
    const finalStats = parseNetDevContent(stats2Content, interfaceName);
    if (!finalStats) {
      hilog.error(DOMAIN, TAG, `fetchNetworkInfo: Failed to parse final stats for ${interfaceName}`);
      return defaultErrorNetInfo;
    }

    // Calculate deltas (rates are per second due to 1s interval)
    const deltaRxBytes = finalStats.rxBytes - initialStats.rxBytes;
    const deltaTxBytes = finalStats.txBytes - initialStats.txBytes;

    // Ensure rates are not negative (can happen if counters reset or very small fluctuations)
    const rxRate = Math.max(0, deltaRxBytes);
    const txRate = Math.max(0, deltaTxBytes);

    return {
      netInterface: interfaceName,
      rxByte: finalStats.rxBytes, // Total received bytes at the end of interval
      txByte: finalStats.txBytes, // Total transmitted bytes at the end of interval
      rxRate: rxRate,
      txRate: txRate,
      unit: 'Bytes/s'
    };
  } catch (error) {
    hilog.error(DOMAIN, TAG, `Exception in fetchNetworkInfo: ${JSON.stringify(error)}`);
    return defaultErrorNetInfo;
  }
}
async function updateNetGlobal(interfaceName: string = "wlan0"): Promise<void> {
  try {
    const fetchedNetInfo = await fetchNetworkInfo(interfaceName);
    net = fetchedNetInfo; // Update the global net variable
    hilog.info(DOMAIN, TAG, `Global net info updated for ${interfaceName}: RxRate=${net.rxRate} B/s, TxRate=${net.txRate} B/s`);
  } catch (error) {
    hilog.error(DOMAIN, TAG, `Failed to update global net info: ${JSON.stringify(error)}`);
    net = { // Reset to error state
      netInterface: interfaceName,
      txByte: -1,
      txRate: -1,
      rxByte: -1,
      rxRate: -1,
      unit: 'Bytes/s'
    };
  }
}

async function fetchUptimeFromProcUptime(): Promise<string | null> {
  const filePath = "/proc/uptime";
  try {
    const content = await readSystemFileContent(filePath);
    if (content === 'N/A' || !content) {
      hilog.error(DOMAIN, TAG, "Failed to read /proc/uptime or content is empty.");
      return null;
    }
    // /proc/uptime 的内容通常是两个数字，例如 "350735.47 234388.95"
    // 我们只需要第一个数字，即系统总运行时间（秒）
    const parts = content.split(/\s+/);
    if (parts.length >= 1) {
      const uptimeSeconds = parseFloat(parts[0]);
      if (!isNaN(uptimeSeconds)) {
        hilog.info(DOMAIN, TAG, `Successfully fetched uptime: ${uptimeSeconds.toFixed(0)} seconds`);
        let upTimeDays = uptimeSeconds / 86400; // 计算天数
        return upTimeDays.toFixed(2); 
      } else {
        hilog.error(DOMAIN, TAG, `Failed to parse uptime value from /proc/uptime: ${parts[0]}`);
        return null;
      }
    }
    hilog.warn(DOMAIN, TAG, "Could not parse uptime from /proc/uptime content: " + content);
    return null;
  } catch (e) {
    hilog.error(DOMAIN, TAG, `Exception in fetchUptimeFromProcUptime: ${JSON.stringify(e)}`);
    return null;
  }
}
async function updateUpTimeGlobal(): Promise<void> {
  try {
    const fetchedUptime = await fetchUptimeFromProcUptime(); // 调用新的函数
    if (fetchedUptime !== null) {
      upTime = fetchedUptime;
      hilog.info(DOMAIN, TAG, `Global uptime updated: ${upTime} days`);
    } else {
      upTime = 'ErrorFetchingUptime'; // 或者其他错误指示字符串
      hilog.error(DOMAIN, TAG, 'Failed to fetch uptime from /proc/uptime');
    }
  } catch (error) {
    upTime = 'ErrorFetchingUptime'; // 或者其他错误指示字符串
    hilog.error(DOMAIN, TAG, `Failed to update global uptime: ${JSON.stringify(error)}`);
  }
}

async function fetchMacAddress(): Promise<string> {
  const macFilePath = '/sys/class/net/wlan0/address'; // 假设使用 wlan0 接口
  return await readSystemFileContent(macFilePath);
}
async function updateMacGlobal(): Promise<void> {
  try {
    mac = await fetchMacAddress();
    if (mac === 'N/A') {
      mac = 'NoMAC'; // 如果无法获取MAC地址，设置为默认值
    }
    hilog.info(DOMAIN, TAG, `Global MAC updated: ${mac}`);
  } catch (error) {
    mac = 'ErrorFetchingMAC'; // 或者其他错误指示字符串
    hilog.error(DOMAIN, TAG, `Failed to update global MAC: ${JSON.stringify(error)}`);
  }
}

async function fetchSystemTime(): Promise<string> {
  const currentTime = await systemDateTime.getCurrentTime(true) / 1000000000; // 获取当前的 Date 对象
  return currentTime.toString();
}
async function updateTimeGlobal(): Promise<void> {
  try {
    time = await fetchSystemTime();
    hilog.info(DOMAIN, TAG, `Global time updated: ${time}`);
  } catch (error) {
    time = 'ErrorFetchingTime'; // 或者其他错误指示字符串
    hilog.error(DOMAIN, TAG, `Failed to update global time: ${JSON.stringify(error)}`);
  }
}

async function fetchCpuTemperature(): Promise<string> {
  const thermalFilePath = '/sys/class/thermal/thermal_zone0/temp';
  return await readSystemFileContent(thermalFilePath);
}
async function updateCpuTempGlobal(): Promise<void> {
  const tempStr = await fetchCpuTemperature();
  if (tempStr !== 'N/A' && tempStr !== 'Loading...') {
    const numericTemp = parseFloat(tempStr);
    if (!isNaN(numericTemp)) {
      cpuTemp = (numericTemp / 1000).toFixed(1);
    } else {
      cpuTemp = 'Invalid';
      hilog.warn(DOMAIN, TAG, `CPU temperature string is not a valid number: ${tempStr}`);
    }
  } else {
    cpuTemp = tempStr;
  }
  hilog.info(DOMAIN, TAG, `CPU Temperature status: ${cpuTemp}°C`);
}

// --- BEGIN: New function to update local IP ---
async function updateLocalIpGlobal(): Promise<void> {
  try {
    const ipInfo = await wifiManager.getIpInfo(); // getIpInfo is asynchronous
    const currentIpNum = ipInfo.ipAddress;
    if (currentIpNum !== 0) { // Check if a valid IP is obtained
      localIp = (currentIpNum >>> 24) + '.' + (currentIpNum >> 16 & 0xFF) + '.' + (currentIpNum >> 8 & 0xFF) + '.' + (currentIpNum & 0xFF);
      hilog.info(DOMAIN, TAG, `Local IP updated: ${localIp}`);
    } else {
      hilog.warn(DOMAIN, TAG, 'Failed to update local IP, ipAddress is 0.');
      // localIp = "N/A"; // Or keep the last known IP
    }
  } catch (error) {
    hilog.error(DOMAIN, TAG, `Error updating local IP: ${JSON.stringify(error)}`);
    // localIp = "Error"; // Or keep the last known IP
  }
}
// --- END: New function to update local IP ---

async function fetchSN(): Promise<string> {
  const snFilePath = '/proc/device-tree/serial-number';
  return await readSystemFileContent(snFilePath);
}
async function updateSnGlobal(): Promise<void> {
  try {
    sn = await fetchSN();
    hilog.info(DOMAIN, TAG, `Global SN updated: ${sn}`);
  } catch (error) {
    sn = 'ErrorFetchingSN'; // 或者其他错误指示字符串
    hilog.error(DOMAIN, TAG, `Failed to update global SN: ${JSON.stringify(error)}`);
  }
}

function calculateChecksum(data: Uint8Array): number {
  let sum = 0;
  const len = data.length;
  const n = len % 2;

  // Sum up 16-bit words
  for (let i = 0; i < len - n; i += 2) {
    // Combine two 8-bit bytes into one 16-bit word (little-endian pair)
    sum += data[i] + (data[i + 1] << 8);
  }

  // Add the last byte if the length is odd
  if (n) {
    sum += data[len - 1];
  }

  // Fold 32-bit sum to 16 bits: add carrier to result
  while (sum >> 16) {
    sum = (sum & 0xFFFF) + (sum >> 16);
  }

  // Take the one's complement of the sum
  return ~sum & 0xFFFF;
}

// --- BEGIN: New function to send device info via UDP ---
async function sendDeviceInfoViaUDP(): Promise<void> {
  try {
    // 1. 确保 CPU 温度是最新的
    await updateCpuTempGlobal();
    await updateLocalIpGlobal();
    await updateSnGlobal();
    await updateTimeGlobal();
    await updateMacGlobal(); 
    await updateUpTimeGlobal(); // 确保在发送前获取最新的运行时间
    await updateNetGlobal("wlan0"); // 确保在发送前获取最新的网络信息
    await updateDiskGlobal("/data");
    await updateCpuPercentGlobal(); // 更新 CPU 使用率
    await updateMemGlobal(); // 更新内存信息
    // 2. 准备要发送的数据

    let agentVersion: string = '1.14514'; // 假设这是您的应用版本号

    const deviceInfo: DeviceInfo = { // 使用定义的接口
      cpuLoad: cpuLoad, // 新增 CPU 负载字段
      memInfo: mem, // 新增内存信息
      disk: disk,
      net: net,
      mac: mac, // 新增 MAC 地址字段
      ipAddress: localIp,
      upTime: Number(upTime),
      time: Number(time),
      sn: sn,
      cpuTemperature: Number(cpuTemp),
      agentVersion: agentVersion // 新增应用版本字段
    };
    const messageString = JSON.stringify(deviceInfo);
    const encoder = new util.TextEncoder();
    // a. 将 JSON 消息编码为字节数组
    const messageBytes = encoder.encode(messageString);

    // b. 计算校验和
    const checksum = calculateChecksum(messageBytes);

    // c. 将 16 位校验和打包成 2 字节的 Uint8Array (大端序/网络字节序)
    const checksumBuffer = new ArrayBuffer(2);
    const view = new DataView(checksumBuffer);
    view.setUint16(0, checksum, false); // false for big-endian (network byte order)
    const checksumBytes = new Uint8Array(checksumBuffer);

    // d. 将校验和与消息拼接，形成最终的数据包
    const packetBytes = new Uint8Array(checksumBytes.length + messageBytes.length);
    packetBytes.set(checksumBytes, 0); // 附加校验和
    packetBytes.set(messageBytes, checksumBytes.length); // 附加消息

    // 3. 定义远程地址信息，使用 socket.NetAddress
    const remoteAddress: socket.NetAddress = { // 改为 socket.NetAddress
      address: TARGET_UDP_IP,
      port: TARGET_UDP_PORT,
      family: 0 // 0 代表 IPv4，与 TARGET_UDP_IP 格式匹配
    };

    // 4. 发送数据
    await udpSocket.send({
      data: packetBytes.buffer,
      address: remoteAddress // 现在类型匹配
    });
    hilog.info(DOMAIN, TAG, `Device info sent to ${TARGET_UDP_IP}:${TARGET_UDP_PORT}: ${messageString}`);
  } catch (error) {
    hilog.error(DOMAIN, TAG, `Failed to send device info via UDP: ${JSON.stringify(error)}`);  
  }
}





// --- END: New function to send device info via UDP ---

(async () => {
  await updateCpuTempGlobal();
  await updateLocalIpGlobal();
  await updateSnGlobal();
  await updateTimeGlobal();
  await updateMacGlobal(); // 确保在应用启动时获取最新的 MAC 地址
  await updateUpTimeGlobal(); // 确保在应用启动时获取最新的运行时间
  await updateNetGlobal("wlan0");
  await updateDiskGlobal("/data"); // 确保在应用启动时获取最新的磁盘信息
  await updateCpuPercentGlobal(); // 更新 CPU 使用率
  await updateMemGlobal(); // 更新内存信息
})();




@Entry
@Component
struct Index {
  @State message: string = 'OpenHarmony Heartbeat Monitor Beta';
  @State serviceStatus: string = '服务未启动';
  @State isServiceRunning: boolean = false;
  @State runtimeLog: string = '应用日志:\n';
  //private monitorManager: SimpleMonitorManager = new SimpleMonitorManager();
  private udpSocketBound: boolean = false; // 用于跟踪全局socket是否已尝试绑定
  private sendIntervalId: number = -1;

  public addLog(log: string): void {
    const now = new Date();
    const timestamp = `${now.getHours()}:${now.getMinutes()}:${now.getSeconds()}.${now.getMilliseconds()}`;
    this.runtimeLog += `[${timestamp}] ${log}\n`;
  }

  build() {
    // ... (您的 build 方法保持不变)
    Column({ space: 10 }) { // 调整 space 以容纳更多元素
      Text(this.message)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .textAlign(TextAlign.Center)

      Text(this.serviceStatus)
        .fontSize(16)
        .fontColor(this.isServiceRunning ? Color.Green : Color.Red)
        .textAlign(TextAlign.Center)

      Button(this.isServiceRunning ? '停止监控服务' : '启动监控服务')
        .width(200)
        .height(50)
        .backgroundColor(this.isServiceRunning ? Color.Red : Color.Blue)
        .onClick(() => {
          if (this.isServiceRunning) {
            this.stopMonitorService();
          } else {
            this.startMonitorService();
          }
        })

      Text('功能说明：')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .margin({ top: 20 }) // 调整边距

      Text('• 后台监控设备网络状态\n• 定期广播设备信息\n• 收集网络接口数据\n• 简化版Python监控脚本功能')
        .fontSize(14)
        .fontColor(Color.Gray)
        .textAlign(TextAlign.Start)
        .width('90%')

      // 新增日志显示区域
      Scroll() {
        Text(this.runtimeLog)
          .fontSize(12)
          .textAlign(TextAlign.Start)
          .width('100%')
          .fontColor(Color.Black) // 确保日志可见
      }
      .layoutWeight(1) //使其填充剩余空间
      .backgroundColor(Color.White)
      .borderColor(Color.Gray)
      .borderWidth(1)
      .width('90%')
      .margin({ top: 10 })
      .padding(5)

    }
    .height('100%')
    .width('100%')
    .padding(20)
    .justifyContent(FlexAlign.Center)
  }

  private async startMonitorService(): Promise<void> {
    try {
      const startMsg = 'Starting monitor service...';
      hilog.info(DOMAIN, TAG, startMsg);
      this.addLog(startMsg);
      
      await updateLocalIpGlobal(); // 确保在启动服务前获取最新的本地IP
      this.addLog("本机IP为" + localIp);
      
      await updateMacGlobal(); // 确保在启动服务前获取最新的MAC地址
      this.addLog("设备MAC地址为" + mac);
      
      await updateSnGlobal(); // 确保在启动服务前获取最新的SN
      this.addLog("设备SN为" + sn);
      
      await updateCpuTempGlobal(); // 确保在启动服务前获取最新的 CPU 温度
      this.addLog("CPU温度为" + cpuTemp + "°C");

      await updateTimeGlobal(); // 确保在启动服务前获取最新的时间
      this.addLog("当前时间为" + time);

      await updateUpTimeGlobal(); // 确保在启动服务前获取最新的运行时间
      this.addLog("设备运行时间为" + upTime + "天");

      await updateNetGlobal("wlan0"); // 确保在启动服务前获取最新的网络信息
      this.addLog(`网络接口 ${net.netInterface} 的接收速率为 ${net.rxRate} B/s,发送速率为 ${net.txRate} B/s`);

      await updateDiskGlobal("/"); // <-- Added: Update and log disk info
      this.addLog(`磁盘 ${disk.mounted} 总空间: ${disk.total} Bytes, 已用: ${disk.used} Bytes (${disk.percent}%)`);

      await updateCpuPercentGlobal(); // 更新 CPU 使用率
      this.addLog(`CPU 使用率为 ${cpuLoad}%`);

      await updateMemGlobal(); // 更新内存信息
      this.addLog(`内存使用率: ${mem.memLoad}%, 总量: ${mem.memTotal} Bytes, 已用: ${mem.memUsed} Bytes`);

      if (!this.udpSocketBound) {
        try {
          await udpSocket.bind({ address: '0.0.0.0', port: LOCAL_UDP_PORT, family: 0 });
          this.addLog(`Global UDP socket bound successfully to port ${LOCAL_UDP_PORT} for IPv4.`);
          hilog.info(DOMAIN, TAG, `Global UDP socket bound successfully to port ${LOCAL_UDP_PORT} for IPv4.`);
          this.udpSocketBound = true;
        } catch (bindError) {
          const bindErrorMsg = `Failed to bind global UDP socket to port ${LOCAL_UDP_PORT}: ${JSON.stringify(bindError)}.`;
          hilog.error(DOMAIN, TAG, bindErrorMsg);
          this.addLog(bindErrorMsg);
        }
      }

      if (this.udpSocketBound) {
        await sendDeviceInfoViaUDP(); // 发送第一次信息
        this.addLog(`Initial device info sent to ${TARGET_UDP_IP}:${TARGET_UDP_PORT}`);

        // --- BEGIN: Start periodic UDP sending ---
        if (this.sendIntervalId === -1) { // 确保只有一个定时器在运行
          this.sendIntervalId = setInterval(async () => {
            try {
              await sendDeviceInfoViaUDP(); // 定期发送信息
              // 您可以在这里添加一个日志，确认定期发送成功，但为了避免日志过于频繁，可以考虑去掉
               this.addLog(`Periodic device info sent to ${TARGET_UDP_IP}:${TARGET_UDP_PORT}`);
              hilog.debug(DOMAIN, TAG, `Periodic device info sent.`);
            } catch (e) {
              const periodicErrorMsg = `Error in periodic UDP send: ${JSON.stringify(e)}`;
              hilog.error(DOMAIN, TAG, periodicErrorMsg);
              this.addLog(periodicErrorMsg); // 只在出错时记录到UI日志
            }
          }, 5000); // 5000 毫秒 = 5 秒
          this.addLog('Started periodic UDP sending every 5 seconds.');
          hilog.info(DOMAIN, TAG, 'Started periodic UDP sending every 5 seconds.');
        }
        // --- END: Start periodic UDP sending ---

      } else {
        this.addLog(`Skipping sending device info as UDP socket is not bound to port ${LOCAL_UDP_PORT}.`);
      }
      
      //this.monitorManager.startMonitoring();
      
      this.isServiceRunning = true;
      this.serviceStatus = '监控服务已启动';
      const successMsg = 'Monitor service started successfully';
      hilog.info(DOMAIN, TAG, successMsg);
      this.addLog(successMsg);
    } catch (error) {
      const errorMsg = `Failed to start monitor service: ${JSON.stringify(error)}`;
      hilog.error(DOMAIN, TAG, errorMsg);
      this.addLog(errorMsg);
      this.serviceStatus = '启动服务失败';
    }
  }

  private stopMonitorService(): void {
    try {
      const stopMsg = 'Stopping monitor service...';
      hilog.info(DOMAIN, TAG, stopMsg);
      this.addLog(stopMsg);

      // --- BEGIN: Stop periodic UDP sending ---
      if (this.sendIntervalId !== -1) {
        clearInterval(this.sendIntervalId);
        this.sendIntervalId = -1; // 重置定时器ID
        this.addLog('Stopped periodic UDP sending.');
        hilog.info(DOMAIN, TAG, 'Stopped periodic UDP sending.');
      }
      // --- END: Stop periodic UDP sending ---
      
      //this.monitorManager.stopMonitoring();
      
      this.isServiceRunning = false;
      this.serviceStatus = '监控服务已停止';
      const successMsg = 'Monitor service stopped successfully';
      hilog.info(DOMAIN, TAG, successMsg);
      this.addLog(successMsg);

      // 可选：如果socket不再使用，可以关闭
      // if (this.udpSocketBound) {
      //   udpSocket.close().then(() => {
      //     this.addLog('Global UDP socket closed.');
      //     this.udpSocketBound = false;
      //   }).catch(e => this.addLog(`Error closing UDP socket: ${e.message}`));
      // }
    } catch (error) {
      const errorMsg = `Failed to stop monitor service: ${JSON.stringify(error)}`;
      hilog.error(DOMAIN, TAG, errorMsg);
      this.addLog(errorMsg);
      this.serviceStatus = '停止服务失败';
    }
  }
}