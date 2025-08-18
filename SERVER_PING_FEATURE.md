# 动态服务器发现和切换功能

## 功能概述

本功能实现了类似于Python代码中的动态服务器发现和切换逻辑：

```python
if 'server_ping' in cmd:
    remote_server_ip = cmd['server_ping']
    if server_ip != remote_server_ip:
        server_ip = remote_server_ip
        save_ip_to_file(remote_server_ip)
```

## 实现原理

### 1. 命令处理流程

当应用接收到包含 `server_ping` 字段的UDP命令时：

1. **命令解析**：在 `handleCommandMessage` 方法中解析JSON命令
2. **命令识别**：通过 `isServerPingCommand` 方法识别服务器ping命令
3. **服务器切换**：调用 `handleServerPingCommand` 处理服务器切换逻辑
4. **持久化保存**：将新的服务器IP保存到本地文件

### 2. 核心组件

#### CommandTypes.ets
- 新增 `ServerPingCommand` 接口，定义服务器ping命令格式

#### DeviceMonitor.ets
- `saveServerIpToFile()`: 保存服务器IP到文件
- `loadServerIpFromFile()`: 从文件加载服务器IP  
- `handleServerPingCommand()`: 处理服务器ping命令
- `initializeServerIpFromFile()`: 应用启动时加载保存的服务器IP

#### Index.ets
- `isServerPingCommand()`: 检查是否为服务器ping命令
- `handleServerPingCommand()`: UI层的服务器ping命令处理

### 3. 文件存储

服务器IP保存在：`/data/storage/el2/base/haps/entry/files/.server`

## 使用方法

### 命令格式

发送UDP命令到设备的9992端口：

```json
{
  "server_ping": "192.168.1.100"
}
```

### 工作流程

1. **设备启动**：从文件中加载上次保存的服务器IP
2. **接收命令**：监听9992端口的UDP命令
3. **服务器发现**：接收到server_ping命令时提取服务器IP
4. **IP比较**：比较当前目标IP与新服务器IP
5. **切换服务器**：如果IP不同则更新配置并保存到文件
6. **响应确认**：向发送方返回切换结果

### 应用场景

- **服务器故障转移**：主服务器故障时自动切换到备用服务器
- **负载均衡**：根据网络条件动态切换监控服务器
- **多环境部署**：在不同网络环境间灵活切换服务器
- **远程配置**：通过UDP命令远程更改设备的目标服务器

## 测试方法

### 1. 使用Python测试脚本

```python
import socket
import json

def send_server_ping(device_ip, new_server_ip):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    command = {"server_ping": new_server_ip}
    message = json.dumps(command).encode('utf-8')
    sock.sendto(message, (device_ip, 9992))
    sock.close()

# 测试切换到新服务器
send_server_ping("192.168.5.114", "192.168.1.200")
```

### 2. 使用UDP测试工具

向设备IP的9992端口发送JSON格式的UDP包：
```json
{"server_ping": "192.168.1.200"}
```

## 日志输出

成功切换时的日志示例：
```
[14:30:25.123] 收到命令: {"server_ping":"192.168.1.200"} 来自: 192.168.1.100:12345
[14:30:25.124] 收到服务器Ping命令，远程服务器IP: 192.168.1.200
[14:30:25.125] Received server ping from: 192.168.1.200
[14:30:25.126] Switching server from 192.168.5.5 to 192.168.1.200
[14:30:25.127] Server IP saved to file: 192.168.1.200
[14:30:25.128] Server switched successfully to: 192.168.1.200
[14:30:25.129] 命令响应已发送到 192.168.1.100:12345
```

## 注意事项

1. **文件权限**：确保应用有权限读写文件目录
2. **网络连通性**：新服务器IP必须网络可达
3. **格式验证**：服务器IP应符合IPv4格式
4. **错误处理**：切换失败时会记录错误日志并返回失败响应
