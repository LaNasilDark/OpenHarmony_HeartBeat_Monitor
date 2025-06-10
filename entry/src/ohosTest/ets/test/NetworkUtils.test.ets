import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { NetworkUtils } from '../../../main/ets/monitorservice/NetworkUtils';

export default function NetworkUtilsTest() {
  describe('NetworkUtils测试', () => {
    
    it('应该正确验证有效的IP地址', 0, () => {
      // 测试有效IP地址
      expect(NetworkUtils.isValidIP('192.168.1.1')).assertTrue();
      expect(NetworkUtils.isValidIP('10.0.0.1')).assertTrue();
      expect(NetworkUtils.isValidIP('172.16.0.1')).assertTrue();
      expect(NetworkUtils.isValidIP('8.8.8.8')).assertTrue();
    });

    it('应该拒绝无效的IP地址', 0, () => {
      // 测试无效IP地址
      expect(NetworkUtils.isValidIP('256.1.1.1')).assertFalse();
      expect(NetworkUtils.isValidIP('192.168.1')).assertFalse();
      expect(NetworkUtils.isValidIP('not.an.ip.address')).assertFalse();
      expect(NetworkUtils.isValidIP('')).assertFalse();
    });

    it('应该正确识别私有IP地址', 0, () => {
      // 测试私有IP地址
      expect(NetworkUtils.isPrivateIP('192.168.1.1')).assertTrue();
      expect(NetworkUtils.isPrivateIP('10.0.0.1')).assertTrue();
      expect(NetworkUtils.isPrivateIP('172.16.0.1')).assertTrue();
      
      // 测试公网IP地址
      expect(NetworkUtils.isPrivateIP('8.8.8.8')).assertFalse();
      expect(NetworkUtils.isPrivateIP('1.1.1.1')).assertFalse();
    });

    it('应该正确计算CIDR', 0, () => {
      // 测试CIDR计算
      expect(NetworkUtils.calculateCIDR('255.255.255.0')).assertEqual(24);
      expect(NetworkUtils.calculateCIDR('255.255.0.0')).assertEqual(16);
      expect(NetworkUtils.calculateCIDR('255.0.0.0')).assertEqual(8);
    });

    it('应该正确格式化网络速度', 0, () => {
      // 测试网络速度格式化
      expect(NetworkUtils.formatNetworkSpeed(512)).assertEqual('512 B/s');
      expect(NetworkUtils.formatNetworkSpeed(1536)).assertEqual('1.50 KB/s');
      expect(NetworkUtils.formatNetworkSpeed(1048576)).assertEqual('1.00 MB/s');
    });

    it('应该正确获取网络类型描述', 0, () => {
      // 测试网络类型描述
      expect(NetworkUtils.getNetworkTypeDescription(1)).assertEqual('WiFi');
      expect(NetworkUtils.getNetworkTypeDescription(2)).assertEqual('移动网络');
      expect(NetworkUtils.getNetworkTypeDescription(3)).assertEqual('以太网');
      expect(NetworkUtils.getNetworkTypeDescription(99)).assertEqual('未知网络');
    });
  });
}
