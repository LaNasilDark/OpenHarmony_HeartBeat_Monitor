import hilog from '@ohos.hilog';
import { DeviceMonitor } from '../common/DeviceMonitor';
import { MonitorConfig, DeviceInfo, WifiConfig, EthernetConfig } from '../common/types';
import { CommandResponse, WifiCommandData, EthernetCommandData, TargetIpCommandData, Command, BaseCommand } from '../common/CommandTypes';
import wifi from '@ohos.wifi';
import { BusinessError } from '@ohos.base';
import { socket } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';

const TextDecoder = util.TextDecoder;

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

  // 配网命令监听
  @State isCommandListening: boolean = false;
  private commandSocket: socket.UDPSocket | null = null;
  private commandListeningPort: number = 9992; // 命令监听端口

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

    await this.startCommandListener();

    hilog.info(DOMAIN, TAG, 'Index component is about to appear.');
  }

  private async startCommandListener(): Promise<void> {
    if (this.isCommandListening) {
      this.addLog('命令监听服务已在运行');
      return;
    }

    try {
      this.commandSocket = socket.constructUDPSocketInstance();
      
      // 绑定监听端口
      await this.commandSocket.bind({
        address: '0.0.0.0',
        port: this.commandListeningPort,
        family: 0
      });

      // 监听消息
      this.commandSocket.on('message', (value: socket.SocketMessageInfo) => {
        this.handleCommandMessage(value);
      });

      // 监听错误
      this.commandSocket.on('error', (err: BusinessError) => {
        this.addLog(`命令监听Socket错误: ${err.message}`);
      });

      // 监听关闭事件
      this.commandSocket.on('close', () => {
        this.addLog('命令监听Socket已关闭');
        this.isCommandListening = false;
      });

      this.isCommandListening = true;
      this.addLog(`命令监听服务已启动，监听端口: ${this.commandListeningPort}`);
    } catch (error) {
      const err = error as BusinessError;
      this.addLog(`启动命令监听服务失败: ${err.message}`);
      throw new Error(`启动命令监听服务失败: ${err.message}`);
    }
  }

  private handleCommandMessage(value: socket.SocketMessageInfo): void {
    try {
      // 将ArrayBuffer转换为字符串
      const uint8Array = new Uint8Array(value.message);
      const messageText = new TextDecoder('utf-8').decode(uint8Array);
      
      this.addLog(`收到命令: ${messageText} 来自: ${value.remoteInfo.address}:${value.remoteInfo.port}`);
      
      // 解析JSON命令
      const command = JSON.parse(messageText) as Command;
      
      // 将 SocketRemoteInfo 转换为 NetAddress
      const remoteNetAddress: socket.NetAddress = {
        address: value.remoteInfo.address,
        port: value.remoteInfo.port,
        family: value.remoteInfo.family === 'IPv4' ? 0 : 1
      };
      
      this.processCommand(command, remoteNetAddress);
      
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      this.addLog(`解析命令消息失败: ${errorMessage}`);
    }
  }

  // 处理具体命令
  private async processCommand(command: Command, remoteInfo: socket.NetAddress): Promise<void> {
    try {
      switch (command.type) {
        case 'configure_wifi':
          await this.handleWifiConfigCommand(command.data);
          break;
        case 'configure_ethernet':
          await this.handleEthernetConfigCommand(command.data);
          break;
        case 'forget_wifi':
          await this.handleForgetWifiCommand();
          break;
        case 'restart_monitor':
          await this.handleRestartMonitorCommand();
          break;
        case 'update_target_ip':
          await this.handleUpdateTargetIpCommand(command.data);
          break;
        default:
          this.addLog(`未知命令类型: ${(command as BaseCommand).type}`);
      }
      
      // 发送命令执行结果回复
      await this.sendCommandResponse(remoteInfo, {
        success: true,
        message: `命令 ${command.type} 执行成功`
      });
      
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      this.addLog(`执行命令失败: ${errorMessage}`);
      await this.sendCommandResponse(remoteInfo, {
        success: false,
        message: `命令执行失败: ${errorMessage}`
      });
    }
  }

  // 处理WiFi配网命令
  private async handleWifiConfigCommand(data: WifiCommandData): Promise<void> {
    this.addLog('收到WiFi配网命令，正在执行...');
    
    // 更新WiFi配置状态
    if (data.ssid) this.wifiSsid = data.ssid;
    if (data.password) this.wifiKey = data.password;
    if (data.ipAddress) this.staticIpAddress = data.ipAddress;
    if (data.gateway) this.staticGateway = data.gateway;
    if (data.dns) this.staticDns = data.dns;
    if (data.bssid) this.wifiBssid = data.bssid;
    
    // 停止监控服务并执行配网
    if (this.isServiceRunning) {
      this.stopMonitorService();
      await new Promise<void>(resolve => setTimeout(resolve, 2000));
    }
    
    await this.configureNetwork(1);
    
    // 重新启动监控服务
    await new Promise<void>(resolve => setTimeout(resolve, 3000));
    await this.startMonitorService();
  }

  // 处理以太网配网命令
  private async handleEthernetConfigCommand(data: EthernetCommandData): Promise<void> {
    this.addLog('收到以太网配网命令，正在执行...');
    
    // 更新以太网配置状态
    if (data.ipAddress) this.ethIpAddress = data.ipAddress;
    if (data.gateway) this.ethGateway = data.gateway;
    if (data.netmask) this.ethNetmask = data.netmask;
    if (data.dns) this.ethDns = data.dns;
    
    // 停止监控服务并执行配网
    if (this.isServiceRunning) {
      this.stopMonitorService();
      await new Promise<void>(resolve => setTimeout(resolve, 2000));
    }
    
    await this.configureNetwork(0);
    
    // 重新启动监控服务
    await new Promise<void>(resolve => setTimeout(resolve, 3000));
    await this.startMonitorService();
  }

  // 处理忘记WiFi命令
  private async handleForgetWifiCommand(): Promise<void> {
    this.addLog('收到忘记WiFi命令，正在执行...');
    await this.monitor?.forgetAllWifiNetworks();
  }

  // 处理重启监控服务命令
  private async handleRestartMonitorCommand(): Promise<void> {
    this.addLog('收到重启监控服务命令，正在执行...');
    if (this.isServiceRunning) {
      this.stopMonitorService();
      await new Promise<void>(resolve => setTimeout(resolve, 2000));
    }
    await this.startMonitorService();
  }

  // 处理更新目标IP命令
  private async handleUpdateTargetIpCommand(data: TargetIpCommandData): Promise<void> {
    this.addLog('收到更新目标IP命令，正在执行...');
    if (data.targetIp) {
      this.targetIp = data.targetIp;
      this.setTargetIp();
    }
  }

  // 发送命令响应
  private async sendCommandResponse(remoteInfo: socket.NetAddress, response: CommandResponse): Promise<void> {
    if (!this.commandSocket) return;
    
    try {
      const responseText = JSON.stringify(response);
      const encoder = new util.TextEncoder();
      const responseBytes = encoder.encode(responseText);
      
      await this.commandSocket.send({
        data: responseBytes.buffer,
        address: remoteInfo
      });
      
      this.addLog(`命令响应已发送到 ${remoteInfo.address}:${remoteInfo.port}`);
    } catch (error) {
      this.addLog(`发送命令响应失败: ${error}`);
    }
  }

  // 停止命令监听服务
  private async stopCommandListener(): Promise<void> {
    if (!this.isCommandListening || !this.commandSocket) {
      return;
    }
    
    try {
      await this.commandSocket.close();
      this.commandSocket = null;
      this.isCommandListening = false;
      this.addLog('命令监听服务已停止');
    } catch (error) {
      this.addLog(`停止命令监听服务失败: ${error}`);
    }
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