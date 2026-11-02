# Release and preview policy

- Production release publication is disabled until explicit authorization and trusted publisher signing exist. The consolidated PR deletes the release job; the main branch workflow is manual-dispatch only, making its older push-only release job unreachable.
- The workflow is not automatically triggered by pushes, pull requests or merges. It can be invoked manually only if the user later authorizes it.
- Preview packaging remains available through scripts/Package-CodexScheduler.ps1, scripts/Package-AeroComponent.ps1 and scripts/Package-ReusableComponents.ps1 using their Preview switches. Preview archives must disclose that they are unsigned.
- SHA-256 manifests verify package content; they are not publisher signatures.
- A production release requires a trusted signing certificate in the release environment, a timestamp service, signature validation, direct Windows acceptance, antivirus checks, and explicit publication authorization. Nothing automatically creates a release.
- Do not disable Bitdefender or broadly exclude program files to make a preview work.
- Weight Trajectory may adopt the selective window, progress, and fallback modules. It must not adopt SettingsStore for durable measurements; that module has no revision or transaction contract and treats corrupt JSON as absent.
