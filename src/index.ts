import { registerPlugin } from '@capacitor/core';

import type { MeteorWebappPlugin, UpdateAvailableEvent } from './definitions';

const MeteorWebapp = registerPlugin<MeteorWebappPlugin>('CapacitorMeteorWebapp', {
  web: () => import('./web').then((m) => new m.MeteorWebappWeb()),
});

// WebAppLocalServer compatibility shim
(window as any).WebAppLocalServer = {
  onNewVersionReady(callback: (event: UpdateAvailableEvent) => void): void {
    MeteorWebapp.addListener('updateAvailable', callback);
  },

  async getNewCordovaVersion(): Promise<string | null> {
    const update = await MeteorWebapp.isUpdateAvailable();
    if (update.available) {
      const current = await MeteorWebapp.getCurrentVersion();
      return current.version;
    }
    return null;
  },

  async switchToPendingVersion(): Promise<void> {
    return MeteorWebapp.reload();
  },
};

export * from './definitions';
export { MeteorWebapp };
