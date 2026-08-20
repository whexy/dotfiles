# Hammerspoon configuration (macOS)
#
# Desktop switching (Hyper + 1..9) and moving focused windows (Meh + 1..9).
# Hyper = Ctrl+Cmd+Alt+Shift (held CapsLock via Karabiner)
# Meh   = Ctrl+Cmd+Alt       (held Tab via Karabiner)
args@{
  lib,
  pkgs,
  ...
}:
let
  osConfig = args.osConfig or null;
  enabled = osConfig != null && (osConfig.dotfiles.keyboard.hammerspoon.enable or false);
in
{
  config = lib.mkIf (enabled && pkgs.stdenv.hostPlatform.isDarwin) {
    home.file.".hammerspoon/init.lua".text = ''
      local hyper = {"ctrl", "cmd", "alt", "shift"}
      local meh   = {"ctrl", "cmd", "alt"}

      -- hs.spaces.gotoSpace() and moveWindowToSpace() rely on private macOS
      -- APIs which are broken on current macOS releases. Switching with the
      -- native Ctrl+Fn+Arrow shortcut still works; holding a window's title
      -- bar while switching moves it with us.
      local function orderedSpaces(screen)
        local spaces, err = hs.spaces.spacesForScreen(screen)
        if not spaces then
          hs.alert.show("Cannot read Spaces: " .. (err or "unknown error"))
          return nil, nil
        end

        local desktops = {}
        for _, spaceID in ipairs(spaces) do
          if hs.spaces.spaceType(spaceID) == "user" then
            table.insert(desktops, spaceID)
          end
        end

        return spaces, desktops
      end

      local function indexOf(items, value)
        for i, item in ipairs(items) do
          if item == value then
            return i
          end
        end
      end

      local function switchBy(offset)
        if offset == 0 then
          return
        end

        local key = offset > 0 and "right" or "left"
        for _ = 1, math.abs(offset) do
          -- `fn` is needed for synthetic Ctrl+Arrow events on macOS.
          hs.eventtap.keyStroke({"ctrl", "fn"}, key, 0)
        end
      end

      local function desktopTarget(screen, n)
        local spaces, desktops = orderedSpaces(screen)
        return spaces, desktops and desktops[n]
      end

      local function switchToDesktop(n)
        local screen = hs.screen.mainScreen()
        local spaces, target = desktopTarget(screen, n)
        if not target then
          return
        end

        local current = hs.spaces.activeSpaceOnScreen(screen)
        local currentIndex = indexOf(spaces, current)
        local targetIndex = indexOf(spaces, target)
        if currentIndex and targetIndex then
          switchBy(targetIndex - currentIndex)
        end
      end

      local function moveWindowToDesktop(n)
        local win = hs.window.focusedWindow()
        if not win or not win:isStandard() or win:isFullScreen() then
          return
        end

        local screen = win:screen()
        local spaces, target = desktopTarget(screen, n)
        local currentSpaces = hs.spaces.windowSpaces(win)
        local current = currentSpaces and currentSpaces[1]
        local currentIndex = current and indexOf(spaces, current)
        local targetIndex = target and indexOf(spaces, target)
        if not currentIndex or not targetIndex or currentIndex == targetIndex then
          return
        end

        local offset = targetIndex - currentIndex
        local cursor = hs.mouse.absolutePosition()
        local zoomButton = win:zoomButtonRect()
        local dragPoint
        if zoomButton then
          dragPoint = {x = zoomButton.x - 1, y = zoomButton.y - 1}
        else
          local frame = win:frame()
          dragPoint = {x = frame.x + frame.w / 2, y = frame.y + 8}
        end

        hs.eventtap.event.newMouseEvent(
          hs.eventtap.event.types.leftMouseDown,
          dragPoint
        ):post()
        switchBy(offset)

        local finished = false
        local waiter
        local timeout
        local function finishMove()
          if finished then
            return
          end
          finished = true
          if waiter then waiter:stop() end
          if timeout then timeout:stop() end

          hs.eventtap.event.newMouseEvent(
            hs.eventtap.event.types.leftMouseUp,
            dragPoint
          ):post()
          hs.mouse.absolutePosition(cursor)
        end

        waiter = hs.timer.waitUntil(function()
          local windowSpaces = hs.spaces.windowSpaces(win)
          return windowSpaces and windowSpaces[1] == target
        end, finishMove, 0.05)
        -- Never leave the mouse button held if macOS rejects the switch.
        timeout = hs.timer.doAfter(3, finishMove)
      end

      for n = 1, 9 do
        local desktop = n
        hs.hotkey.bind(hyper, tostring(desktop), function()
          switchToDesktop(desktop)
        end)
        hs.hotkey.bind(meh, tostring(desktop), function()
          moveWindowToDesktop(desktop)
        end)
      end
    '';
  };
}
