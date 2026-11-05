---
description: Build, install to /Applications, and launch Wiki LLM (macOS)
---

Build (per build-app), then install and launch:

1. `osascript -e 'quit app "Wiki LLM"'`
2. `rm -rf "/Applications/Wiki LLM.app" && cp -R "/tmp/mvbuild/Build/Products/Debug/Wiki LLM.app" "/Applications/"`
3. `open "/Applications/Wiki LLM.app"`
4. Optionally screenshot the window for verification with `screencapture -x -o -R"<x,y,w,h>" /tmp/app.png`.

Report install + launch status.
