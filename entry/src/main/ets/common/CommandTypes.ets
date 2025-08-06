export interface CommandResponse {
  success: boolean;
  message: string;
}

export interface WifiCommandData {
  ssid?: string;
  password?: string;
  ipAddress?: string;
  gateway?: string;
  dns?: string;
  bssid?: string;
}

export interface EthernetCommandData {
  ipAddress?: string;
  gateway?: string;
  netmask?: string;
  dns?: string;
}

export interface TargetIpCommandData {
  targetIp?: string;
}

export interface BaseCommand {
  type: string;
}

export interface WifiConfigCommand extends BaseCommand {
  type: 'configure_wifi';
  data: WifiCommandData;
}

export interface EthernetConfigCommand extends BaseCommand {
  type: 'configure_ethernet';
  data: EthernetCommandData;
}

export interface ForgetWifiCommand extends BaseCommand {
  type: 'forget_wifi';
}

export interface RestartMonitorCommand extends BaseCommand {
  type: 'restart_monitor';
}

export interface UpdateTargetIpCommand extends BaseCommand {
  type: 'update_target_ip';
  data: TargetIpCommandData;
}

export type Command = WifiConfigCommand | EthernetConfigCommand | ForgetWifiCommand | RestartMonitorCommand | UpdateTargetIpCommand;
