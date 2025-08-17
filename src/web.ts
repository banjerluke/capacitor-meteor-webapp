import { WebPlugin } from '@capacitor/core';

import type { CapacitorMeteorWebAppPlugin } from './definitions';

export class CapacitorMeteorWebAppWeb extends WebPlugin implements CapacitorMeteorWebAppPlugin {
  async echo(options: { value: string }): Promise<{ value: string }> {
    console.log('ECHO', options);
    return options;
  }
}
