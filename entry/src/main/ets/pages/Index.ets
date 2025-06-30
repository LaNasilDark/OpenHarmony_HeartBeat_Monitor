import hilog from '@ohos.hilog';
import { DeviceMonitor, MonitorConfig, DeviceInfo } from '../common/DeviceMonitor';
import ethernet from '@ohos.net.ethernet';
import { BusinessError } from '@ohos.base';
import connection from '@ohos.net.connection';
import fs from '@ohos.file.fs';
import common from '@ohos.app.ability.common';



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
      Button('读取Wi-Fi配置')
        .width(200)
        .height(50)
        .margin({ top: 10 })
        .onClick(() => {
          this.readWifiConfig();
        })

      Button('获取沙盒路径')
        .width(200)
        .height(50)
        .margin({ top: 10 })
        .onClick(() => {
          this.getSandboxPath();
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

  private getSandboxPath(): void {
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
  }

  private async startMonitorService(): Promise<void> {
    try {
      const startMsg = 'Starting monitor service...';
      hilog.info(DOMAIN, TAG, startMsg);
      this.addLog(startMsg);
      /*
      // 1. 动态获取网络接口
      let defaultNet = await connection.getDefaultNet();
      if (!defaultNet) {
        this.addLog('获取默认网络失败，请检查网络连接');
        hilog.error(DOMAIN, TAG, 'Failed to get default net');
        this.serviceStatus = '启动服务失败';
        return;
      }
      let connProperties = await connection.getConnectionProperties(defaultNet);
      const ifaceName = connProperties.interfaceName;
      this.addLog(`获取到活动网络接口: ${ifaceName}`);

      // 2. 使用获取到的接口名称进行配置
      let InterfaceConfiguration: ethernet.InterfaceConfiguration = {
        mode: ethernet.IPSetMode.STATIC,
        ipAddr: "10.0.90.248",
        route: "10.0.71.254",
        gateway: "10.0.71.254",
        netMask: "255.255.254.0",
        dnsServers: "8.8.8.8",
      }

      try {
        await ethernet.setIfaceConfig(ifaceName, InterfaceConfiguration)
        hilog.info(DOMAIN,TAG, `设置${ifaceName}接口配置成功: ${JSON.stringify(InterfaceConfiguration)}`);
        this.addLog(`设置${ifaceName}接口配置成功: ${JSON.stringify(InterfaceConfiguration)}`);
      } catch (error) {
        const err = error as BusinessError;
        hilog.error(DOMAIN, TAG, `设置${ifaceName}接口配置失败: ${JSON.stringify(err)}`);
        this.addLog(`设置${ifaceName}接口配置失败: ${JSON.stringify(err)}`);
        // 如果设置IP失败，可以选择是否要继续执行
        // this.serviceStatus = '启动服务失败';
        // return;
      }
      */

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