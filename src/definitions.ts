import type { PluginListenerHandle } from '@capacitor/core';

export interface CapacitorMeteorWebAppPlugin {

  /**
   * Signal that the app startup has completed
   */
  startupDidComplete(): Promise<void>;

  /**
   * Get the current version of the app
   */
  getCurrentVersion(): Promise<{ version: string }>;

  /**
   * Check if an update is available
   */
  isUpdateAvailable(): Promise<{ available: boolean }>;

  /**
   * Reload the app with the latest version
   */
  reload(): Promise<void>;

  /**
   * Listen for update available events
   */
  addListener(
    eventName: 'updateAvailable',
    listenerFunc: (event: UpdateAvailableEvent) => void,
  ): Promise<PluginListenerHandle>;

  /**
   * Listen for update complete events
   */
  addListener(
    eventName: 'updateComplete',
    listenerFunc: (event: UpdateCompleteEvent) => void,
  ): Promise<PluginListenerHandle>;

  /**
   * Remove all listeners
   */
  removeAllListeners(): Promise<void>;
}

export interface UpdateAvailableEvent {
  version: string;
}

export interface UpdateCompleteEvent {
  version: string;
  isReady: boolean;
}

export enum MeteorWebAppError {
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
