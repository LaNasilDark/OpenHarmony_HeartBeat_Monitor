#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
IP地址与整数相互转换工具
支持IPv4地址的大端序和小端序转换
"""

import socket
import struct
import ipaddress


class IPConverter:
    """IP地址与整数转换工具类"""
    
    @staticmethod
    def ip_to_int_big_endian(ip_str):
        """
        将IP地址字符串转换为大端序整数
        Args:
            ip_str (str): IP地址字符串，如 "192.168.1.1"
        Returns:
            int: 对应的大端序整数
        """
        # 方法1：使用socket模块
        return struct.unpack("!I", socket.inet_aton(ip_str))[0]
    
    @staticmethod
    def int_to_ip_big_endian(ip_int):
        """
        将大端序整数转换为IP地址字符串
        Args:
            ip_int (int): 大端序整数
        Returns:
            str: 对应的IP地址字符串
        """
        return socket.inet_ntoa(struct.pack("!I", ip_int))
    
    @staticmethod
    def ip_to_int_little_endian(ip_str):
        """
        将IP地址字符串转换为小端序整数
        Args:
            ip_str (str): IP地址字符串，如 "10.0.71.254"
        Returns:
            int: 对应的小端序整数
        """
        parts = list(map(int, ip_str.split('.')))
        # 小端序：最后一个字节在最高位
        return (parts[3] << 24) | (parts[2] << 16) | (parts[1] << 8) | parts[0]
    
    @staticmethod
    def int_to_ip_little_endian(ip_int):
        """
        将小端序整数转换为IP地址字符串
        Args:
            ip_int (int): 小端序整数
        Returns:
            str: 对应的IP地址字符串
        """
        part1 = ip_int & 0xFF
        part2 = (ip_int >> 8) & 0xFF
        part3 = (ip_int >> 16) & 0xFF
        part4 = (ip_int >> 24) & 0xFF
        return f"{part1}.{part2}.{part3}.{part4}"
    
    @staticmethod
    def ip_to_int_manual(ip_str):
        """
        手动实现IP到大端序整数的转换
        Args:
            ip_str (str): IP地址字符串
        Returns:
            int: 对应的大端序整数
        """
        parts = list(map(int, ip_str.split('.')))
        return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]
    
    @staticmethod
    def int_to_ip_manual(ip_int):
        """
        手动实现大端序整数到IP的转换
        Args:
            ip_int (int): 大端序整数
        Returns:
            str: 对应的IP地址字符串
        """
        part1 = (ip_int >> 24) & 0xFF
        part2 = (ip_int >> 16) & 0xFF
        part3 = (ip_int >> 8) & 0xFF
        part4 = ip_int & 0xFF
        return f"{part1}.{part2}.{part3}.{part4}"


def test_conversions():
    """测试所有转换方法"""
    converter = IPConverter()
    
    # 测试用例
    test_cases = [
        "192.168.1.1",
        "10.0.0.1", 
        "10.0.71.254",
        "8.8.8.8",
        "255.255.255.255",
        "0.0.0.0"
    ]
    
    print("=" * 80)
    print("IP地址与整数转换测试")
    print("=" * 80)
    
    for ip in test_cases:
        print(f"\n原始IP地址: {ip}")
        print("-" * 40)
        
        # 大端序转换
        big_endian_int = converter.ip_to_int_big_endian(ip)
        big_endian_back = converter.int_to_ip_big_endian(big_endian_int)
        
        # 小端序转换
        little_endian_int = converter.ip_to_int_little_endian(ip)
        little_endian_back = converter.int_to_ip_little_endian(little_endian_int)
        
        # 手动大端序转换
        manual_int = converter.ip_to_int_manual(ip)
        manual_back = converter.int_to_ip_manual(manual_int)
        
        # Python内置方法
        builtin_int = int(ipaddress.IPv4Address(ip))
        builtin_back = str(ipaddress.IPv4Address(builtin_int))
        
        print(f"大端序整数:     {big_endian_int:>12} -> {big_endian_back}")
        print(f"小端序整数:     {little_endian_int:>12} -> {little_endian_back}")
        print(f"手动大端序:     {manual_int:>12} -> {manual_back}")
        print(f"内置方法:       {builtin_int:>12} -> {builtin_back}")
        
        # 验证一致性
        assert big_endian_back == ip, f"大端序转换错误: {big_endian_back} != {ip}"
        assert little_endian_back == ip, f"小端序转换错误: {little_endian_back} != {ip}"
        assert manual_back == ip, f"手动转换错误: {manual_back} != {ip}"
        assert builtin_back == ip, f"内置方法转换错误: {builtin_back} != {ip}"


def interactive_converter():
    """交互式转换工具"""
    converter = IPConverter()
    
    print("\n" + "=" * 50)
    print("交互式IP地址转换工具")
    print("=" * 50)
    print("1. IP -> 大端序整数")
    print("2. IP -> 小端序整数") 
    print("3. 大端序整数 -> IP")
    print("4. 小端序整数 -> IP")
    print("5. 退出")
    
    while True:
        try:
            choice = input("\n请选择操作 (1-5): ").strip()
            
            if choice == '1':
                ip = input("请输入IP地址: ").strip()
                result = converter.ip_to_int_big_endian(ip)
                print(f"大端序整数: {result}")
                
            elif choice == '2':
                ip = input("请输入IP地址: ").strip()
                result = converter.ip_to_int_little_endian(ip)
                print(f"小端序整数: {result}")
                
            elif choice == '3':
                num = int(input("请输入大端序整数: ").strip())
                result = converter.int_to_ip_big_endian(num)
                print(f"IP地址: {result}")
                
            elif choice == '4':
                num = int(input("请输入小端序整数: ").strip())
                result = converter.int_to_ip_little_endian(num)
                print(f"IP地址: {result}")
                
            elif choice == '5':
                print("再见！")
                break
                
            else:
                print("无效选择，请输入1-5")
                
        except ValueError as e:
            print(f"输入错误: {e}")
        except Exception as e:
            print(f"转换错误: {e}")


if __name__ == "__main__":
    # 运行测试
    test_conversions()
    
    # 特殊测试：验证OpenHarmony的转换
    print("\n" + "=" * 50)
    print("OpenHarmony特殊案例验证")
    print("=" * 50)
    
    converter = IPConverter()
    test_ip = "10.0.71.254"
    expected_result = 167790590
    
    little_endian_result = converter.ip_to_int_little_endian(test_ip)
    print(f"IP: {test_ip}")
    print(f"期望结果: {expected_result}")
    print(f"小端序结果: {little_endian_result}")
    print(f"匹配: {'是' if little_endian_result == expected_result else '否'}")
    
    # 反向验证
    back_to_ip = converter.int_to_ip_little_endian(expected_result)
    print(f"反向转换: {expected_result} -> {back_to_ip}")
    
    # 启动交互式工具
    interactive_converter()