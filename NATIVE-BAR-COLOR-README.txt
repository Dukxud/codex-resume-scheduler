Original Windows v1.8 Bar + Aero Liquid — LIVE preview

Run: double-click Start-Native-Bar-Color-Lab.vbs
Requires Windows and PowerShell 7.

The ORIGINAL GREEN row is still the exact v1.8 WinForms ProgressBar,
with Windows visual styles active. The other five bars still use a
color remap of the actual original Windows control's rendered pixels.

NEW:
  - Aero Liquid checked: soft curved internal reflections, caustics,
    and a rounded liquid front travel inside the existing Windows fill.
  - Uncheck Aero Liquid: return to the exact approved recolored bars.
  - Aero intensity: change the strength of the optical overlay.
  - Percentage slider: real native progress value remains authoritative.

No custom executable, WebView2 dependency, commercial controls, or
third-party runtime. All visuals come from Windows Forms and GDI+.
This is a small Aero-inspired optical overlay at the original 400x13
Windows bar dimensions, not a full GPU fluid simulation.

This is an unmerged preview. It changes no scheduler settings,
scheduled runs, or production UI. Windows CI captures OFF, ON, and
two motion phases at an unchanged percentage for comparison.
