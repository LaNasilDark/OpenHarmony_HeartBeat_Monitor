import socket

# --- 配置 ---
LISTEN_IP = "0.0.0.0"  # 监听所有网络接口。对于广播，通常绑定到 "0.0.0.0" 或具体网卡的广播地址
LISTEN_PORT = 9990     # 监听的端口号，应与广播发送方使用的端口一致
BUFFER_SIZE = 4096     # 接收缓冲区大小

def start_udp_broadcast_listener():
    """
    启动一个UDP广播监听器。
    """
    # 1. 创建UDP套接字
    # AF_INET 表示使用 IPv4 地址族
    # SOCK_DGRAM 表示使用 UDP 协议
    listen_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

    # 2. 设置套接字选项
    # SO_REUSEADDR 允许立即重用端口，在快速重启脚本时有用
    listen_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    # SO_BROADCAST 允许套接字发送和接收广播消息 (对于接收端，主要是确保可以绑定到广播地址或接收广播)
    # 虽然对于纯接收端，SO_BROADCAST 可能不是严格必需的（取决于操作系统），但加上无害。
    listen_socket.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)


    try:
        # 3. 绑定IP地址和端口
        # 对于接收广播，通常绑定到 "0.0.0.0" (所有接口) 或特定接口的IP地址。
        # 如果发送方发送到特定子网的广播地址 (如 192.168.1.255)，
        # 绑定到 "0.0.0.0" 或该子网内的接口IP (如 192.168.1.100) 应该都能接收到。
        listen_socket.bind((LISTEN_IP, LISTEN_PORT))
        print(f"UDP广播监听器正在监听 {LISTEN_IP}:{LISTEN_PORT}...")

        # 4. 循环接收消息
        while True:
            print(f"\n等待接收广播消息 (端口: {LISTEN_PORT})...")
            try:
                # 接收数据，data 是接收到的字节数据，addr 是发送方的地址 (ip, port)
                data, addr = listen_socket.recvfrom(BUFFER_SIZE)
                message = data.decode('utf-8', errors='replace') # 将字节解码为字符串,替换无法解码的字符

                print(f"从 {addr[0]}:{addr[1]} 收到广播消息:")
                print(f"  内容: {message}")
                print("-" * 40)

            except UnicodeDecodeError:
                print(f"从 {addr[0]}:{addr[1]} 接收到无法解码为UTF-8的数据。")
            except socket.error as e:
                print(f"Socket 错误: {e}")
                break # 发生socket错误时退出循环

    except socket.error as e:
        print(f"启动监听器时发生 Socket 错误: {e}")
        print("请检查端口是否被占用或网络配置。")
    except KeyboardInterrupt:
        print("\n监听器正在关闭...")
    finally:
        # 关闭套接字
        if 'listen_socket' in locals() and listen_socket:
            listen_socket.close()
            print("监听器已关闭。")

if __name__ == "__main__":
    print("=== UDP 广播接收程序 ===")
    # 提示：确保您的防火墙允许在指定端口上接收UDP流量。
    # 广播发送方需要将消息发送到网络中的广播地址（例如，192.168.1.255）
    # 或特定多播地址（如果配置为多播监听器）。
    # 此脚本是为接收传统的子网广播而设计的。
    start_udp_broadcast_listener()