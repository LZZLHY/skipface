import { hilog } from '@kit.PerformanceAnalysisKit';
import { BackupExtensionAbility, BundleVersion } from '@kit.CoreFileKit';

const DOMAIN: number = 0xF1AC;
const TAG: string = 'SkipfaceBackup';

export default class SkipfaceBackupAbility extends BackupExtensionAbility {
  async onBackup(): Promise<void> {
    hilog.info(DOMAIN, TAG, '%{public}s', 'onBackup ok');
    await Promise.resolve();
  }

  async onRestore(bundleVersion: BundleVersion): Promise<void> {
    hilog.info(DOMAIN, TAG, '%{public}s', `onRestore ok ${JSON.stringify(bundleVersion)}`);
    await Promise.resolve();
  }
}