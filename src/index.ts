import { registerPlugin } from '@capacitor/core';

import type { CapacitorMeteorWebAppPlugin } from './definitions';

const CapacitorMeteorWebApp = registerPlugin<CapacitorMeteorWebAppPlugin>('CapacitorMeteorWebApp', {
  web: () => import('./web').then((m) => new m.CapacitorMeteorWebAppWeb()),
});

export * from './definitions';
export { CapacitorMeteorWebApp };
