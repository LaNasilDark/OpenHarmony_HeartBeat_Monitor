import wifi from '@ohos.wifi';
import ethernet from '@ohos.net.ethernet';
import connection from '@ohos.net.connection';
import { fileIo as fs } from '@kit.CoreFileKit';
import { WifiConfig, EthernetConfig, LogFunction } from './types';

export class NetworkManager {
  private static readonly FILE_PATH_DHCP_CACHE = "/data/service/el1/public/dhcp/dhcp_cache.conf";

  private log: LogFunction;
  private formatError: (error: Object) => string;

  constructor(log: LogFunction, formatError: (error: Object) => string) {
    this.log = log;
    this.formatError = formatError;
  }

  // 手动实现 IP 字符串到整数的转换 (大端序)
  private manualIpToInt(ip: string): number {
    const parts = ip.split('.').map(part => parseInt(part, 10));
    if (parts.length !== 4 || parts.some(isNaN)) {
      return 0; // Invalid format
    }
    return ((parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]) >>> 0;
  }

  // 自动检测网络接口
  public async autoDetectNetworkInterface(): Promise<string> {
    this.log('Auto-detecting network interface...');
    try {
      const defaultNet = await connection.getDefaultNet();
      if (defaultNet) {
        const netCaps = await connection.getNetCapabilities(defaultNet);
        if (netCaps.bearerTypes.includes(connection.NetBearType.BEARER_WIFI)) {
          this.log('Default network is Wi-Fi, using interface wlan0');
          return 'wlan0';
        } else if (netCaps.bearerTypes.includes(connection.NetBearType.BEARER_ETHERNET)) {
          this.log('Default network is Ethernet, using interface eth0');
          return 'eth0';
        }
      }
    } catch (e) {
      this.log(`Failed to detect network interface: ${this.formatError(e)}`, 'error');
    }
    this.log('No default network connection detected. Using default wlan0.', 'warn');
    return 'wlan0'; // 返回一个默认值
  }

  // 配置以太网
  public async configureEthernet(iface: string, config: EthernetConfig): Promise<void> {
    this.log(`Configuring Ethernet interface ${iface}...`);
    try {
      const ethConfig: ethernet.InterfaceConfiguration = {
        mode: ethernet.IPSetMode.STATIC,
        ipAddr: config.ipAddress,
        route: "0.0.0.0", // 通常设为0.0.0.0，由网关决定
        gateway: config.gateway,
        netMask: config.netmask,
        dnsServers: config.dns // dnsServers 需要一个字符串
      };
      await ethernet.setIfaceConfig(iface, ethConfig);
      this.log(`Successfully set Ethernet configuration for ${iface}.`);
    } catch (error) {
      const errMsg = `Failed to configure Ethernet: ${this.formatError(error)}`;
      this.log(errMsg, 'error');
      throw new Error(errMsg);
    }
  }

  // 配置Wi-Fi
  public async configureWifi(config: WifiConfig): Promise<void> {
    this.log('Starting Wi-Fi configuration...');
    try {
      // 1. 确保Wi-Fi已激活
      if (!wifi.isWifiActive()) {
        this.log('Wi-Fi is not active, enabling...');
        wifi.enableWifi();
        await new Promise<void>(resolve => setTimeout(resolve, 2000)); // 等待启动
        this.log('Wi-Fi enabled.');
      } else {
        this.log('Wi-Fi is already active.');
      }

      // 2. IP地址转换
      const ipAddressInt = this.manualIpToInt(config.ipAddress);
      const gatewayInt = this.manualIpToInt(config.gateway);
      const dnsInt = this.manualIpToInt(config.dns);
      if (ipAddressInt === 0 || gatewayInt === 0 || dnsInt === 0) {
        throw new Error('Invalid IP, gateway, or DNS address format.');
      }

      // 3. 断开当前连接并移除旧配置
      this.log('Disconnecting current Wi-Fi...');
      wifi.disconnect();
      await new Promise<void>(resolve => setTimeout(resolve, 2000));

      const existingConfigs = wifi.getDeviceConfigs();
      const oldConfig = existingConfigs.find(c => c.ssid === config.ssid);
      if (oldConfig) {
        this.log(`Found and removing old config for ${config.ssid} (NetId: ${oldConfig.netId})`);
        wifi.disableNetwork(oldConfig.netId);
        wifi.removeDevice(oldConfig.netId);
        this.log('Old config removed.');
      }

      // 4. 清除DHCP缓存
      try {
        await fs.unlink(NetworkManager.FILE_PATH_DHCP_CACHE);
        this.log('DHCP cache cleared.');
      } catch (unlinkError) {
        this.log(`Could not clear DHCP cache (this may be expected): ${this.formatError(unlinkError)}`, 'warn');
      }

      // 5. 创建并添加新配置
      const deviceConfig: wifi.WifiDeviceConfig = {
        ssid: config.ssid,
        bssid: config.bssid,
        preSharedKey: config.preSharedKey,
        isHiddenSsid: config.isHiddenSsid,
        securityType: config.securityType,
        creatorUid: 0,
        disableReason: 0,
        netId: 0,
        randomMacType: 0,
        randomMacAddr: "00:00:00:00:00:00",
        ipType: wifi.IpType.STATIC,
        staticIp: {
          ipAddress: ipAddressInt,
          gateway: gatewayInt,
          dnsServers: [dnsInt],
          domains: ["dc.com"]
        }
      };

      this.log('Adding new Wi-Fi configuration...');
      const newNetId = await wifi.addDeviceConfig(deviceConfig);
      this.log(`New config added with NetId: ${newNetId}`);

      // 6. 连接到新网络
      this.log(`Connecting to ${config.ssid}...`);
      await new Promise<void>(resolve => setTimeout(resolve, 1000));
      const connectResult = wifi.connectToNetwork(newNetId);
      if (connectResult) {
        this.log(`Successfully sent connection command for ${config.ssid}.`);
      } else {
        throw new Error('Failed to send connection command.');
      }
    } catch (error) {
      const errMsg = `Wi-Fi configuration failed: ${this.formatError(error)}`;
      this.log(errMsg, 'error');
      throw new Error(errMsg);
    }
  }

  // 忘记所有Wi-Fi网络
  public async forgetAllWifiNetworks(): Promise<void> {
    this.log('Clearing all saved Wi-Fi networks...');
    try {
      if (!wifi.isWifiActive()) {
        this.log('Wi-Fi is not active. Please enable Wi-Fi first.', 'warn');
        return;
      }

      const savedNetworks = wifi.getDeviceConfigs();
      if (savedNetworks.length === 0) {
        this.log('No saved Wi-Fi networks found.');
        return;
      }

      this.log(`Found ${savedNetworks.length} networks. Removing them...`);
      let successCount = 0;
      let failCount = 0;

      for (const network of savedNetworks) {
        try {
          this.log(`Removing: ${network.ssid} (NetId: ${network.netId})`);
          wifi.disableNetwork(network.netId);
          wifi.removeDevice(network.netId);
          successCount++;
        } catch (innerError) {
          this.log(`Failed to remove ${network.ssid}: ${this.formatError(innerError)}`, 'error');
          failCount++;
        }
      }
      this.log(`Operation complete. Succeeded: ${successCount}, Failed: ${failCount}.`);
      wifi.disconnect();
    } catch (error) {
      const errMsg = `Failed to clear all Wi-Fi networks: ${this.formatError(error)}`;
      this.log(errMsg, 'error');
      throw new Error(errMsg);
    }
  }

  /**
   * 网络配置统一入口
   * @param mode 0: Ethernet, 1: Wi-Fi
   * @param ethConfig EthernetConfig
   * @param wifiConfig WifiConfig
   */
  public async configureNetwork(mode: number, ethConfig?: EthernetConfig, wifiConfig?: WifiConfig): Promise<void> {
    switch (mode) {
      case 0: // 以太网
        if (!ethConfig) throw new Error('EthernetConfig 参数缺失');
        await this.configureEthernet('eth0', ethConfig);
        break;
      case 1: // Wi-Fi
        if (!wifiConfig) throw new Error('WifiConfig 参数缺失');
        await this.configureWifi(wifiConfig);
        break;
      default:
        throw new Error(`未知的配置模式: ${mode}`);
    }
  }
}
