# SA Cook Assistant Windows Preview 5.46

- Fixes in-app Update by running the installer outside the installed application folder before replacing it.
- Uses a Windows PowerShell 5.1-compatible wait loop and allows up to 90 seconds for the old app to close.
- Hides the taskbar icon while the presenter window is open. The icon appears only while minimized so the window can be restored.
- Prevents duplicate background instances; opening the EXE again restores and focuses the existing presenter window.
- Retains the improved culinary speech recognition and concise B2 answers from 5.45.
