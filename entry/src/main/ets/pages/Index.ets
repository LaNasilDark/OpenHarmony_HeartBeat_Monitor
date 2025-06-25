import hilog from '@ohos.hilog';
import { DeviceMonitor, MonitorConfig, DeviceInfo } from '../common/DeviceMonitor';
import bundleManager from '@ohos.bundle.bundleManager';
import abilityAccessCtrl, { PermissionRequestResult, Permissions } from '@ohos.abilityAccessCtrl';


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
  @State aplLevel: string = '未知';
  @State bundleInfo: string = '获取中...';
  private monitor: DeviceMonitor = new DeviceMonitor(monitorConfig);

  public addLog(log: string): void {
    const now = new Date();
    const timestamp = `${now.getHours()}:${now.getMinutes()}:${now.getSeconds()}.${now.getMilliseconds()}`;
    this.runtimeLog += `[${timestamp}] ${log}\n`;
  }

  private async checkAplLevel(): Promise<void> {
    try {
      // 获取当前应用的包名
      const context = getContext(this);
      const bundleName = context.applicationInfo.name;
      
      // 查询应用信息
      const applicationInfo = await bundleManager.getApplicationInfo(bundleName, 
        bundleManager.ApplicationFlag.GET_APPLICATION_INFO_DEFAULT);
      this.addLog(`查询应用信息成功: ${JSON.stringify(applicationInfo)}`);
      //hilog.info(DOMAIN, TAG, `查询应用信息成功: ${JSON.stringify(applicationInfo)}`);
      // APL级别映射
      const aplLevelMap: Map<string, string> = new Map([
        ['1', 'normal (普通应用)'],
        ['2', 'system_basic (基础系统应用)'],
        ['3', 'system_core (核心系统应用)']
      ]);
      
      this.aplLevel = aplLevelMap.get(applicationInfo.appProvisionType.toString()) || `未知级别(${applicationInfo.appProvisionType})`;
      this.bundleInfo = `包名: ${bundleName}\nAPL级别: ${this.aplLevel}`;
      
      this.addLog(`当前应用APL级别: ${this.aplLevel}`);
      
      // 检查关键权限是否被授予
      await this.checkCriticalPermissions();
      
    } catch (error) {
      const errorMsg = `查询APL级别失败: ${JSON.stringify(error)}`;
      this.addLog(errorMsg);
      hilog.error(DOMAIN, TAG, errorMsg);
    }
  }

  // 检查关键权限状态
  private async checkCriticalPermissions(): Promise<void> {
    const criticalPermissions: Array<Permissions> = [
      'ohos.permission.RECEIVER_STARTUP_COMPLETED',
      'ohos.permission.MANAGE_APP_BOOT'
    ];
    const atManager = abilityAccessCtrl.createAtManager();

    for (const permission of criticalPermissions) {
      try {
        const context = getContext(this);
        const result: PermissionRequestResult = await atManager.requestPermissionsFromUser(context, [permission]);
        // 注意：系统级权限通常不能通过用户授权获得，这里主要是检查状态
        this.addLog(`权限 ${permission}: ${result.authResults[0] === 0 ? '已授予' : '未授予'}`);
      } catch (error) {
        this.addLog(`检查权限 ${permission} 失败: ${JSON.stringify(error)}`);
      }
    }
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

      Text('功能说明：')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .margin({ top: 20 }) // 调整边距

      Text('• 后台监控设备网络状态\n• 定期广播设备信息\n• 收集网络接口数据\n• 简化版Python监控脚本功能')
        .fontSize(14)
        .fontColor(Color.Gray)
        .textAlign(TextAlign.Start)
        .width('90%')

      Text(this.bundleInfo)
        .fontSize(14)
        .fontColor(Color.Blue)
        .textAlign(TextAlign.Center)
        .margin({ top: 10 })

      Button('检查APL级别')
        .width(150)
        .height(40)
        .backgroundColor(Color.Orange)
        .onClick(() => {
          this.checkAplLevel();
        })
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