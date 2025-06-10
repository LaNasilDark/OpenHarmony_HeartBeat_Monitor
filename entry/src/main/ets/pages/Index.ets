import hilog from '@ohos.hilog';
//import { SimpleMonitorManager } from '../monitorservice/SimpleMonitorManager';
import socket from '@ohos.net.socket';
import wifiManager from '@ohos.wifiManager';
import systemDateTime from '@ohos.systemDateTime';
import util from '@ohos.util';
import fs from '@ohos.file.fs';

interface DeviceInfo {
  ipAddress: string;
  cpuTemperature: string;
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


// --- BEGIN: New function to send device info via UDP ---
async function sendDeviceInfoViaUDP(): Promise<void> {
  try {
    // 1. 确保 CPU 温度是最新的
    await updateCpuTempGlobal();
    await updateLocalIpGlobal();
    // 2. 准备要发送的数据
    const deviceInfo: DeviceInfo = { // 使用定义的接口
      ipAddress: localIp,
      cpuTemperature: cpuTemp
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
    // 您可以在此处的 addLog 调用中访问 this，如果此函数是 Index 类的方法
    // 如果是全局函数，则不能直接使用 this.addLog
  }
}
// --- END: New function to send device info via UDP ---

(async () => {
  await updateCpuTempGlobal();
  await updateLocalIpGlobal();
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

  private addLog(log: string): void {
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

      await updateCpuTempGlobal(); // 确保在启动服务前获取最新的 CPU 温度
      this.addLog("CPU温度为" + cpuTemp + "°C");

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