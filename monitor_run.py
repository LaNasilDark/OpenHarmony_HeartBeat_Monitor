#!/usr/bin/env python
# encoding: utf-8
"""
@author: simin. Gong
@license: (C) Copyright 2013-2023 Spacemit Corporation Limited.
@contact: simin.gong@spacemit.com
@file: udpclient.py
@date: 2025/2/7 09:39 
@desc:
"""
import asyncio
import json
import socket
import netifaces
import psutil
import time
import struct
import os
import yaml
import ipaddress
from urllib.request import urlopen
from urllib.error import URLError, HTTPError
from asyncio import subprocess

monitor_cmd = 'bash -c export LANG="en_US";export LANGUAGE="en_US";export LC_ALL="en_US";echo spacemit_separator;free;echo ' \
                'spacemit_separator;uptime;echo spacemit_separator;cat /proc/net/dev;echo ' \
                'spacemit_separator;df -h;echo spacemit_separator;sleep 1;free;echo spacemit_separator;uptime;echo ' \
                'spacemit_separator;cat /proc/net/dev;echo spacemit_separator;df -h;echo spacemit_separator;top -b -n ' \
                '1 | head -n 30 ;echo spacemit_separator; '
#无任何其他地方调用

update_url = None
can_use_urls = ['http://10.0.56.20:8081/repository/images/bianbucloud/install_update.sh', 'https://cloudfile.bianbu.xyz/repository/images/bianbucloud/install_update.sh', 'https://cloudfile.spacemit.com/resource/install_update.sh']

VERSION = '0.0.3'
TIMEOUE = None
node_ip = None
will_ip = None
will_interface = 'end0'
home_path = os.path.expanduser("~")
record_cloud_file = os.path.join(home_path, '.cloud')

"""
network:
    version: 2
    renderer: networkd
    ethernets:
        end0:
            dhcp4: no
            dhcp6: no
            addresses:
              - 10.65.21.91/23
            gateway4: 10.65.20.1
            nameservers:
              addresses: [ 8.8.8.8 ]
"""

cat_interface_cmd = "ip addr | grep -E '^[0-9]+:' | awk '{print $2}' | sed 's/://g' | grep -E '^en|^eth' | grep -v '^lo$'"

def is_webpage_accessible_urllib(url, timeout=2):
    try:
        with urlopen(url, timeout=timeout) as response:
            if response.getcode() == 200:
                return True
            else:
                return False
    except HTTPError as e:
        return False
    except URLError as e:
        return False
    except Exception as e:
        return False

def save_dict_to_json(dictionary):
    try:
        with open(record_cloud_file, 'w') as file:
            json.dump(dictionary, file)
    except Exception as e:
        pass

def load_dict_from_json():
    try:
        with open(record_cloud_file, 'r') as file:
            dictionary = json.load(file)
        return dictionary
    except Exception :
        pass
    return {}

def change_code_server_password(new_password):      #无任何地方调用
    config_file = os.path.expanduser('~/.config/code-server/config.yaml')
    try:
        with open(config_file, 'r') as file:
            config = yaml.safe_load(file)
        if 'password' in config:
            config['password'] = new_password
        else:
            config.update({'password': new_password})
        with open(config_file, 'w') as file:
            yaml.dump(config, file, default_flow_style=False)
        print("密码修改成功！")
    except FileNotFoundError:
        print("配置文件未找到，请检查路径。")
    except Exception as e:
        print(f"发生错误: {e}")


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


def build_udp_packet(udp_msg): #json.dumps
    udp_msg = bytes(udp_msg, encoding='utf-8')
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

async def run_command(command, callback=None):
    process = await asyncio.create_subprocess_shell(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )
    stdout = ''
    while True:
        output = await process.stdout.readline()
        if not output:
            break
        if callback is not None:
            await callback(output)
        stdout += output.decode('utf-8', 'ignore')
    await process.wait()
    return stdout


async def run_command_with_timeout(command, timeout=2, callback=None, ex_callback=None):
    try:
        return await asyncio.wait_for(run_command(command, callback), timeout)
    except asyncio.TimeoutError:
        if ex_callback is not None:
            ex_callback(TIMEOUE)
        print(f'time out error: {command} {timeout}')
        return TIMEOUE

def search_node(): #无任何调用
    mac, _ = get_interface_mac_ip()
    global node_ip
    node_flag = 'node:'
    while True:
        msg = send_udp_broadcast(mac)
        if node_flag in msg:
            node_ip = msg.replace(node_flag, '')
            break

def send_udp_broadcast(info_dict):
    client_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    client_socket.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    broadcast_address = ('255.255.255.255', 18887)

    message =  build_udp_packet(json.dumps(info_dict))
    client_socket.sendto(message, broadcast_address) #发送二进制msg到addr
    
    try: #返回接受到的第一个响应
        client_socket.settimeout(5)
        while True:
            packet, addr = client_socket.recvfrom(1024)
            msg = unpack_udp_packet(packet)
            return msg
    except socket.timeout:
        print('No more responses received.')
        return None
    except Exception:
        print('No more responses received.')
        return None
    finally:
        client_socket.close()

def get_interface_mac_ip(intf = 'end0'): #本机IP?
    interfaces = netifaces.interfaces()
    for interface in interfaces:
        addrs = netifaces.ifaddresses(interface)
        if netifaces.AF_INET in addrs and netifaces.AF_LINK in addrs:
            if interface == intf:
                return addrs[netifaces.AF_LINK][0].get('addr'), addrs[netifaces.AF_INET][0]['addr']
    return None, None

def check_updater_url():
    """
    can_use_urls = ['http://10.0.56.20:8081/repository/images/bianbucloud/install_update.sh', 'https://cloudfile.bianbu.xyz/repository/images/bianbucloud/install_update.sh', 'https://cloudfile.spacemit.com/resource/install_update.sh']
    """
    global update_url
    for url in can_use_urls:
        if is_webpage_accessible_urllib(url):
            update_url = url
            print(f'使用的更新服务地址为: {update_url}')
            return

async def check_updater_service():
    if update_url is None:
        return
    status = await run_command_with_timeout('systemctl is-active cloud_update.service', timeout=10)
    if 'active'!= status.strip():
        print('重启update服务')
        if is_webpage_accessible_urllib(update_url):
            await run_command_with_timeout(f'wget --no-check-certificate -O install_update.sh {update_url} && bash install_update.sh && rm install_update.sh', timeout=60)
        else:
            print('更新服务无法访问!')

async def set_ip(ip, netmask='255.255.254.0', gw='10.0.71.254', dns=None):
    if dns is None:
        dns = ['8.8.8.8']
    if not await configure_network(will_interface, ip, gw, netmask, dns): 
        await run_command_with_timeout(f'ifconfig {will_interface} down')
        await asyncio.sleep(10)
        await run_command_with_timeout(f'ifconfig {will_interface} {ip} netmask {netmask} up')
        await asyncio.sleep(8)
        await run_command_with_timeout(f'route add default gw {gw}')
        await asyncio.sleep(5)


def netmask_to_prefix(netmask: str) -> int:

    """将点分十进制子网掩码转换为前缀长度"""
    return ipaddress.IPv4Network(f'0.0.0.0/{netmask}').prefixlen

async def configure_network(interface: str, ip_address: str, gateway: str, netmask: str, dns_servers: list):
    if not os.path.exists('/etc/netplan'):
        return False
    config_file = os.path.join('/etc/netplan', '50-cloud-init.yaml')
    if os.path.exists(config_file):
        os.remove(config_file)

    if not os.path.exists(config_file):
        print(f"配置文件 {config_file} 不存在，将创建新文件")
        config_data = {
            "network": {
                "version": 2,
                "renderer": "networkd",
                "ethernets": {}
            }
        }
    else:
        with open(config_file, "r") as f:
            config_data = yaml.safe_load(f)

    if "network" not in config_data or "ethernets" not in config_data["network"]:
        config_data["network"] = {
            "version": 2,
            "renderer": "networkd",
            "ethernets": {}
        }

    config_data["network"]["ethernets"][interface] = {
        "dhcp4": False,
        "addresses": [f'{ip_address}/{netmask_to_prefix(netmask)}'],
        "gateway4": gateway,
        "nameservers": {
            "addresses": dns_servers
        }
    }
    with open(config_file, "w") as f:
        yaml.dump(config_data, f, default_flow_style=False)
    await run_command_with_timeout('chmod 600 /etc/netplan/50-cloud-init.yaml')
    await run_command_with_timeout('netplan apply', timeout=20)
    print(f"已更新网络配置: {interface} → {ip_address}")
    return True


def cat_file(file_path):
    try:
        with open(file_path, 'r') as file:
            return file.read().strip()
    except FileNotFoundError:
        print(f"未找到名为 {file_path} 文件。")
        return None
    except Exception as e:
        print(f"读取{file_path}文件时出现错误: {e}")
        return None

def is_network_interface_down(interface_name):
    file_path = f'/sys/class/net/{interface_name}/operstate'
    try:
        with open(file_path, 'r') as file:
            state = file.read().strip()
            return state == 'down'
    except FileNotFoundError:
        print(f"未找到名为 {interface_name} 的网卡对应的状态文件。")
        return True
    except Exception as e:
        print(f"读取网卡状态文件时出现错误: {e}")
        return True

# 读取一系列设备数据
def read_sn():
    file_path = '/proc/device-tree/serial-number'
    sn_str = cat_file(file_path)
    if sn_str is None:
        return None
    return sn_str.rstrip('\x00')

def read_tmp():
    file_path = '/sys/class/thermal/thermal_zone0/temp'
    return cat_file(file_path)

def get_uptime_days(): #/proc/uptime读取
    boot_time = psutil.boot_time()
    current_time = time.time()
    uptime_seconds = current_time - boot_time
    uptime_days = uptime_seconds // (24 * 3600)
    return uptime_days

sn = read_sn()

async def monitor_device():
    monitor_info = {}
    # 获取 CPU 占用率
    cpu_percent = psutil.cpu_percent(interval=1) #proc/stat 
    monitor_info['cpuLoad'] = cpu_percent

    # 获取内存信息
    memory = psutil.virtual_memory() #proc/meminfo
    total_memory = memory.total
    memory_percent = memory.percent
    memory_used = memory.used
    memory_av = memory.available
    monitor_info['memInfo'] = {'memTotal': round(total_memory, 2), 'memLoad': round(memory_percent, 2), 'memUsed': round(memory_used, 2),  'memAvailable': round(memory_av, 2), 'unit': 'Byte'}

    # 获取磁盘信息
    disk = psutil.disk_usage('/') #proc/diskstats
    total_disk = disk.total
    disk_percent = disk.percent
    disk_used = disk.used
    disk_av = disk.free
    monitor_info['disk'] = {'mounted':'/', 'available':round(disk_av, 2),  'total': round(total_disk, 2), 'percent': int(disk_percent), 'used': round(disk_used, 2), 'unit': 'Byte'}

    # 获取网络上下行速率
    net_io_counters1 = psutil.net_io_counters() #proc/net/dev
    bytes_sent1 = net_io_counters1.bytes_sent
    bytes_recv1 = net_io_counters1.bytes_recv

    # 等待 1 秒
    await asyncio.sleep(1)

    net_io_counters2 = psutil.net_io_counters()
    bytes_sent2 = net_io_counters2.bytes_sent
    bytes_recv2 = net_io_counters2.bytes_recv

    # 计算网络上下行速率（单位：KB/s）
    send_rate = bytes_sent2 - bytes_sent1
    recv_rate = bytes_recv2 - bytes_recv1
    monitor_info['net'] = {'netInterface': '', 'txByte': bytes_sent2, 'txRate': send_rate, 'rxByte': bytes_recv2, 'rxRate': recv_rate, 'unit': 'Bytes/s'}
    
    mac, ip = get_interface_mac_ip(will_interface)
    monitor_info['mac'] = mac
    monitor_info['ip'] = ip
    monitor_info['upTime'] = get_uptime_days()
    monitor_info['time'] = time.time()
    monitor_info['sn'] = sn
    monitor_info['cpuTemp'] = read_tmp()
    monitor_info['agentVersion'] = VERSION
    print(monitor_info)
    return monitor_info

async def deal_set_ip(cmd):
    global will_ip
    _ip = cmd['set_ip']
    will_ip = _ip
    save_dict_to_json(cmd)
    netmask = cmd.get('netmask', '255.255.254.0')
    gw = cmd.get('gw', '10.0.71.254')
    dns = cmd.get('dns', ['8.8.8.8'])
    print(f'将设置ip地址为: {_ip} 掩码地址 {netmask} 网关 {gw}')
    await set_ip(_ip, netmask, gw, dns)

async def handle_msg_fun(msg):

    if msg is None:
        return
    try:
        cmd = json.loads(msg)
    except Exception:
        return
    if 'set_ip' in cmd:
        await deal_set_ip(cmd)
    if 'set_cmd' in cmd:
        _cmd = cmd['set_cmd']
        _timeout = cmd.get('timeout', 20)
        await run_command_with_timeout(_cmd, timeout=_timeout)


def get_nic_ips():
    """
    获取所有网卡的 IPv4 地址
    :return: 字典，键为网卡名，值为对应的 IPv4 地址
    """
    nic_ips = {}
    net_if_addrs = psutil.net_if_addrs()
    for nic, addrs in net_if_addrs.items():
        for addr in addrs:
            if addr.family == 2:
                nic_ips[nic] = addr.address
    return nic_ips

def can_connect(ip):
    """
    检查指定 IP 地址是否可以通过 TCP 连接到 Google 的 DNS 服务器
    :param ip: 要检查的 IP 地址\n    :return: True 表示可以连接，False 表示不可以
    """
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.bind((ip, 0))
        sock.settimeout(2)
        result = sock.connect_ex(('8.8.8.8', 53))
        sock.close()
        return result == 0
    except Exception as e:
        print(f'检查 {ip} 时出错: {e}')
        return False

async def find_connectable_nics():
    """
    查找可以联网的网卡
    :return: 列表，包含可以联网的网卡名
    """
    nets = await run_command_with_timeout(cat_interface_cmd)
    nic_ips = nets.strip().split('\n')
    return nic_ips

async def run_main():
    global will_interface
    global will_ip
    #init
    try:
        nics = await find_connectable_nics()
        if nics: # 简化条件判断
            intf = nics[0]
            print(f'匹配网卡：{intf}') # 使用 f-string
            will_interface = intf
            # 明确传递接口名称
            mac, ip = get_interface_mac_ip(will_interface)
            if ip:
                will_ip = ip
                print(f'当前ip为：{will_ip}') # 使用 f-string
        if not is_webpage_accessible_urllib('https://www.baidu.com/'):
            print('无法访问网络')
            record_cmd = load_dict_from_json()
            if 'set_ip' in record_cmd:
                await deal_set_ip(record_cmd)
    except Exception as e: # 捕获并打印初始化阶段的错误
        print(f"初始化网络设置时发生错误: {e}")
    # check update
    check_updater_url()
    
    while True:
        #启动时间
        start_time = time.time()
        
        try:
            if is_network_interface_down(will_interface):
                if will_ip is None:
                    await run_command_with_timeout(f'ifconfig {will_interface} up')
                else:
                    await set_ip(will_ip)

            monitor_info = await monitor_device()
            
            msg = send_udp_broadcast(monitor_info) #上游发回的响应

            await handle_msg_fun(msg)

            await check_updater_service()
        except Exception as error:
            print(f"主循环中发生错误: {error}") # 使用 f-string 并提供更明确的错误信息
        need_sleep = 5 - (time.time() - start_time)
        if need_sleep > 0:
            await asyncio.sleep(need_sleep)

print(f'version: V{VERSION}')
try:
    asyncio.run(run_main())
except KeyboardInterrupt:
    pass