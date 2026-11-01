Native Windows v1.8 ProgressBar — recoloring test

Run: double-click Start-Native-Bar-Color-Lab.vbs
Prerequisite: Windows with PowerShell 7.

The first bar is an unmodified WinForms ProgressBar at the original
v1.8 dimensions (400 x 13).

All other colors use frames sampled from that exact original, remapped
through GDI+ RGB channel matrices. Grey tracks and white highlights
remain neutral. There are NO replacement bar skins or gradient templates.

The slider changes the single original native bar's percentage.
The colored copies follow it. The source is sampled about 13 times per
second; the application does not alter your scheduler or its settings.

This is a visual feasibility experiment, not a published product change.
Do not assume animated theme reflections will survive until the capture
and animation tests have been checked on your Windows version.
