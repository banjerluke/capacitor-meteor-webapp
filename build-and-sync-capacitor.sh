#!/usr/bin/env bash

set -euxo pipefail

# Function to shut down running Meteor server(s) after script completes
kill_server() {
  kill $SERVER_PID 2>/dev/null || true
  kill $MONGO_SERVER_PID 2>/dev/null || true
}

# Make sure to clean up on Ctrl+C as well
trap kill_server SIGINT SIGTERM

# This can be anything; just note that if you target a directory within the Meteor project,
# you should add it to .meteorignore so that it doesn't get recursively built
BUILD_DIR=../_app-build

# We need a valid MongoDB connection to boot server - can be local or hosted.
# In this example, we boot up a Meteor dev server and connect to its MongoDB instance.

# If you've set MONGO_URL above to something else, you can comment out the following lines:
meteor run --port 3353 & # MongoDB server is on port N+1
export MONGO_SERVER_PID=$!
export MONGO_URL=mongodb://localhost:3354/ # This goes after dev server is booted
sleep 3

# If you have another MongoDB instance you can connect to, you can put it in below and comment out the above
#export MONGO_URL=mongodb://localhost:27017/meteor

# Port for short-lived server that we'll boot up to grab index.html and manifest.json
export PORT=3333

# Put the URL of the Meteor server you want the built Capacitor app to connect to
export ROOT_URL=https://yourserver.example.com

# Build Meteor app
# Recommended: add `--mobile-settings "mobile-settings.json"` to include public Meteor settings in built app
meteor build --directory $BUILD_DIR/ --headless --server-only --server $ROOT_URL

# Clean www-dist directory
rm -rf capacitor/www-dist || exit 1
mkdir -p capacitor/www-dist

# Copy web.cordova build files into www-dist, excluding sourcemaps
find $BUILD_DIR/bundle/programs/web.cordova -mindepth 1 -maxdepth 1 ! -name '*.map' -exec cp -r {} capacitor/www-dist/ \;

# Install server dependencies, then start server in background and capture PID
(cd $BUILD_DIR/bundle/programs/server && npm install --no-audit --loglevel error --omit=dev)
node $BUILD_DIR/bundle/main.js &
export SERVER_PID=$!
sleep 3

# Remove these two files before downloading them from the server
rm -f capacitor/www-dist/index.html capacitor/www-dist/program.json

# Fetch index.html from server
curl -f --connect-timeout 20 "http://localhost:${PORT}/__cordova/index.html" >capacitor/www-dist/index.html

# Fetch manifest.json and save as program.json for HCP (to get "version" field)
curl -f --connect-timeout 20 "http://localhost:${PORT}/__cordova/manifest.json" >capacitor/www-dist/program.json

# We're done with the server, so shut it down
kill_server

# Sync www files to Capacitor
npx cap sync

# Open (or focus) Xcode so you can build/run/upload the app!
npx cap open ios

