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
OpenHarmony_Test_APP/
├── README.md                    # 项目说明文档
├── build-profile.json5          # 构建配置
├── oh-package.json5             # 包依赖配置
├── 
├── entry/                       # 应用主模块
│   ├── src/main/ets/pages/
│   │   └── Index.ets            # 主界面和核心逻辑
│   ├── src/main/module.json5    # 模块配置
│   └── build-profile.json5     # 模块构建配置
├── 
├── monitor_run.py               # Python 监控服务器
├── udp_listener.py              # UDP 监听工具
└── AppScope/                    # 应用全局配置
    ├── app.json5
    └── resources/
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
cd OpenHarmony_Test_APP

# 2. 在 DevEco Studio 中打开项目
# 3. 配置目标 IP 地址（在 Index.ets 中）
TARGET_UDP_IP: "YOUR_SERVER_IP"
TARGET_UDP_PORT: 9990

# 4. 编译并部署到设备
```

### 2. Python 监控服务器部署

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
// OpenHarmony 应用配置 (Index.ets)
const TARGET_UDP_IP: string = "10.0.90.241";    // 服务器 IP
const TARGET_UDP_PORT: number = 9990;           // 服务器端口
const LOCAL_UDP_PORT: number = 9991;            // 本地端口
```

```python
# Python 服务器配置
LISTEN_IP = "0.0.0.0"      # 监听所有接口
LISTEN_PORT = 9990         # 监听端口
BUFFER_SIZE = 4096         # 缓冲区大小
```

### 数据格式

设备信息以 JSON 格式通过 UDP 发送。数据包的前2个字节是基于消息体的校验和（大端序，unsigned short）。

**JSON 示例:**

```json
{
  "cpuLoad": "5.7",
  "memInfo": {
    "memTotal": 8123456,
    "memLoad": 65,
    "memUsed": 5280247,
    "memAvailable": 2843209,
    "unit": "Byte"
  },
  "disk": {
    "mounted": "/data",
    "available": 5432109876,
    "total": 10987654321,
    "percent": 50,
    "used": 5555544445,
    "unit": "Byte"
  },
  "net": {
    "netInterface": "wlan0",
    "txByte": 123456,
    "txRate": 1024,
    "rxByte": 789012,
    "rxRate": 2048,
    "unit": "Bytes/s"
  },
  "mac": "00:11:22:33:44:55",
  "ipAddress": "10.0.90.100",
  "upTime": "123456.78",
  "time": "1718689815",
  "sn": "1234567890ABCDEF",
  "cpuTemperature": "45.2",
  "agentVersion": "1.14514"
}
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

#### 4. CPU 负载显示为 N/A 或获取失败

此问题通常是由于应用没有权限读取 `/proc/stat` 文件导致的。系统启动脚本可能将该文件权限设置得过于严格。

**解决方案：**

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

### 扩展功能

1. 添加新的监控指标
2. 实现数据持久化
3. 支持多种通信协议
4. 添加 Web 管理界面

## 技术支持(真的会有吗？)

- 📧 Email: [123090669@link.cuhk.edu.cn](mailto:123090669@link.cuhk.edu.cn)

## 更新日志

### v1.1.0 (2025-06-18)

- ✨ **新增**：添加了丰富的设备指标监控，包括 CPU 负载、内存、磁盘、网络流量、MAC地址、SN号、系统运行时间等。
- 📝 **更新**：更新了通信的数据结构和文档，以反映最新的功能。
- 🐛 **修复**：优化了数据采集的稳定性和准确性。

### v1.0.0 (2025-06-16)

- ✅ 初始版本发布
- ✅ 基础 UDP 通信功能
- ✅ 设备信息监控
- ✅ Python 服务器支持
