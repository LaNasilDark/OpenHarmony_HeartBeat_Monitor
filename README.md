# OpenHarmony 设备监控系统

一个完整的 OpenHarmony 设备监控解决方案，包含设备端应用和服务器端监控工具。

## 项目概述

本项目是一个基于 UDP 通信的设备监控系统，包括：

- **OpenHarmony 应用**：运行在设备上，定期发送设备状态信息
- **Python 监控服务器**：接收设备数据，提供系统管理功能
- **UDP 通信工具**：支持广播和点对点通信
- **模块化架构**：采用分层设计，便于维护和扩展

## 系统架构

```text
OpenHarmony 设备          网络          监控服务器
┌─────────────────┐      UDP       ┌─────────────────┐
│  设备监控应用    │ <-----------> │  Python 服务器   │
│  - CPU 温度      │      :9990    │  - 数据接收      │
│  - IP 地址       │               │  - 设备管理      │
│  - 状态信息      │               │  - 系统监控      │
└─────────────────┘               └─────────────────┘
```

## 主要功能

### OpenHarmony 应用端

- ✅ **设备信息采集**

  - CPU 负载和温度
  - 内存使用情况
  - 磁盘空间信息
  - 网络流量统计
  - 设备序列号 (SN)
  - MAC 地址
  - 动态 IP 地址
  - 系统运行时间
  - 系统当前时间
- ✅ **网络管理**

  - Wi-Fi 配置与连接
  - 以太网静态IP配置
  - 网络接口自动检测
  - 网络配置忘记功能
- ✅ **UDP 通信**

  - 定期发送设备状态（可配置间隔）
  - 支持自定义目标服务器
  - 基于 RFC 1071 的数据完整性校验和
  - 动态IP配置功能
- ✅ **用户界面**

  - 服务启动/停止控制
  - 实时日志显示
  - 状态指示器
  - 动态设置UDP目标IP
  - Wi-Fi和以太网配置界面

### Python 服务器端

- ✅ **网络监控**

  - UDP 数据包接收
  - 广播消息处理
  - 多设备管理
- ✅ **系统管理**

  - 远程命令执行
  - 网络配置管理
  - 服务状态监控
- ✅ **数据处理**

  - JSON 数据解析
  - 校验和验证
  - 错误处理机制

## 项目结构

```text
OpenHarmony_HeartBeat_Monitor/
├── README.md                    # 项目说明文档
├── init.musepaper.cfg           # 设备启动配置文件 (用于修改/proc/stat权限)
├── hvigorfile.ts                # Hvigor 编译脚本
├── build-profile.json5          # 构建配置文件
├── oh-package.json5             # 项目依赖配置
├── code-linter.json5            # 代码规范配置
├── AppScope/                    # 应用级配置
│   ├── app.json5               # 应用全局配置
│   └── resources/              # 应用级资源
├── entry/                       # 应用主模块
│   ├── hvigorfile.ts           # 模块构建脚本
│   ├── oh-package.json5        # 模块依赖配置
│   ├── build-profile.json5     # 模块构建配置
│   └── src/
│       └── main/
│           ├── ets/
│           │   ├── common/     # 公共模块
│           │   │   ├── DeviceMonitor.ets      # 设备监控核心逻辑
│           │   │   ├── SystemInfoCollector.ets # 系统信息采集器
│           │   │   ├── NetworkManager.ets      # 网络管理器
│           │   │   └── types.ets              # 类型定义
│           │   ├── entryability/
│           │   │   └── EntryAbility.ets       # 应用入口
│           │   ├── entrybackupability/
│           │   │   └── EntryBackupAbility.ets # 备份能力
│           │   └── pages/
│           │       └── Index.ets              # 主界面UI和应用逻辑
│           ├── module.json5                   # 模块配置
│           └── resources/                     # 资源文件
│       ├── ohosTest/                         # 单元测试
│       │   └── ets/
│       │       └── test/
│       ├── test/                             # 测试文件
│       └── mock/                             # 模拟数据
└── pytools/                     # Python 工具集
    ├── monitor_run.py          # Python 监控服务器
    ├── udp_listener.py         # UDP 监听工具
    └── ipconverter.py          # IP 转换工具
```

## 快速开始

### 1. OpenHarmony 应用部署

#### 环境要求

- [OpenHarmony FULL SDK 5.0.0.17](https://github.com/LaNasilDark/OpenHarmony-5.0.0-full-sdk/releases/tag/5.0.0.71-full-sdk)
- DevEco Studio 5.0.5
- 目标设备：OpenHarmony 系统

#### 安装步骤

```bash
# 1. 克隆项目
git clone https://github.com/LaNasilDark/OpenHarmony_HeartBeat_Monitor
cd OpenHarmony_HeartBeat_Monitor

# 2. 在 DevEco Studio 中打开项目
# 3. （可选）在 entry/src/main/ets/pages/Index.ets 中修改默认目标IP
# 4. 编译并部署到设备
# 5. （可选）在应用界面中动态设置目标服务器IP地址
```

### 2. 修改设备启动配置文件

你需要修改设备的启动配置文件以放宽对 `/proc/stat` 的访问限制。此操作需要 root 权限。

#### a. 以读写模式重新挂载 vendor 分区

在设备的 shell 中执行以下命令：

```bash
mount -o remount,rw /vendor
```

#### b. 更新配置文件

用本仓库中的 `init.musepaper.cfg` 文件替换原本的 `init.musepaper.cfg`文件：

*注意：请将文件名中的musepaper换成对应的设备名称*

```bash
hdc file send ./init.musepaper.cfg /vendor/etc/init.musepaper.cfg
```

其主要区别为原文件中的：
`"chmod 0440 /proc/stat",`

被修改为：
`"chmod 0444 /proc/stat",`

#### c. 恢复分区为只读模式

为了系统安全，将分区重新挂载为只读：

```bash
mount -o remount,ro /vendor
```

#### d. 重启设备

执行重启命令使更改生效：

```bash
reboot
```

重启后，应用应该能正常读取 CPU 信息。

### 3. Python 监控服务器部署

#### Python 环境要求

```bash
# Python 3.8+
pip install psutil netifaces PyYAML asyncio
```

#### 启动服务器

```bash
# 启动完整监控服务
python pytools/monitor_run.py

# 启动 UDP 监听器
python pytools/udp_listener.py

# 使用 IP 转换工具
python pytools/ipconverter.py
```

## 配置说明

### 网络配置

```typescript
// OpenHarmony 应用配置 (entry/src/main/ets/pages/Index.ets)
const monitorConfig: MonitorConfig = {
  targetUdpIp: "192.168.5.5",  // 目标IP地址（可在应用内动态修改）
  targetUdpPort: 9990,         // 目标端口
  localUdpPort: 9991,          // 本地监听端口
  agentVersion: '1.14514',     // 代理版本号
  networkInterface: 'wlan0',   // 监控的网络接口
  diskMountPath: '/data',      // 监控的磁盘挂载点
  collectInterval: 5000        // 采集间隔（毫秒）
};

// Wi-Fi 配置示例
const wifiConfig: WifiConfig = {
  ssid: "JDSK",
  bssid: "c4:69:f0:e7:4c:81",
  preSharedKey: "SpaceT20211102",
  isHiddenSsid: false,
  securityType: wifi.WifiSecurityType.WIFI_SEC_TYPE_WPA2_PSK,
  ipAddress: "10.0.90.200",
  gateway: "10.0.90.254",
  dns: "10.0.2.2"
};

// 以太网配置示例
const ethernetConfig: EthernetConfig = {
  ipAddress: "192.168.5.114",
  gateway: "192.168.5.1",
  netmask: "255.255.255.0",
  dns: "192.168.5.1"
};
```

```python
# Python 服务器配置
LISTEN_IP = "0.0.0.0"      # 监听所有接口
LISTEN_PORT = 9990         # 监听端口
BUFFER_SIZE = 4096         # 缓冲区大小
```

### 数据格式

设备信息以 JSON 格式通过 UDP 发送。数据包的前2个字节是基于消息体的校验和（大端序，unsigned short）。

**示例数据格式:**

```json
{
  "cpuLoad": 2.6,
  "memInfo": {
    "memTotal": 8095608832,
    "memLoad": 18.8,
    "memUsed": 1521864704,
    "memAvailable": 6573744128,
    "unit": "Byte"
  },
  "disk": {
    "mounted": "/data",
    "available": 4047802368,
    "total": 4047802368,
    "percent": 0,
    "used": 0,
    "unit": "Byte"
  },
  "net": {
    "netInterface": "wlan0",
    "rxByte": 32983504,
    "txByte": 464972,
    "rxRate": 7912,
    "txRate": 0,
    "unit": "Bytes/s"
  },
  "mac": "5c:8a:ae:67:5f:ab",
  "ipAddress": "10.0.91.21",
  "upTime": 0.05,
  "time": 1750737593.1238554,
  "sn": "TGyREaXdrx1fhBek",
  "cpuTemperature": 41,
  "agentVersion": "1.14514"
}
```

## API 文档

### 核心函数

#### OpenHarmony API

```typescript
// 核心类和接口
class DeviceMonitor {
  // 设备信息采集
  async collectDeviceInfo(): Promise<DeviceInfo>
  async sendDeviceInfoViaUDP(): Promise<void>
  
  // 网络管理
  async autoDetectNetworkInterface(): Promise<void>
  async configureNetwork(mode: number, ethConfig?: EthernetConfig, wifiConfig?: WifiConfig): Promise<void>
  async forgetAllWifiNetworks(): Promise<void>
  
  // 监控服务
  async startMonitoring(): Promise<void>
  stopMonitoring(): void
  isMonitoringRunning(): boolean
  
  // 数据管理
  getDeviceDataSnapshot(): DeviceDataCache
  updateConfig(newConfig: Partial<MonitorConfig>): void
  dispose(): void
}

class SystemInfoCollector {
  // 系统信息采集
  async fetchMemInfo(): Promise<MemObjectType>
  async getCpuPercent(): Promise<number>
  async fetchDiskInfo(mountPath: string): Promise<DiskObjectType>
  async fetchNetworkInfo(interfaceName: string): Promise<NetObjectType>
  async fetchMacAddress(interfaceName: string): Promise<string>
  async fetchLocalIp(interfaceName: string): Promise<string>
  async fetchCpuTemperature(): Promise<number | string>
  async fetchSN(): Promise<string>
  async fetchSystemTime(): Promise<number>
  async fetchUptime(): Promise<number | null>
}

class NetworkManager {
  // 网络配置
  async autoDetectNetworkInterface(): Promise<string>
  async configureNetwork(mode: number, ethConfig?: EthernetConfig, wifiConfig?: WifiConfig): Promise<void>
  async forgetAllWifiNetworks(): Promise<void>
}

// 类型定义
interface DeviceInfo {
  cpuLoad: number;
  memInfo: MemObjectType;
  disk: DiskObjectType;
  net: NetObjectType;
  mac: string;
  ipAddress: string;
  upTime: number;
  time: number;
  sn: string;
  cpuTemperature: number;
  agentVersion: string;
}

interface MonitorConfig {
  targetUdpIp: string;
  targetUdpPort: number;
  localUdpPort: number;
  agentVersion: string;
  networkInterface: string;
  diskMountPath: string;
  collectInterval: number;
  logCallback?: (message: string) => void;
}
```

#### Python API

```python
# 数据包处理
def build_udp_packet(udp_msg: str) -> bytes
def unpack_udp_packet(udp_packet: bytes) -> str

# 网络管理
async def configure_network(interface: str, ip: str, gateway: str) -> bool
def send_udp_broadcast(info_dict: dict) -> str

# 系统监控
def read_tmp() -> str
def get_uptime_days() -> int

# 异步监控
async def monitor_device() -> None
async def handle_udp_data(data: bytes, addr: tuple) -> None
```

## 使用示例

### 启动设备监控

```typescript
// OpenHarmony 应用中 - 启动设备监控
const monitor = new DeviceMonitor(monitorConfig);
await monitor.autoDetectNetworkInterface(); // 自动检测网络接口
await monitor.startMonitoring(); // 开始监控服务

// 配置网络 - Wi-Fi
const wifiConfig: WifiConfig = {
  ssid: "YourWiFiSSID",
  bssid: "xx:xx:xx:xx:xx:xx",
  preSharedKey: "YourPassword",
  // ...其他配置
};
await monitor.configureNetwork(1, undefined, wifiConfig);

// 配置网络 - 以太网
const ethConfig: EthernetConfig = {
  ipAddress: "192.168.1.100",
  gateway: "192.168.1.1",
  netmask: "255.255.255.0",
  dns: "8.8.8.8"
};
await monitor.configureNetwork(0, ethConfig);

// 获取设备信息快照
const deviceData = monitor.getDeviceDataSnapshot();
console.log('Current device data:', JSON.stringify(deviceData));
```

### 服务器接收数据

```python
# Python 服务器 - 启动监控
import asyncio
from pytools.monitor_run import monitor_device

async def main():
    await monitor_device()

# 运行服务器
asyncio.run(main())
```

### UDP 广播通信

```python
# 发送设备发现广播
device_info = {
    'type': 'device_discovery',
    'ip': '192.168.5.5',
    'hostname': 'openharmony-device'
}
response = send_udp_broadcast(device_info)
```

### 应用内动态配置

在应用启动后，可以通过界面进行以下配置：

1. **UDP 目标IP设置**：在输入框中修改目标服务器的IP地址，点击"设置UDP目标IP"按钮更新配置
2. **Wi-Fi 网络配置**：设置SSID、密码、静态IP等，点击"配置Wi-Fi"连接网络
3. **以太网配置**：设置静态IP、网关、DNS等，点击"配置以太网"应用设置

## 故障排除

### 常见问题

#### 1. UDP 通信失败

```bash
# 检查防火墙设置
sudo ufw allow 9990/udp

# 检查网络连通性
ping 192.168.5.5

# 验证端口监听
netstat -ulnp | grep 9990
```

#### 2. 设备信息获取失败

```typescript
// 检查文件权限
// /sys/class/thermal/thermal_zone0/temp
// 确保应用有读取权限
```

#### 3. Python 依赖问题

```bash
# 安装缺失的包
pip install psutil netifaces PyYAML asyncio

# 处理 netifaces 编译问题（Windows）
# 下载预编译版本或安装 Visual C++ Build Tools
```

## 性能优化

### OpenHarmony 端

- 使用定时器控制发送频率
- 实现错误重试机制
- 优化内存使用
- 模块化架构提高可维护性

### Python 端

- 异步处理多设备连接
- 数据缓存机制
- 连接池管理

## 安全注意事项

1. **网络安全**

   - 使用 HTTPS 进行敏感配置
   - 验证数据包来源
   - 限制广播频率
2. **权限控制**

   - 最小权限原则
   - 文件访问控制
   - 网络访问限制

## 开发指南

### 扩展功能开发计划

1. **OpenHarmony系统内的自启动功能**: 研究并实现应用开机自启动，确保设备重启后监控服务能自动运行
2. ~~**有线网络配置**: 增加对有线网络（Ethernet）的IP地址等配置功能，扩展设备适用性~~(已完成，但存在一台设备占用两个ip的bug，推测为鸿蒙系统问题)
3. **清除DHCP缓存**: 为确保Wi-Fi或有线网络配置能立即生效，研究在应用内通过程序化方式清除系统DHCP缓存（例如 `/data/service/el1/public/dhcp/dhcp_cache.conf`），避免因缓存导致IP不更新
4. ~~**修改设备静态IP以实现配网功能**~~ (已通过Wi-Fi配置API实现)
5. ~~**尝试让磁盘统计可以获取整机而非沙盒内的数据**~~ (已通过@ohos.file.storageStatistics实现)
6. ~~**远程固件升级（FOTA）**~~ (功能过于复杂且超出项目范围，已移除)
7. **添加接受配网指令功能**

## 技术支持(真的会有吗?)

- 📧 Email: [123090669@link.cuhk.edu.cn](mailto:123090669@link.cuhk.edu.cn)

## 更新日志

### v1.5.0 (2025-07-16)

- 🏗️ **架构重构**: 实现模块化架构，将功能拆分为 `DeviceMonitor`、`SystemInfoCollector` 和 `NetworkManager` 三个核心类
- ✨ **新增**: 完善的TypeScript类型定义系统，提供强类型支持
- ✨ **新增**: 增加 `pytools` 目录，重新组织Python工具集
- 📝 **文档**: 大幅更新 `README.md`，完善项目结构说明和API文档
- 🐛 **修复**: 解决类型导入问题，提高代码质量和可维护性
- ⚡ **优化**: 改进错误处理机制和日志系统

### v1.4.0 (2025-07-02)

- 📝 **文档**: 更新 `README.md`，添加 `init.musepaper.cfg` 到项目结构中。
- 📝 **文档**: 澄清了开发指南中的功能规划，移除了已完成或超出范围的条目。
- ✨ **新增**:支持以太网与wifi的一键配网与更改ip功能，但是鸿蒙系统api目前存在bug，会导致一台设备占据两个ip。

### v1.3.0 (2025-07-01)

- ✨ **新增**: 在应用UI中增加了动态配置目标服务器IP的功能。
- ✨ **新增**: 增加了读取设备Wi-Fi配置和通过API进行Wi-Fi配网的功能。
- ✨ **新增**: 增加了获取应用沙盒路径的功能，方便调试。
- 📝 **更新**: 更新了 `README.md` 以反映最新的UI功能和API变化。

### v1.2.0 (2025-06-24)

- ✨ **新增**: 将应用采集与发送的逻辑剥离 实现可复用与模块化
- 🐛 **修复**: 优化了设备信息采集逻辑，提高了数据准确性和稳定性。
- 📝 **更新**: 完善了 `README.md` 文档，包括更新项目结构、配置说明和功能列表。

### v1.1.0 (2025-06-18)

- ✨ **新增**：添加了丰富的设备指标监控，包括 CPU 负载、内存、磁盘、网络流量、MAC地址、SN号、系统运行时间等。
- 📝 **更新**：更新了通信的数据结构和文档，以反映最新的功能。
- 🐛 **修复**：优化了数据采集的稳定性和准确性。

### v1.0.0 (2025-06-16)

- ✅ 初始版本发布
- ✅ 基础 UDP 通信功能
- ✅ 设备信息监控
- ✅ Python 服务器支持
