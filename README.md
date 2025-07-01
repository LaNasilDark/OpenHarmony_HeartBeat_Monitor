# OpenHarmony 设备监控系统

一个完整的 OpenHarmony 设备监控解决方案，包含设备端应用和服务器端监控工具。

## 项目概述

本项目是一个基于 UDP 通信的设备监控系统，包括：

- **OpenHarmony 应用**：运行在设备上，定期发送设备状态信息
- **Python 监控服务器**：接收设备数据，提供系统管理功能
- **UDP 通信工具**：支持广播和点对点通信

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
  - CPU 负载
  - 内存使用情况
  - 磁盘空间信息
  - 网络流量统计
  - CPU 实时温度
  - 设备序列号 (SN)
  - MAC 地址
  - 动态 IP 地址
  - 系统运行时间
  - 系统当前时间
- ✅ **UDP 通信**
  - 定期发送设备状态（每5秒）
  - 支持自定义目标服务器
  - 基于 RFC 1071 的数据完整性校验和
- ✅ **用户界面**
  - 服务启动/停止控制
  - 实时日志显示
  - 状态指示器
  - 动态设置UDP目标IP
  - Wi-Fi配置与连接

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

```
OpenHarmony_HeartBeat_Monitor/
├── README.md                    # 项目说明文档
├── hvigorfile.ts                # Hvigor 编译脚本
├── monitor_run.py               # Python 监控服务器
├── udp_listener.py              # UDP 监听工具
├── AppScope/                    # 应用级配置
│   └── app.json5
└── entry/                       # 应用主模块
    ├── hvigorfile.ts
    ├── oh-package.json5
    └── src/
        └── main/
            ├── ets/
            │   ├── common/
            │   │   └── DeviceMonitor.ets  # 设备监控核心逻辑
            │   ├── entryability/
            │   │   └── EntryAbility.ets   # 应用入口
            │   └── pages/
            │       └── Index.ets        # 主界面UI和应用逻辑
            └── module.json5
```

## 快速开始

### 1. OpenHarmony 应用部署

#### 环境要求

- OpenHarmony SDK 5.0.0.17
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

### 2.修改设备启动配置文件

你需要修改设备的启动配置文件以放宽对 `/proc/stat` 的访问限制。此操作需要 root 权限。

a. **以读写模式重新挂载 vendor 分区**

在设备的 shell 中执行以下命令：

```bash
mount -o remount,rw /vendor
```

b. 更新**配置文件**

用本仓库中的 `init.musepaper.cfg` 文件替换原本的 `init.musepaper.cfg`文件：

```bash
hdc file send ./init.musepaper.cfg /vendor/etc/init.musepaper.cfg
```

其主要区别为原文件中的：
`"chmod 0440 /proc/stat",`

被其修改为：
`"chmod 0444 /proc/stat",`

c. **恢复分区为只读模式（重要）**

为了系统安全，将分区重新挂载为只读：

```bash
mount -o remount,ro /vendor
```

d. **重启设备**

执行重启命令使更改生效：

```bash
reboot
```

重启后，应用应该能正常读取 CPU 信息。

### 3. Python 监控服务器部署

#### Python 环境要求

```bash
# Python 3.8+
pip install psutil netifaces PyYAML
```

#### 启动服务器

```bash
# 启动完整监控服务
python monitor_run.py

# 启动 UDP 监听器
python udp_listener.py
```

## 配置说明

### 网络配置

```typescript
// OpenHarmony 应用配置 (entry/src/main/ets/pages/Index.ets)
const monitorConfig: MonitorConfig = {
  targetUdpIp: "10.0.90.241", // 目标IP地址（可在应用内动态修改）
  targetUdpPort: 9990,      // 目标端口
  localUdpPort: 9991,       // 本地监听端口
  agentVersion: '1.14514',  // 代理版本号
  networkInterface: 'wlan0',// 监控的网络接口
  diskMountPath: '/data',   // 监控的磁盘挂载点
  collectInterval: 5000     // 采集间隔（毫秒）
};
```

```python
# Python 服务器配置
LISTEN_IP = "0.0.0.0"      # 监听所有接口
LISTEN_PORT = 9990         # 监听端口
BUFFER_SIZE = 4096         # 缓冲区大小
```

### 数据格式

设备信息以 string 格式通过 UDP 发送。数据包的前2个字节是基于消息体的校验和（大端序，unsigned short）。

**示例:**

```string
{'cpuLoad': '2.6', 'memInfo': {'memTotal': 8095608832, 'memLoad': 18.8, 'memUsed': 1521864704, 'memAvailable': 6573744128, 'unit': 'Byte'}, 'disk': {'mounted': 
'/data', 'available': 4047802368, 'total': 4047802368, 'percent': 0, 'used': 0, 
'unit': 'Byte'}, 'net': {'netInterface': 'wlan0', 'rxByte': 32983504, 'txByte': 
464972, 'rxRate': 7912, 'txRate': 0, 'unit': 'Bytes/s'}, 'mac': '5c:8a:ae:67:5f:ab', 'ipAddress': '10.0.91.21', 'upTime': 0.05, 'time': 1750737593.1238554, 'sn': 'TGyREaXdrx1fhBek', 'cpuTemperature': 41, 'agentVersion': '1.14514'}
```

## API 文档

### 核心函数

#### OpenHarmony API

```typescript
// 数据采集
async function fetchMemInfo(): Promise<MemObjectType>
async function getCpuPercent(interval: number): Promise<number>
async function fetchDiskInfo(mountPath: string): Promise<DiskObjectType>
async function fetchNetworkInfo(interfaceName: string): Promise<NetObjectType>
async function fetchUptimeFromProcUptime(): Promise<string | null>
async function fetchMacAddress(): Promise<string>
async function fetchSystemTime(): Promise<string>
async function fetchCpuTemperature(): Promise<string>
async function fetchSN(): Promise<string>
async function readSystemFileContent(filePath: string): Promise<string>
async function configureWifi(): Promise<void>
async function readWifiConfig(): Promise<void>

// UDP 通信
async function sendDeviceInfoViaUDP(): Promise<void>
function calculateChecksum(data: Uint8Array): number
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
```

## 使用示例

### 启动设备监控

```typescript
// OpenHarmony 应用中
await this.startMonitorService();
// 自动开始每5秒发送设备信息
```

### 服务器接收数据

```python
# Python 服务器
import asyncio
from monitor_run import monitor_device

async def main():
    await monitor_device()

asyncio.run(main())
```

### UDP 广播通信

```python
# 发送设备发现广播
device_info = {
    'type': 'device_discovery',
    'ip': '10.0.90.241',
    'hostname': 'openharmony-device'
}
response = send_udp_broadcast(device_info)

### 应用内配置IP

在应用启动后，可以直接在输入框中修改目标服务器的IP地址，并点击“设置UDP目标IP”按钮来更新配置。
```

## 故障排除

### 常见问题

#### 1. UDP 通信失败

```bash
# 检查防火墙设置
sudo ufw allow 9990/udp

# 检查网络连通性
ping 10.0.90.241

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
pip install psutil netifaces PyYAML

# 处理 netifaces 编译问题（Windows）
# 下载预编译版本或安装 Visual C++ Build Tools
```

## 性能优化

### OpenHarmony 端

- 使用定时器控制发送频率
- 实现错误重试机制
- 优化内存使用

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

1. ohos系统内的自启动功能
2. ~~修改设备静态IP以实现配网功能~~ (已通过Wi-Fi配置API实现)
3. 远程固件升级（FOTA）?
4. ~~尝试让磁盘统计可以获取整机而非沙盒内的数据~~

## 技术支持(真的会有吗？)

- 📧 Email: [123090669@link.cuhk.edu.cn](mailto:123090669@link.cuhk.edu.cn)

## 更新日志

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
