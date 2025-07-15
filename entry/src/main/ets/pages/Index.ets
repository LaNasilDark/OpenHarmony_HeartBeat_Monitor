import hilog from '@ohos.hilog';
import { DeviceMonitor, MonitorConfig, DeviceInfo, WifiConfig, EthernetConfig } from '../common/DeviceMonitor';
import wifi from '@ohos.wifi';
import { BusinessError } from '@ohos.base';

const TAG: string = 'IndexPage';
const DOMAIN: number = 0x0001;

// 监控配置
const monitorConfig: MonitorConfig = {
  targetUdpIp: "192.168.5.5", // 请替换为您的目标IP地址
  targetUdpPort: 9990,
  localUdpPort: 9991,
  agentVersion: '1.14514',
  networkInterface: 'wlan0', // 将由自动检测更新
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
  @State targetIp: string = monitorConfig.targetUdpIp;

  // Wi-Fi 配置状态
  @State wifiSsid: string = "JDSK";
  @State wifiBssid: string = "c4:69:f0:e7:4c:81";
  @State wifiKey: string = "SpaceT20211102";
  @State staticIpAddress: string = "10.0.90.200";
  @State staticGateway: string = "10.0.90.254";
  @State staticDns: string = "10.0.2.2";

  // 以太网配置状态
  @State ethIpAddress: string = "192.168.5.114";
  @State ethGateway: string = "192.168.5.1";
  @State ethNetmask: string = "255.255.255.0";
  @State ethDns: string = "192.168.5.1";


  private monitor: DeviceMonitor | null = null;

  async aboutToAppear() {
    // 在 aboutToAppear 中初始化 monitor
    if (!this.monitor) {
      monitorConfig.logCallback = this.addLog.bind(this);
      this.monitor = new DeviceMonitor(monitorConfig);
    }

    this.addLog('组件即将加载...');
    await this.monitor.autoDetectNetworkInterface();
    this.addLog('自动配置网络并启动监控服务...');
    await this.configureNetwork(0); // 尝试配置以太网
    await this.startMonitorService();
    hilog.info(DOMAIN, TAG, 'Index component is about to appear.');
  }

  public addLog(log: string): void {
    const now = new Date();
    const timestamp = `${now.getHours()}:${now.getMinutes()}:${now.getSeconds()}.${now.getMilliseconds()}`;
    this.runtimeLog += `[${timestamp}] ${log}\n`;
  }

  build() {
    Column({ space: 10 }) {
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

      // Wi-Fi 配置区域
      Column({ space: 5 }) {
        Text('静态Wi-Fi配置').fontSize(16).width('90%').textAlign(TextAlign.Start)
        TextInput({ placeholder: 'SSID', text: this.wifiSsid }).onChange(v => this.wifiSsid = v).width('90%').height(40)
        TextInput({ placeholder: '密码', text: this.wifiKey }).onChange(v => this.wifiKey = v).width('90%').height(40)
        TextInput({ placeholder: '静态IP地址', text: this.staticIpAddress }).onChange(v => this.staticIpAddress = v).width('90%').height(40)
        TextInput({ placeholder: '网关地址', text: this.staticGateway }).onChange(v => this.staticGateway = v).width('90%').height(40)
        TextInput({ placeholder: 'DNS服务器', text: this.staticDns }).onChange(v => this.staticDns = v).width('90%').height(40)
        Row({ space: 10 }) {
          Button('配置WiFi').width(150).height(50).margin({ top: 10 }).onClick(() => this.configureNetwork(1))
          Button('忘记所有WiFi').width(150).height(50).margin({ top: 10 }).backgroundColor(Color.Orange).onClick(() => this.monitor?.forgetAllWifiNetworks())
        }
      }
      .alignItems(HorizontalAlign.Center)
      .margin({ top: 10 })

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


      // 日志显示区域
      Scroll() {
        Text(this.runtimeLog)
          .fontSize(12)
          .textAlign(TextAlign.Start)
          .width('100%')
          .fontColor(Color.Black)
      }
      .layoutWeight(1)
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
    const ipRegex = /^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/;
    if (!ipRegex.test(this.targetIp)) {
      this.addLog(`无效的IP地址格式: ${this.targetIp}`);
      return;
    }

    this.monitor?.updateConfig({ targetUdpIp: this.targetIp });
    this.addLog(`目标UDP IP已更新为: ${this.targetIp}`);
  }

  private async startMonitorService(): Promise<void> {
    if (!this.monitor) return;
    try {
      this.addLog('正在启动监控服务...');
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

      await this.monitor.startMonitoring();

      this.isServiceRunning = true;
      this.serviceStatus = '监控服务已启动';
    } catch (error) {
      const err = error as BusinessError;
      this.addLog(`启动监控服务失败: ${err.message}`);
      this.serviceStatus = '启动服务失败';
    }
  }

  private async configureNetwork(mode: number): Promise<void> {
    if (!this.monitor) return;
    try {
      if (this.isServiceRunning) {
        this.addLog('配置网络前请先停止监控服务。');
        return;
      }
      if (mode === 0) {
        const ethConfig: EthernetConfig = {
          ipAddress: this.ethIpAddress,
          gateway: this.ethGateway,
          netmask: this.ethNetmask,
          dns: this.ethDns
        };
        await this.monitor.configureNetwork(0, ethConfig);
      } else if (mode === 1) {
        const wifiConfig: WifiConfig = {
          ssid: this.wifiSsid,
          bssid: this.wifiBssid,
          preSharedKey: this.wifiKey,
          isHiddenSsid: false,
          securityType: wifi.WifiSecurityType.WIFI_SEC_TYPE_PSK,
          ipAddress: this.staticIpAddress,
          gateway: this.staticGateway,
          dns: this.staticDns
        };
        await this.monitor.configureNetwork(1, undefined, wifiConfig);
      } else {
        this.addLog(`未知的配置模式: ${mode}`);
      }
    } catch (error) {
      const err = error as BusinessError;
      this.addLog(`网络配置失败: ${err.message}`);
    }
  }

  private stopMonitorService(): void {
    if (!this.monitor) return;
    try {
      this.addLog('正在停止监控服务...');
      this.monitor.stopMonitoring();
      this.isServiceRunning = false;
      this.serviceStatus = '监控服务已停止';
    } catch (error) {
      const err = error as BusinessError;
      this.addLog(`停止服务失败: ${err.message}`);
      this.serviceStatus = '停止服务失败';
    }
  }
}