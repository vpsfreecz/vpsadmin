#!/usr/bin/env bash

npm install @xterm/xterm
cp node_modules/@xterm/xterm/lib/xterm.{js,js.map} public/
cp node_modules/@xterm/xterm/css/xterm.css public/

npm install @xterm/addon-fit
cp node_modules/@xterm/addon-fit/lib/addon-fit.{js,js.map} public/
