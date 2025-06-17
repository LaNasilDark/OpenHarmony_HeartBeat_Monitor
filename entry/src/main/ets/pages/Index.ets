import hilog from '@ohos.hilog';
import socket from '@ohos.net.socket';
import wifiManager from '@ohos.wifiManager';
import systemDateTime from '@ohos.systemDateTime';
import util from '@ohos.util';
import fs from '@ohos.file.fs';

interface DeviceInfo {
  ipAddress: string;
  cpuTemperature: string;
  sn: string;
  time: string;
  mac: string;
  upTime: string;
  net: NetObjectType;   
}
interface NetObjectType {
  netInterface: string;
  txByte: string;
  txRate: string;
  rxByte: string;
  rxRate: string;
  unit: string; // 可选属性 
}
interface ParsedNetStats {
  rxBytes: number;
  txBytes: number;
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
  netInterface: 'Loading...',
  txByte: 'Loading...',
  txRate: 'Loading...',
  rxByte: 'Loading...',
  rxRate: 'Loading...',
  unit: 'Bytes/s'
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

// {'cpuLoad': 4.1, 'memInfo': {'memTotal': 16780967936, 'memLoad': 69.8, 'memUsed': 11710365696, 'memAvailable': 5070602240, 'unit': 'Byte'}, 'disk': {'mounted': '/', 'available': 160797757440, 'total': 322000908288, 'percent': 50, 'used': 161203150848, 'unit': 'Byte'}, 'net': {'netInterface': 'Done', 'txByte': 94729625, 'txRate': 0, 'rxByte': 5531100835, 'rxRate': 12128, 'unit': 'Bytes/s'}, 'mac': Done, 'ip': Done, 'upTime': Done, 'time': Done, 'sn': Done, 'cpuTemp': Done, 'agentVersion': '1.14514'}
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
    txByte: 'N/A',
    txRate: 'N/A',
    rxByte: 'N/A',
    rxRate: 'N/A',
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
      rxByte: finalStats.rxBytes.toString(), // Total received bytes at the end of interval
      txByte: finalStats.txBytes.toString(), // Total transmitted bytes at the end of interval
      rxRate: rxRate.toString(),
      txRate: txRate.toString(),
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
      txByte: 'Error',
      txRate: 'Error',
      rxByte: 'Error',
      rxRate: 'Error',
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
    // 2. 准备要发送的数据

    

    const deviceInfo: DeviceInfo = { // 使用定义的接口
      ipAddress: localIp,
      cpuTemperature: cpuTemp,
      sn: sn,
      time: time,
      mac: mac, // 新增 MAC 地址字段
      upTime: upTime, // 新增运行时间字段
      net: net 
    };
    const messageString = JSON.stringify(deviceInfo);
    const encoder = new util.TextEncoder();
    const dataToSendBuffer = encoder.encode(messageString).buffer;

    // 3. 定义远程地址信息，使用 socket.NetAddress
    const remoteAddress: socket.NetAddress = { // 改为 socket.NetAddress
      address: TARGET_UDP_IP,
      port: TARGET_UDP_PORT,
      family: 0 // 0 代表 IPv4，与 TARGET_UDP_IP 格式匹配
    };

    // 4. 发送数据
    await udpSocket.send({
      data: dataToSendBuffer,
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
      this.addLog(`网络接口 ${net.netInterface} 的接收速率为 ${net.rxRate} B/s，发送速率为 ${net.txRate} B/s`);

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