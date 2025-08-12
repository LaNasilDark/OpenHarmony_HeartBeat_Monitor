import asyncio
import struct
import json


def calculate_checksum(data):
    s = 0
    n = len(data) % 2
    for i in range(0, len(data)-n, 2):
        s += (data[i]) + ((data[i+1]) << 8)
    if n:
        s += data[-1]
    while (s >> 16):
        s = (s & 0xFFFF) + (s >> 16)
    s = ~s & 0xFFFF
    return s

async def handle_discovery_requests():
    # 创建 UDP 套接字传输协议工厂
    transport, protocol = await loop.create_datagram_endpoint(
        lambda: DeviceDiscoveryProtocol(),
        local_addr=('0.0.0.0', 18887)
    )

    print('Waiting for device discovery requests...')
    try:
        # 保持事件循环运行
        await asyncio.sleep(3600)  # 可以根据需要调整等待时间
    except asyncio.CancelledError:
        pass
    finally:
        # 关闭传输
        transport.close()


def build_udp_packet(udp_msg):
    udp_msg =  bytes(udp_msg, encoding='utf-8')
    checksum = calculate_checksum(udp_msg)
    packet = struct.pack('!H', checksum) + udp_msg
    return packet

def unpack_udp_packet(udp_packet):
    received_checksum = struct.unpack('!H', udp_packet[:2])[0]
    data = udp_packet[2:]
    calculated_checksum = calculate_checksum(data)
    if received_checksum == calculated_checksum:
        return data.decode()
    print('接收到的udp数据包不完整!')
    return None


class DeviceDiscoveryProtocol(asyncio.DatagramProtocol):

    def connection_made(self, transport):
        # 初始化 transport 属性
        self.transport = transport

    def datagram_received(self, data, addr):
        msg = unpack_udp_packet(data)
        if msg:
            print(msg)
        #response =  json.dumps({'server_ping': "10.255.128.91"})
        response =  json.dumps({'set_ip': "10.255.128.90", 'gw': "10.255.255.254", 'netmask': "10.255.255.4", 'dns': ['8.8.8.8']})
        self.transport.sendto(build_udp_packet(response), addr)

if __name__ == "__main__":
    # 获取事件循环
    loop = asyncio.get_event_loop()
    try:
        # 运行事件循环
        loop.run_until_complete(handle_discovery_requests())
    except KeyboardInterrupt:
        pass
    finally:
        # 关闭事件循环
        loop.close()
