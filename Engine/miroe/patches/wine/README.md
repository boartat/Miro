# Wine patches for the miroe engine (ARM64, upstream Wine)

Applied on top of `WINE_UPSTREAM` in `../../sources.conf` by `scripts/build-wine-upstream.sh` (the source worktree keeps them on its `miroe` branch).

| Patch | What it does | Checked |
| --- | --- | --- |
| `0001` imm32 composition window | When a program gives no usable composition position (an empty `CFS_RECT` or none at all, as Steam's Chromium does) and leaves the composition to the default IME window, show it at the thread's caret or where the text field was clicked, with a font sized for the window's DPI. Before, the window was 1x1 at the screen corner and Korean syllables stayed invisible until committed. | Steam on miroe, Gureum 2-set: ㄱ → 그 → 근 shown while composing, 근+ㅏ → 그 + 나, Backspace removes one jamo |
| `0002` winemac remote windows | A window another process draws into (a `CALayerHost`, as Chromium's GPU process draws the browser's windows) leaves its own surface out while only the window background colour was drawn into it, as a flip-model swapchain does on Windows: the window is clear until that process's first frame and still takes clicks over all of it. Sticky for a window that ever showed another process's layer, since Chromium makes a popup's swapchain anew each time it opens; anything drawn into the surface shows as before | Steam on miroe: menus flashed the light window background for 2 frames each time they opened (recorded); after it and Mullion `0005`, six openings with no white or black frame |

These are LGPL-2.1-or-later like Wine, written with AI assistance and not submitted upstream (a Wine contribution needs the author's real name).
