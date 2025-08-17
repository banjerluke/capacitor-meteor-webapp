# Agent Context for Capacitor Meteor WebApp Plugin

## Project Overview

This project creates a Capacitor plugin that enables hot code push functionality for Meteor apps, similar to the existing Cordova plugin but adapted for the Capacitor ecosystem.

## Key Commands

### Development

- `npm run build` - Build the plugin
- `npm run test` - Run tests (when implemented)
- `npm run lint` - Run ESLint
- `npm run fmt` - Format code with Prettier

### iOS Development

- Open `ios/` directory in Xcode for native iOS development
- Use iOS simulator for testing
- Build and test with example app in `example-app/`

## Project Structure

### Source Code

- `src/` - TypeScript source code for the plugin
  - `definitions.ts` - Plugin interface definitions
  - `web.ts` - Web implementation
  - `index.ts` - Main plugin export
- `ios/Sources/CapacitorMeteorWebapp/` - iOS native implementation
- `android/` - Android implementation (future, not yet implemented)

### Reference Materials

- `reference-plugin-cordova/` - Original Cordova plugin for reference
- `reference-capgo/` - Capgo CapacitorUpdater plugin for reference
- `CordovaPluginOverview.md` - Detailed explanation of Cordova plugin architecture

### Documentation

- `PLAN.md` - Implementation plan and architecture decisions
- `README.md` - Public documentation
- This `AGENT.md` - Context for AI agents
