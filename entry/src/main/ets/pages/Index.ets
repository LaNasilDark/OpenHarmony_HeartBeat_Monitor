import hilog from '@ohos.hilog';
import { DeviceMonitor, MonitorConfig, DeviceInfo } from '../common/DeviceMonitor';
import wifi from '@ohos.wifiManager';
import { BusinessError } from '@ohos.base';
//import connection from '@ohos.net.connection';
//import fs from '@ohos.file.fs';
//import common from '@ohos.app.ability.common';
//import ethernet from '@ohos.net.ethernet';


const TAG: string = 'IndexPage';
const DOMAIN: number = 0x0001;

// 监控配置
const monitorConfig: MonitorConfig = {
  targetUdpIp: "10.0.90.241", // 请替换为您的目标IP地址
  targetUdpPort: 9990,
  localUdpPort: 9991,
  agentVersion: '1.14514',
  networkInterface: 'wlan0',
  diskMountPath: '/data',
  collectInterval: 5000 // 5秒
};


@Entry
@Component
struct Index {
  @State message: string = 'OpenHarmony Heartbeat Monitor Beta';
  @State serviceStatus: string = '服务未启动';
  @State isServiceRunning: boolean = false;
  @State runtimeLog: string = '应用日志:\n';
  @State targetIp: string = monitorConfig.targetUdpIp; // 新增状态，用于绑定输入框
  private monitor: DeviceMonitor = new DeviceMonitor(monitorConfig);

  public addLog(log: string): void {
    const now = new Date();
    const timestamp = `${now.getHours()}:${now.getMinutes()}:${now.getSeconds()}.${now.getMilliseconds()}`;
    this.runtimeLog += `[${timestamp}] ${log}\n`;
  }

  build() {
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
      /*Button('读取Wi-Fi配置')
        .width(200)
        .height(50)
        .margin({ top: 10 })
        .onClick(() => {
          this.readWifiConfig();
        })*/

       Button('配置Wi-Fi网络')
        .width(200)
        .height(50)
        .margin({ top: 10 })
        .onClick(() => {
          this.configureWifi();
        })

      /*Button('获取沙盒路径')
        .width(200)
        .height(50)
        .margin({ top: 10 })
        .onClick(() => {
          this.getSandboxPath();
        })*/  
      Row({ space: 10 }) {
        TextInput({ placeholder: '目标IP地址', text: this.targetIp })
          .onChange((value: string) => {
            this.targetIp = value;
          })
          .layoutWeight(1)
          .height(50)
          .fontSize(16)

        Button('设置UDP目标IP')
          .width(100)
          .height(50)
          .onClick(() => {
            this.setTargetIp();
          })
      }
      .width('90%')
      .margin({ top: 10 })
      .justifyContent(FlexAlign.Center)
     

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

  private setTargetIp(): void {
    if (this.isServiceRunning) {
      this.addLog('请先停止监控服务再修改IP地址。');
      return;
    }
    // 简单的IP地址格式验证
    const ipRegex = /^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/;
    if (!ipRegex.test(this.targetIp)) {
      this.addLog(`无效的IP地址格式: ${this.targetIp}`);
      return;
    }

    monitorConfig.targetUdpIp = this.targetIp;
    // 使用新的配置重新创建监控实例
    this.monitor = new DeviceMonitor(monitorConfig);
    const msg = `目标UDP IP已更新为: ${this.targetIp}`;
    this.addLog(msg);
    hilog.info(DOMAIN, TAG, msg);
  }

  /*private getSandboxPath(): void {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      this.addLog('获取应用沙盒路径成功:');
      this.addLog(`  - Cache Dir: ${context.cacheDir}`);
      this.addLog(`  - Files Dir: ${context.filesDir}`);
      if (context.distributedFilesDir) {
        this.addLog(`  - Distributed Files Dir: ${context.distributedFilesDir}`);
      }
    } catch (error) {
      const err = error as BusinessError;
      const errorMsg = `获取沙盒路径失败: ${JSON.stringify(err)}`;
      hilog.error(DOMAIN, TAG, errorMsg);
      this.addLog(errorMsg);
    }
  }

  private async readWifiConfig(): Promise<void> {
    const filePath = '/data/service/el1/public/wifi/device_config.conf';
    this.addLog(`尝试读取配置文件: ${filePath}`);
    try {
      // 检查文件是否存在
      const isExist = await fs.access(filePath);
      if (!isExist) {
        this.addLog(`文件不存在: ${filePath}`);
        hilog.error(DOMAIN, TAG, `File not found: ${filePath}`);
        return;
      }

      // 读取文件内容
      const content = await fs.readText(filePath);
      this.addLog('成功读取Wi-Fi配置文件内容:');
      this.addLog(content);
      hilog.info(DOMAIN, TAG, `Successfully read wifi config.`);

    } catch (error) {
      const err = error as BusinessError;
      const errorMsg = `读取文件失败: ${JSON.stringify(err)}`;
      hilog.error(DOMAIN, TAG, errorMsg);
      this.addLog(errorMsg);
      this.addLog('请检查应用是否具有读取该文件的权限。此路径可能需要系统应用权限。');
    }
  }*/

  private async startMonitorService(): Promise<void> {
    try {
      const startMsg = 'Starting monitor service...';
      hilog.info(DOMAIN, TAG, startMsg);
      this.addLog(startMsg);

      // 收集一次设备信息并日志展示
      const info: DeviceInfo = await this.monitor.collectDeviceInfo();
      this.addLog(`本机IP为${info.ipAddress}`);
      this.addLog(`设备MAC地址为${info.mac}`);
      this.addLog(`设备SN为${info.sn}`);
      this.addLog(`CPU温度为${info.cpuTemperature}°C`);
      this.addLog(`当前时间为${info.time}`);
      this.addLog(`设备运行时间为${info.upTime}天`);
      this.addLog(`网络接口${info.net.netInterface}的接收速率为${info.net.rxRate}B/s, 发送速率为${info.net.txRate}B/s`);
      this.addLog(`磁盘${info.disk.mounted} 总空间: ${info.disk.total} Bytes, 已用: ${info.disk.used} Bytes (${info.disk.percent}%)`);
      this.addLog(`CPU使用率为${info.cpuLoad}%`);
      this.addLog(`内存使用率: ${info.memInfo.memLoad}%, 总量: ${info.memInfo.memTotal} Bytes, 已用: ${info.memInfo.memUsed} Bytes`);

      // 启动监控服务（含UDP定时发送）
      await this.monitor.startMonitoring();
      this.addLog('Started periodic UDP sending every 5 seconds.');

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

  private async configureWifi(): Promise<void> {

     try {
      // 检查Wi-Fi是否已激活
      if (!wifi.isWifiActive()) {
        this.addLog('Wi-Fi 未激活，正在尝试启动...');
        await wifi.enableWifi();
        
        this.addLog('Wi-Fi 已成功启动。');
      } else {
        this.addLog('Wi-Fi 已处于激活状态。');
      }
    } catch (error) {
      const err = error as BusinessError;
      const errorMsg = `启动Wi-Fi失败: ${JSON.stringify(err)}`;
      hilog.error(DOMAIN, TAG, errorMsg);
      this.addLog(errorMsg);
      return; // 如果无法启动Wi-Fi，则中止后续操作
    }
    await sleep(500);
    this.addLog('开始配置Wi-Fi网络...');

    try {
      // 使用简化的配置对象（参考示例代码的做法）
      let deviceConfig: wifi.WifiDeviceConfig = {
        ssid: "JDSK",
        bssid: "c4:69:f0:e7:4c:81",
        preSharedKey: "SpaceT20211102",
        isHiddenSsid: false,
        securityType: wifi.WifiSecurityType.WIFI_SEC_TYPE_PSK // 使用枚举值
        

      };

      // 先添加配置
      const configResult = await wifi.addDeviceConfig(deviceConfig);
      this.addLog(`添加Wi-Fi配置成功,网络ID: ${configResult}`);

      // 然后尝试连接
      await wifi.connectToDevice(deviceConfig);
      this.addLog(`连接指令已发送到网络: ${deviceConfig.ssid}`);

    } catch (error) {
      const err = error as BusinessError;
      hilog.error(DOMAIN, TAG, `Wi-Fi配置失败: ${JSON.stringify(err)}`);
      this.addLog(`Wi-Fi配置失败: ${JSON.stringify(err)}`);
      this.addLog('请检查应用权限及参数。');
    }
  }

  private stopMonitorService(): void {
    try {
      const stopMsg = 'Stopping monitor service...';
      hilog.info(DOMAIN, TAG, stopMsg);
      this.addLog(stopMsg);

      this.monitor.stopMonitoring();
      this.addLog('Stopped periodic UDP sending.');

      this.isServiceRunning = false;
      this.serviceStatus = '监控服务已停止';
      const successMsg = 'Monitor service stopped successfully';
      hilog.info(DOMAIN, TAG, successMsg);
      this.addLog(successMsg);
    } catch (error) {
      const errorMsg = `Failed to stop monitor service: ${JSON.stringify(error)}`;
      hilog.error(DOMAIN, TAG, errorMsg);
      this.addLog(errorMsg);
      this.serviceStatus = '停止服务失败';
    }
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}