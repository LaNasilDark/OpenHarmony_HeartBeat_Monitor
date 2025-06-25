import { ExtensionAbility, Want } from '@kit.AbilityKit';
import { commonEventManager } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BootCompletedSubscriber } from '../common/BootCompletedSubscriber';
import type { BusinessError } from '@ohos.base';



const TAG = 'BootEventService';
const DOMAIN = 0x0001;

export default class BootEventService extends ExtensionAbility {
  private subscriber: BootCompletedSubscriber | null = null;

  onCreate(want: Want): void {
    hilog.info(DOMAIN, TAG, 'BootEventService onCreate, want: ' + JSON.stringify(want));
    this.subscriber = new BootCompletedSubscriber();
    this.subscriber.subscribe((err: BusinessError, data: commonEventManager.CommonEventData) => {
      if (err) {
        hilog.error(DOMAIN, TAG, 'Subscription callback error: ' + JSON.stringify(err));
      } else {
        hilog.info(DOMAIN, TAG, 'Subscription callback success, data: ' + JSON.stringify(data));
        // TODO: 在这里可以执行开机后需要进行的操作，例如启动监控服务
        
      }
    });
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'BootEventService onDestroy');
    if (this.subscriber) {
      this.subscriber.unsubscribe();
      this.subscriber = null;
    }
  }
}

