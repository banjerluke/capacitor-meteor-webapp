export interface CapacitorMeteorWebAppPlugin {
  echo(options: { value: string }): Promise<{ value: string }>;
}
