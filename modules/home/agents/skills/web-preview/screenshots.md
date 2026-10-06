# Publishable screenshots

These rules cover images that go into a README, docs, or anywhere public.
Capture them with Playwright as SKILL.md describes.

- Use real data from a real run, not mock data, unless he says otherwise.
- Capture at `deviceScaleFactor: 2`.
- No scrollbars or cut-off content in the frame. Size the viewport to the
  content, scroll inner panels to the meaningful part with `evaluate_script`,
  and hide scrollbars for the capture only
  (`* { scrollbar-width: none } ::-webkit-scrollbar { display: none }`).
- Crop to the subject; keep the app's own design.
- Compress losslessly with `oxipng`; `pngquant` leaves artifacts on
  transparent edges.
- Edit images with `nix run nixpkgs#imagemagick -- …` when Python imaging is
  not installed.
- Read every final image yourself before committing it.
