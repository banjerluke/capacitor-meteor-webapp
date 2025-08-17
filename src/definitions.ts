import type { PluginListenerHandle } from '@capacitor/core';

export interface MeteorWebappPlugin {
  checkForUpdates(): Promise<void>;
  startupDidComplete(): Promise<void>;
  getCurrentVersion(): Promise<{ version: string }>;
  isUpdateAvailable(): Promise<{ available: boolean }>;
  reload(): Promise<void>;

  // Event listener methods
  addListener(
    eventName: 'updateAvailable',
    listenerFunc: (event: UpdateAvailableEvent) => void,
  ): Promise<PluginListenerHandle>;

  addListener(
    eventName: 'updateComplete',
    listenerFunc: (event: UpdateCompleteEvent) => void,
  ): Promise<PluginListenerHandle>;

  removeAllListeners(): Promise<void>;
}

export interface UpdateAvailableEvent {
  version: string;
}

export interface UpdateCompleteEvent {
  version: string;
  isReady: boolean;
}

export enum MeteorWebappError {
  DOWNLOAD_FAILED = 'DOWNLOAD_FAILED',
  VALIDATION_FAILED = 'VALIDATION_FAILED',
  BLACKLISTED_VERSION = 'BLACKLISTED_VERSION',
  STARTUP_TIMEOUT = 'STARTUP_TIMEOUT',
  FILE_SYSTEM_ERROR = 'FILE_SYSTEM_ERROR',
}

declare global {
  interface Window {
    WebAppLocalServer: {
      onNewVersionReady(callback: (event: UpdateAvailableEvent) => void): void;
      getNewCordovaVersion(): Promise<string | null>;
      switchToPendingVersion(): Promise<void>;
    };
  }
}
