# Rendepth Reshade
![Rendepth_Reshade_Title](https://github.com/user-attachments/assets/ef0a839f-d640-4399-9f48-5f993e8d1248)

2D-to-3D Conversion Reshade Plug-In.

## Features
- Optimized to provide minimal artifacts, halos, or ghosting.
- Includes newly developed red/cyan anaglyph filter for more accurate colors.
- Side-by-side mode (half-width) works with popular XR glasses and 3D displays.
- Simple settings (only 3 sliders) for easy adjustment and minimal errors.
- Stereoscopic mouse cursor for using menus in SBS mode (press '+' key).

## 3D Screenshots

![ACShadows_Crouch_anaglyph](https://github.com/user-attachments/assets/c7ea9e1e-f611-40b7-8572-8e7e66d33eb3)

![ACShadows_Crouch_sbs](https://github.com/user-attachments/assets/166b49b1-2cc1-4fdb-b299-b82d6815ac7a)

![ACShadows_Blade_anaglyph](https://github.com/user-attachments/assets/c3499474-3d5e-4498-a20d-29d4509be2cd)

![ACShadows_Blade_sbs](https://github.com/user-attachments/assets/64ebdffe-7f25-4a63-b3ab-991fc0c6799f)

![ACShadows_Stereo_Cursor_anaglyph](https://github.com/user-attachments/assets/ab7f0c18-c9f3-457f-a38b-0d64d5435fa2)

![ACShadows_Stereo_Cursor_sbs](https://github.com/user-attachments/assets/351018ef-ec0e-4fda-bf66-e592232a2822)

## Installation

- Download the latest Reshade installer from: https://reshade.me
- Run the Reshade executable and choose the game you wish to mod.
- Selected graphics API is usually correct, only the "Standard effects" are needed.
- Next download the folders from this Github, `Shaders` and `Textures`.
- Alternatively, download the latest release zip from the releases section.
- Launch the game and do the Reshade tutorial, if unfamiliar.
- In the `Settings` tab, click `+` to add a new `Effect search paths` for the `Shaders` folder you downloaded.
- Click `+` on the `Texture search paths` to add a new path to the `Textures` folder you downloaded.
- Go back to the `Home` Reshade tab and click `Reload`.
- See `Rendepth [Rendepth.fx]` appear in the list, and click the checkbox to enable it.

## Settings

After installation, press the Reshade key (default `Home` key) to access the menu. Make sure the checkbox next to `Rendepth [Rendepth.fx]` is checked to enable the 2D-to-3D conversion shader. In the Rendepth menu, the top slider is the distance between your eyes. In most cases you can set the value to `100` for maximum 3D effect, though lowering the value can help mitigate artifacts. The middle option controls how strong the depth is evaluated to. It is typically safe to increase this value to `100` for a more extreme depth range. The bottom most slider is the parallax overlap. This shifts the images left or right to make the overlap more comfortable (plane of focus). This value is content dependent but usually acceptable near the center. For most games, setting the values to `100` `100` `64` provides the best effect. After you find acceptable settings, click the `Performance mode` checkbox on the bottom right to optimize the shader performance.

## Troubleshooting

Many games will work with the default depth buffer settings. However, you may have to change the configuration if the game is not supported out of the box. In the Advanced Settings for Rendepth, click the `Show Depth Buffer` checkbox. This will show the game color on the left and the Z buffer on the right. For things to work properly, nearby objects (such as the character or gun) should be almost white, and the sky should be black, with a gradient in-between. If this is not the case (e.g. the screen is fully black or white, or odd) then see below. There are a few Reshade options that alter the depth buffer. You can click the `Edit global preprocessor definitions` to open the menu. The most common error is that the depth buffer is reversed (e.g. black where it should be white, or the entire screen white) in which case you can enter `1` for the `RESHADE_DEPTH_INPUT_IS_REVERSED` value. If the depth buffer looks upside-down (e.g. the floor is on the ceiling) then set `RESHADE_DEPTH_INPUT_IS_UPSIDE_DOWN` to `1`. The other options here are rarely used. Additionally, the way the depth buffer is detected can be customized, particularly if you see artifacts or flashing objects. If you experience issues, click the Reshade `Add-ons` tab and look under `Generic Depth`. The most common cause of a blank depth buffer is the setting for `Aspect ratio heuristic`, which can be either `Similar aspect ratio` or `Mutiples of resolution`. If you see any flicker or artifacts, try checking both `Copy depth buffer before clear operations` and `Copy depth buffer before fullscreen draw calls`. Infrequently, you may have to change `Draw stats heuristic` to either `Higher vertices` or `Higher draw calls`. The game settings themselves may have to be adjusted. In most cases you want to have the game display resolution set to the screen native resolution. HDR should be disabled. Scaling technology, like DLSS/FSR/XeSS, can work, however you might have to tweak things. Particularly certain combinations of scaling and frame generation may cause the depth buffer to be blank, though this can be game specific and also vary depending on your hardware vendor. If none of these options seem to fix it, it's possible Reshade cannot read the depth buffer for that game, in which case it's just unsupported. Some 3D display devices may need additional processing for 3D, in which case it's a good idea to lower in-game settings (e.g. set DLSS to Performance mode) for a smoother gameplay experience. Settings you adjust in the Reshade menu will save, on a per-game-basis, so this setup is only required to be done once.
