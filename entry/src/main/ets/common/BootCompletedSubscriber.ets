
import { hilog } from '@kit.PerformanceAnalysisKit';
import type { BusinessError } from '@ohos.base';
import { commonEventManager } from '@kit.BasicServicesKit';

const TAG = 'BootCompletedSubscriber';
const DOMAIN = 0x0001;

export class BootCompletedSubscriber {
  subscriber: commonEventManager.CommonEventSubscriber | null = null;

  // 订阅开机完成事件
  subscribe(callback: (err: BusinessError, data: commonEventManager.CommonEventData) => void) {
    const subscribeInfo: commonEventManager.CommonEventSubscribeInfo= {
      events: [commonEventManager.Support.COMMON_EVENT_BOOT_COMPLETED,commonEventManager.Support.COMMON_EVENT_LOCKED_BOOT_COMPLETED,commonEventManager.Support.COMMON_EVENT_SCREEN_ON]
    };

    commonEventManager.createSubscriber(subscribeInfo).then((subscriber: commonEventManager.CommonEventSubscriber) => {
      this.subscriber = subscriber;
      commonEventManager.subscribe(this.subscriber, (err: BusinessError, data: commonEventManager.CommonEventData) => {
        hilog.info(DOMAIN, TAG, 'Received COMMON_EVENT_BOOT_COMPLETED event.');
        if (err) {
          hilog.error(DOMAIN, TAG, `Subscription callback error: ${JSON.stringify(err)}`);
        } else {
          hilog.info(DOMAIN, TAG, `Boot completed event received: ${JSON.stringify(data)}`);
          // 在这里可以执行开机后需要进行的操作
        }
        callback(err, data);
      });
    }).catch((err: BusinessError) => {
      hilog.error(DOMAIN, TAG, `Failed to create subscriber: ${JSON.stringify(err)}`);
    });
  }

  // 取消订阅
  unsubscribe() {
    if (this.subscriber) {
      commonEventManager.unsubscribe(this.subscriber, (err: BusinessError) => {
        if (err) {
          hilog.error(DOMAIN, TAG, `Failed to unsubscribe: ${JSON.stringify(err)}`);
        } else {
          hilog.info(DOMAIN, TAG, 'Unsubscribed successfully.');
          this.subscriber = null;
        }
      });
    }
  }
}
