# OpenHarmony UDP 设备监控应用

## 描述

这是一个为 OpenHarmony 操作系统开发的测试应用程序。它演示了以下功能：
- 检索设备信息，例如本地 IP 地址和 CPU 温度。
- 通过 UDP 将此信息定期发送到指定的目标 IP 和端口。
- 提供一个简单的用户界面来启动和停止监控服务。
- 记录应用程序事件和 UDP 通信状态。

## 特性

- **设备信息检索:** 获取并显示设备的本地 IP 地址和 CPU 温度。
- **UDP 通信:**
    - 通过 UDP 以 JSON 有效负载形式发送设备信息（IP、CPU 温度）。
    - 可配置用于发送 UDP 数据包的目标 IP 和端口。
    - 绑定到特定的本地 UDP 端口进行发送。
- **定期更新:** 监控服务启动后，设备信息会以固定间隔（例如，每5秒）通过 UDP 发送。
- **用户界面:**
    - 显示当前服务状态（运行中/已停止）。
    - 用于启动/停止监控服务的按钮。
    - 在应用程序内显示运行时日志。
- **实时数据更新:** CPU 温度和本地 IP 在每次 UDP 传输前以及服务启动时更新。

## 安装与运行

1.  **环境设置:** 确保您已安装并配置了 OpenHarmony SDK 和 DevEco Studio IDE。
2.  **导入项目:** 在 DevEco Studio 中打开此项目。
3.  **编译项目:** 使用 DevEco Studio 编译生成 HAP 文件。
    *   通常，这包括同步项目，然后单击“Build HAP(s)”或“Run”按钮（这也会执行编译）。
4.  **在设备/模拟器上运行:**
    *   连接 OpenHarmony 设备或启动模拟器。
    *   在 DevEco Studio 中选择目标设备。
    *   单击“Run 'entry'”按钮来部署和运行应用程序。

## 使用说明

1.  在您的 OpenHarmony 设备上启动应用程序。
2.  主屏幕将显示 "OpenHarmony Heartbeat Monitor Beta"。
3.  **目标 IP/端口:** 应用程序预配置为将 UDP 数据发送到 `10.0.90.241:9990`，并将本地发送套接字绑定到端口 `9991`。这些常量定义在 `entry/src/main/ets/pages/Index.ets` 文件中。
4.  **启动监控:** 点击 "启动监控服务" 按钮。
    *   应用程序将尝试绑定 UDP 套接字。
    *   它将获取当前的 IP 地址和 CPU 温度。
    *   包含此信息的初始 UDP 数据包将被发送。
    *   一个计时器将启动，每5秒发送一次 UDP 数据包。
    *   服务状态将更改为 "监控服务已启动"。
    *   日志将显示在屏幕上的可滚动日志视图中。
5.  **停止监控:** 点击 "停止监控服务" 按钮。
    *   定期的 UDP 发送将停止。
    *   服务状态将更改为 "监控服务已停止"。
6.  **查看日志:** 运行时日志，包括 UDP 发送状态和错误，会显示在应用的 UI 中。

## 关键文件

-   `entry/src/main/ets/pages/Index.ets`: 包含 OpenHarmony 应用程序的主要 UI 逻辑、UDP 通信和设备信息检索。
-   `udp_listener.py`: (可选的配套工具) 一个 Python UDP 监听器脚本，用于在目标机器上接收此应用发送的 UDP 消息。

## 如何接收 UDP 消息

您可以在目标机器 (`10.0.90.241`) 上运行一个 UDP 监听器脚本（例如项目中的 `udp_listener.py` 或以下示例），监听端口 `9990`。

**Python UDP 监听器示例 (`udp_listener.py`):**
```python
import socket
import json

LISTEN_IP = "0.0.0.0"  # 监听所有可用的网络接口
LISTEN_PORT = 9990     # 必须与 OpenHarmony 应用中的 TARGET_UDP_PORT 匹配
BUFFER_SIZE = 1024

def start_udp_server():
    # 创建 UDP socket
    udp_server_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        # 绑定 IP 地址和端口
        udp_server_socket.bind((LISTEN_IP, LISTEN_PORT))
        print(f"UDP 服务器正在监听 {LISTEN_IP}:{LISTEN_PORT}...")
        while True:
            # 接收数据
            data, addr = udp_server_socket.recvfrom(BUFFER_SIZE)
            message = data.decode('utf-8')
            print(f"从 {addr[0]}:{addr[1]} 收到消息:")
            try:
                # 尝试解析为JSON并格式化打印
                device_info = json.loads(message)
                print(json.dumps(device_info, indent=2, ensure_ascii=False))
            except json.JSONDecodeError:
                # 如果不是JSON，则按原样打印
                print(f"  Raw: {message}")
            print("-" * 30)
    except Exception as e:
        print(f"发生错误: {e}")
    finally:
        # 关闭 socket
        udp_server_socket.close()
        print("服务器已关闭。")

if __name__ == "__main__":
    start_udp_server()
```
在 IP 地址为 `10.0.90.241` 的机器上运行此 Python 脚本。
