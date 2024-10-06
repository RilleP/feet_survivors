@echo off
set optimization=%1
IF NOT DEFINED optimization set optimization=speed

@echo on
odin build src -target:js_wasm32 -no-entry-point -out:game.wasm -o:%optimization% -ignore-unknown-attributes