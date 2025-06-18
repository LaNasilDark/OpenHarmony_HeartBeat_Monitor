# udp_listener.py
import socket
import json
import struct
import datetime

# --- 与 OpenHarmony 端完全相同的校验和计算函数 ---
def calculate_checksum(data: bytes) -> int:
    """
    计算给定字节数据的互联网校验和 (RFC 1071)。
    """
    s = 0
    # 处理偶数长度部分
    n = len(data) % 2
    for i in range(0, len(data) - n, 2):
        # 将两个8位字节组合成一个16位字
        s += data[i] + (data[i+1] << 8)
    
    # 如果长度是奇数，处理最后一个字节
    if n:
        s += data[-1]
    
    # 将32位的和折叠成16位
    while (s >> 16):
        s = (s & 0xFFFF) + (s >> 16)
    
    # 取反码
    s = ~s & 0xFFFF
    return s

def main():
    """
    主函数，用于监听和处理带有CRC校验的UDP数据包。
    """
    # 监听所有可用的网络接口
    listen_ip = "0.0.0.0" 
    # 必须与 OpenHarmony 应用中 TARGET_UDP_PORT 匹配
    listen_port = 9990 

    # 创建 UDP socket
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    
    # 绑定到指定的 IP 和端口
    try:
        sock.bind((listen_ip, listen_port))
        print(f"UDP listener started on {listen_ip}:{listen_port}...")
    except OSError as e:
        print(f"Error binding to port {listen_port}: {e}")
        print("Please make sure the port is not in use by another application.")
        return

    while True:
        try:
            # 接收数据，缓冲区大小设为4096字节，对于JSON数据足够了
            packet, addr = sock.recvfrom(4096)
            
            # 1. 检查数据包长度
            if len(packet) < 2:
                print(f"[{datetime.datetime.now()}] Received a malformed packet (too short) from {addr}")
                continue

            # 2. 解包并分离校验和与消息
            # '!H' 表示网络字节序（大端）的无符号短整型（2字节）
            received_checksum = struct.unpack('!H', packet[:2])[0]
            message_bytes = packet[2:]

            # 3. 重新计算校验和
            calculated_checksum = calculate_checksum(message_bytes)

            # 4. 验证校验和
            if received_checksum == calculated_checksum:
                # 校验成功，处理数据
                try:
                    message_str = message_bytes.decode('utf-8')
                    device_info = json.loads(message_str)
                    
                    print("-" * 40)
                    print(f"[{datetime.datetime.now()}] Packet received from {addr} (Checksum OK: {received_checksum})")
                    # 使用 json.dumps 美化输出
                    print(json.dumps(device_info, indent=2, ensure_ascii=False))
                    
                except (UnicodeDecodeError, json.JSONDecodeError) as e:
                    print(f"[{datetime.datetime.now()}] Checksum OK, but failed to decode/parse JSON from {addr}: {e}")
            else:
                # 校验失败
                print(f"[{datetime.datetime.now()}] !!! CHECKSUM ERROR from {addr} !!!")
                print(f"  -> Received: {received_checksum}, Calculated: {calculated_checksum}")

        except Exception as e:
            print(f"An unexpected error occurred: {e}")

if __name__ == "__main__":
    main()