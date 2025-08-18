# Agent Context for Capacitor Meteor WebApp Plugin

## Project Overview

This project creates a Capacitor plugin that enables hot code push functionality for Meteor apps, similar to the existing Cordova plugin but adapted for the Capacitor ecosystem.

## Key Commands

### Development

- `npm run build` - Build the plugin
- `npm run test` - Run tests (if/when implemented)
- `npm run lint` - Run ESLint
- `npm run fmt` - Format code with Prettier and SwiftLint - run this before committing changes

## Project Structure

### Source Code

- `src/` - TypeScript source code for the plugin
  - `definitions.ts` - Plugin interface definitions
  - `web.ts` - Web implementation
  - `index.ts` - Main plugin export
- `ios/Sources/CapacitorMeteorWebapp/` - iOS native implementation
- `android/` - Android implementation (future, not yet implemented)

### Documentation

- `PLAN.md` - Implementation plan and architecture decisions
- `README.md` - Public documentation
- This `AGENT.md` - Context for AI agents

## Workflow

There is NO AUTOMATED INTEGRATION TESTING at this time. Rely on the user to test the plugin on real devices and provide you with logs.
