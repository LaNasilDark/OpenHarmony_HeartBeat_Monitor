import hilog from '@ohos.hilog';
import { DeviceMonitor, MonitorConfig, DeviceInfo } from '../common/DeviceMonitor';
//import wifi from '@ohos.wifiManager';
import wifi from '@ohos.wifi';
import { BusinessError } from '@ohos.base';
import connection from '@ohos.net.connection';
//import fs from '@ohos.file.fs';
//import common from '@ohos.app.ability.common';
import ethernet from '@ohos.net.ethernet';
import { fileIo as fs } from '@kit.CoreFileKit';


const TAG: string = 'IndexPage';
const DOMAIN: number = 0x0001;



// 监控配置
const monitorConfig: MonitorConfig = {
  targetUdpIp: "192.168.5.5", // 请替换为您的目标IP地址
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
  
  @State staticIpAddress: string = "10.0.90.200";
  @State staticGateway: string = "10.0.90.254";
  @State staticDns: string = "10.0.2.2";

  private monitor: DeviceMonitor = new DeviceMonitor(monitorConfig);

  async aboutToAppear() {
    this.addLog('组件即将加载...');

    // 动态检测并设置网络接口
    try {
      const defaultNet = await connection.getDefaultNet();
      if (defaultNet) {
        const netCaps = await connection.getNetCapabilities(defaultNet);
        if (netCaps.bearerTypes.includes(connection.NetBearType.BEARER_WIFI)) {
          monitorConfig.networkInterface = 'wlan0';
          this.addLog('检测到默认网络为Wi-Fi，使用接口 wlan0');
        } else if (netCaps.bearerTypes.includes(connection.NetBearType.BEARER_ETHERNET)) {
          monitorConfig.networkInterface = 'eth0';
          this.addLog('检测到默认网络为以太网，使用接口 eth0');
        }
        // 使用更新后的配置重新创建监控实例，确保配置生效
        this.monitor = new DeviceMonitor(monitorConfig);
      } else {
        this.addLog('未检测到默认网络连接。将使用默认配置 wlan0');
      }
    } catch(e) {
      this.addLog(`检测网络接口失败: ${JSON.stringify(e)}`);
    }

    this.addLog('自动配置网络并启动监控服务...');
    this.configureNetwork(0); // 尝试配置以太网
    this.startMonitorService();
    hilog.info(DOMAIN, TAG, 'Index component is about to appear.');
  }

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
      
      Column({ space: 5 }) {
        Text('静态Wi-Fi配置').fontSize(16).width('90%').textAlign(TextAlign.Start)
        TextInput({ placeholder: '静态IP地址', text: this.staticIpAddress })
          .onChange((value: string) => { this.staticIpAddress = value; })
          .width('90%').height(40)
        TextInput({ placeholder: '网关地址', text: this.staticGateway })
          .onChange((value: string) => { this.staticGateway = value; })
          .width('90%').height(40)
        TextInput({ placeholder: 'DNS服务器', text: this.staticDns })
          .onChange((value: string) => { this.staticDns = value; })
          .width('90%').height(40)
      }
      .alignItems(HorizontalAlign.Center)
      .margin({ top: 10 })


      Button('配置WiFi网络')
        .width(200)
        .height(50)
        .margin({ top: 10 })
        .onClick(() => {
          this.configureNetwork(1);
        })
      Button('忘记所有Wi-Fi')
        .width(200)
        .height(50)
        .margin({ top: 5 })
        .backgroundColor(Color.Orange)
        .onClick(() => {
          this.forgetAllWifiNetworks();
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

   private async configureNetwork(mode:number): Promise<void> {
    switch (mode) {
      case 0:
        let config: ethernet.InterfaceConfiguration ={
          mode: ethernet.IPSetMode.STATIC,
          ipAddr: "192.168.5.114",
          route: "192.168.5.0",
          gateway: "192.168.5.1",
          netMask: "255.255.255.0",
          dnsServers: "0.0.0.0"
        };
        ethernet.setIfaceConfig("eth0", config, (error: BusinessError) => {
          if (error) {
            console.error("setIfaceConfig callback error = " + JSON.stringify(error));
          } else {
            console.log("setIfaceConfig callback ok");
          }
        });

      case 1: //目前wifi配置模式存在bug：由于无法清除/data/service/el1/public/dhcp/内的缓存文件，导致无法添加新的wifi配置
        this.addLog('模式 1: 开始配置Wi-Fi网络...');
        try {
          // 检查Wi-Fi是否已激活
          if (!wifi.isWifiActive()) {
            this.addLog('Wi-Fi 未激活，正在尝试启动...');
            wifi.enableWifi();
            await sleep(2000); // 等待Wi-Fi启动
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

        try {
          // --- 新增: IP字符串转整数 ---
          const ipAddressInt = this.ipToInt(this.staticIpAddress);
          const gatewayInt = this.ipToInt(this.staticGateway);
          const dnsInt = this.ipToInt(this.staticDns);

          if (ipAddressInt === 0 || gatewayInt === 0 || dnsInt === 0) {
            this.addLog('无效的IP地址、网关或DNS格式,请检查后重试。');
            return;
          }

          const ssid = "JDSK"; // 目标网络SSID

          // 1. 断开当前连接
          this.addLog('正在断开当前Wi-Fi连接...');
          wifi.disconnect();
          await sleep(2000); // 等待断开完成

          // 2. 移除旧的配置
          try {
            const configs = wifi.getDeviceConfigs();
            const oldConfig = configs.find(c => c.ssid === ssid);
            if (oldConfig) {
              this.addLog(`发现旧的网络配置 (NetId: ${oldConfig.netId})，正在移除...`);
              wifi.disableNetwork(oldConfig.netId);
              wifi.removeDevice(oldConfig.netId);
              this.addLog('旧配置移除成功。');
              await sleep(1000);
              //return;
            }
          } catch (removeError) {
            this.addLog(`移除旧配置时发生非致命错误: ${JSON.stringify(removeError)}`);
          }

          //处理dhcp缓存配置
          fs.unlink("/data/service/el1/public/dhcp/dhcp_cache.conf")
            .then(() => {
              this.addLog('已清除DHCP缓存配置。');
            })
            .catch((unlinkError: BusinessError) => {
              this.addLog(`清除DHCP缓存配置失败: ${JSON.stringify(unlinkError)}`);
            });

          // 3. 创建并添加新的网络配置
          let deviceConfig: wifi.WifiDeviceConfig = {
            ssid: ssid,
            bssid: "c4:69:f0:e7:4c:81",
            preSharedKey: "SpaceT20211102",
            isHiddenSsid: false,
            securityType: wifi.WifiSecurityType.WIFI_SEC_TYPE_PSK,
            creatorUid: 0,
            disableReason: 0,
            netId: 0,
            randomMacType: 0,
            randomMacAddr: "5c.8a.ae.67.5f.ab",
            ipType: wifi.IpType.STATIC,
            staticIp: {
              ipAddress: ipAddressInt,
              gateway: gatewayInt,
              dnsServers: [dnsInt],
              domains: ["dc.com"]
            }
          };

          this.addLog('正在添加新的Wi-Fi配置...');
          const newNetId = await wifi.addDeviceConfig(deviceConfig);
          this.addLog(`添加新Wi-Fi配置成功, 网络ID: ${newNetId}`);

          // 4. 使用新配置进行连接
          this.addLog(`正在连接到网络: ${deviceConfig.ssid}`);
          await sleep(1000);
          const connectResult = wifi.connectToNetwork(newNetId);
          if (connectResult) {
            this.addLog(`连接指令已成功发送到网络: ${deviceConfig.ssid}`);
          } else {
            this.addLog(`发送连接指令失败。`);
          }

        } catch (error) {
          const err = error as BusinessError;
          hilog.error(DOMAIN, TAG, `Wi-Fi配置失败: ${JSON.stringify(err)}`);
          this.addLog(`Wi-Fi配置失败: ${JSON.stringify(err)}`);
          this.addLog('请检查应用权限及参数。');
        }
        break;

      default:
        this.addLog(`未知的配置模式: ${mode}`);
        break;
    }
  }



   private async forgetAllWifiNetworks(): Promise<void> {
    this.addLog('开始清除所有已保存的Wi-Fi网络...');
    try {
      // 1. 检查Wi-Fi是否已激活，未激活则无法获取配置
      if (!wifi.isWifiActive()) {
        this.addLog('Wi-Fi 未激活,无法执行操作。请先打开Wi-Fi。');
        return;
      }

      // 2. 获取所有已保存的网络配置
      const savedNetworks = wifi.getDeviceConfigs();

      if (savedNetworks.length === 0) {
        this.addLog('没有找到已保存的Wi-Fi网络。');
        return;
      }

      this.addLog(`发现 ${savedNetworks.length} 个网络，正在逐个移除...`);
      let successCount = 0;
      let failCount = 0;

      // 3. 遍历并逐个移除
      for (const network of savedNetworks) {
        try {
          this.addLog(`正在移除: ${network.ssid} (NetId: ${network.netId})`);
          // 首先禁用网络，这是一种更稳妥的做法
          wifi.disableNetwork(network.netId);
          // 然后移除网络配置
          wifi.removeDevice(network.netId);
          this.addLog(`成功移除网络: ${network.ssid}`);
          successCount++;
        } catch (innerError) {
          const err = innerError as BusinessError;
          this.addLog(`移除网络 ${network.ssid} 时出错: ${err.message}`);
          failCount++;
        }
      }
      this.addLog(`操作完成。成功移除 ${successCount} 个网络，失败 ${failCount} 个。`);
      // 操作完成后可以断开当前连接，确保处于干净状态
      wifi.disconnect();

    } catch (error) {
      const err = error as BusinessError;
      const errorMessage = `清除所有Wi-Fi网络失败: ${err.message}`;
      hilog.error(DOMAIN, TAG, errorMessage, err);
      this.addLog(errorMessage);
      this.addLog('请确保应用拥有 ohos.permission.SET_WIFI_CONFIG 系统权限。');
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

  private ipToInt(ip: string): number {
    const parts = ip.split('.');
    if (parts.length !== 4) {
      return 0; // 无效格式
    }
    let result = 0;
    for (let i = 0; i < 4; i++) {
      const part = parseInt(parts[i], 10);
      if (isNaN(part) || part < 0 || part > 255) {
        return 0; // 无效部分
      }
      result |= part << ((3 - i) * 8);
    }
    return result >>> 0; // 转换为无符号32位整数
  }
}


function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}