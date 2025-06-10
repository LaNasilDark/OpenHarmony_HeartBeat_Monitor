import socket
import threading
import time
import json
from datetime import datetime

# --- 配置 ---
TARGET_IP = "10.0.90.241"  # 目标IP地址 (OpenHarmony设备或其他服务)
TARGET_PORT = 9990         # 目标端口
LISTEN_IP = "0.0.0.0"      # 监听所有网络接口
LISTEN_PORT = 9990         # 本地监听端口 (如果此脚本运行在10.0.90.241上，它将接收发往该地址和端口的消息)
SEND_INTERVAL_SECONDS = 5  # 发送消息的间隔时间
BUFFER_SIZE = 4096         # 接收缓冲区大小

# 尝试导入 psutil 获取更详细的系统信息
try:
    import psutil
    PSUTIL_AVAILABLE = True
except ImportError:
    PSUTIL_AVAILABLE = False
    print("[注意] 未找到 'psutil' 库。发送的系统信息将受限。")
    print("     如需更详细信息，请安装: pip install psutil")

class UDPMonitor:
    def __init__(self, target_ip, target_port, listen_ip, listen_port, send_interval, buffer_size):
        self.target_ip = target_ip
        self.target_port = target_port
        self.listen_ip = listen_ip
        self.listen_port = listen_port
        self.send_interval = send_interval
        self.buffer_size = buffer_size

        self.stop_event = threading.Event()
        self.send_socket = None
        self.listen_socket = None

        self.sender_thread = threading.Thread(target=self._sender_loop, daemon=True)
        self.receiver_thread = threading.Thread(target=self._receiver_loop, daemon=True)

    def _get_local_ip_for_sending(self):
        """获取用于发送消息的本机IP（非绑定IP）"""
        try:
            # 通过连接到一个外部地址（不实际发送数据）来获取本机IP
            s_temp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s_temp.connect(("8.8.8.8", 80)) # Google DNS, or any reliable external IP
            local_ip = s_temp.getsockname()[0]
            s_temp.close()
            return local_ip
        except socket.error:
            return "127.0.0.1" # Fallback

    def _get_cpu_temperature(self):
        """尝试获取CPU温度 (高度依赖平台和权限)"""
        if PSUTIL_AVAILABLE:
            try:
                temps = psutil.sensors_temperatures()
                if temps:
                    # 尝试查找常见的CPU温度键
                    for name in ['coretemp', 'k10temp', 'cpu_thermal', 'soc_thermal']:
                        if name in temps and temps[name]:
                            return f"{temps[name][0].current:.1f}°C"
                    # 如果没有特定键，取第一个可用的
                    for key in temps:
                        if temps[key]:
                            return f"{temps[key][0].current:.1f}°C"
            except Exception:
                pass # psutil可能没有权限或不支持

        # Linux specific fallback
        try:
            with open('/sys/class/thermal/thermal_zone0/temp', 'r') as f:
                temp = int(f.read().strip()) / 1000.0
                return f"{temp:.1f}°C"
        except FileNotFoundError:
            pass # 文件不存在
        except Exception:
            pass # 其他读取错误
        return "N/A"

    def _create_message_payload(self):
        """创建要发送的消息内容"""
        payload = {
            "ipAddress": self._get_local_ip_for_sending(),
            "cpuTemperature": self._get_cpu_temperature(),
            "timestamp": datetime.now().isoformat(),
            "source": "Python UDP Monitor"
        }
        if PSUTIL_AVAILABLE:
            payload["cpuUsage"] = f"{psutil.cpu_percent(interval=None):.1f}%"
            mem = psutil.virtual_memory()
            payload["memoryUsage"] = f"{mem.percent:.1f}% (Total: {mem.total // (1024**3)}GB)"
        return payload

    def _sender_loop(self):
        print(f"[*] 发送线程已启动。将每隔 {self.send_interval} 秒向 {self.target_ip}:{self.target_port} 发送消息。")
        try:
            self.send_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            while not self.stop_event.is_set():
                try:
                    message_payload = self._create_message_payload()
                    message_bytes = json.dumps(message_payload).encode('utf-8')
                    self.send_socket.sendto(message_bytes, (self.target_ip, self.target_port))
                    print(f"[{datetime.now().strftime('%H:%M:%S')}] -> SENT to {self.target_ip}:{self.target_port}: {message_payload['ipAddress']} CPU {message_payload['cpuTemperature']}")
                except socket.gaierror:
                    print(f"[ERROR] 无法解析主机名: {self.target_ip}。请检查网络和DNS设置。")
                except Exception as e:
                    print(f"[ERROR] 发送消息时出错: {e}")
                
                # 等待或直到停止事件被设置
                self.stop_event.wait(self.send_interval)
        finally:
            if self.send_socket:
                self.send_socket.close()
            print("[-] 发送线程已停止。")

    def _receiver_loop(self):
        print(f"[*] 接收线程已启动。正在监听 {self.listen_ip}:{self.listen_port}...")
        try:
            self.listen_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            # SO_REUSEADDR 允许立即重用端口，在快速重启脚本时有用
            self.listen_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self.listen_socket.bind((self.listen_ip, self.listen_port))
            self.listen_socket.settimeout(1.0) # 设置超时以便能检查 stop_event

            while not self.stop_event.is_set():
                try:
                    data, addr = self.listen_socket.recvfrom(self.buffer_size)
                    message_str = data.decode('utf-8')
                    print(f"\n[{datetime.now().strftime('%H:%M:%S.%f')[:-3]}] <- RECV from {addr[0]}:{addr[1]}")
                    try:
                        # 尝试将消息解析为JSON并格式化打印
                        json_data = json.loads(message_str)
                        print(json.dumps(json_data, indent=2, ensure_ascii=False))
                    except json.JSONDecodeError:
                        # 如果不是JSON，直接打印原始字符串
                        print(f"  Raw: {message_str}")
                    print("-" * 40)
                except socket.timeout:
                    continue # 超时后继续循环，检查 stop_event
                except UnicodeDecodeError:
                    print(f"[WARN] 从 {addr[0]}:{addr[1]} 接收到无法解码为UTF-8的数据。")
                except Exception as e:
                    if not self.stop_event.is_set(): # 避免在关闭过程中打印错误
                        print(f"[ERROR] 接收消息时出错: {e}")
                    break # 发生其他错误时退出循环
        finally:
            if self.listen_socket:
                self.listen_socket.close()
            print("[-] 接收线程已停止。")

    def start(self):
        print("启动 UDP 监视器...")
        self.stop_event.clear()
        self.receiver_thread.start()
        self.sender_thread.start()
        print(f"UDP 监视器正在运行。按 Ctrl+C 停止。")

    def stop(self):
        if not self.stop_event.is_set():
            print("\n正在停止 UDP 监视器...")
            self.stop_event.set()

            # 等待线程结束
            if self.sender_thread.is_alive():
                self.sender_thread.join(timeout=self.send_interval + 1)
            if self.receiver_thread.is_alive():
                self.receiver_thread.join(timeout=2)
            
            print("UDP 监视器已停止。")

if __name__ == "__main__":
    monitor = UDPMonitor(
        target_ip=TARGET_IP,
        target_port=TARGET_PORT,
        listen_ip=LISTEN_IP,
        listen_port=LISTEN_PORT,
        send_interval=SEND_INTERVAL_SECONDS,
        buffer_size=BUFFER_SIZE
    )
    try:
        monitor.start()
        # 主线程保持活动状态，直到 KeyboardInterrupt
        while True:
            time.sleep(1) # 可以执行其他主线程任务或只是休眠
    except KeyboardInterrupt:
        pass
    finally:
        monitor.stop()