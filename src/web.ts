import { WebPlugin } from '@capacitor/core';

import type { MeteorWebappPlugin } from './definitions';

export class MeteorWebappWeb extends WebPlugin implements MeteorWebappPlugin {
  async checkForUpdates(): Promise<void> {
    console.warn('MeteorWebapp.checkForUpdates() is not available on web platform');
  }

  async startupDidComplete(): Promise<void> {
    console.warn('MeteorWebapp.startupDidComplete() is not available on web platform');
  }

  async getCurrentVersion(): Promise<{ version: string }> {
    console.warn('MeteorWebapp.getCurrentVersion() is not available on web platform');
    return { version: '1.0.0' };
  }

  async isUpdateAvailable(): Promise<{ available: boolean }> {
    console.warn('MeteorWebapp.isUpdateAvailable() is not available on web platform');
    return { available: false };
  }

  async reload(): Promise<void> {
    console.warn('MeteorWebapp.reload() is not available on web platform');
    window.location.reload();
  }
}
