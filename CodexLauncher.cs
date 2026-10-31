// Windows GUI-subsystem launcher. No console is allocated to this process or its child.
// Compiled into CodexScheduler.exe by the Windows build; no .NET SDK required on the user's PC.
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

[assembly: AssemblyTitle("Codex Resume Scheduler")]
[assembly: AssemblyProduct("Codex Resume Scheduler")]
[assembly: AssemblyVersion("1.10.0.0")]
[assembly: AssemblyFileVersion("1.10.0.0")]

internal static class CodexLauncher
{
    [STAThread]
    private static int Main(string[] args)
    {
        bool runner = args.Length == 2 &&
            string.Equals(args[0], "--run-job", StringComparison.OrdinalIgnoreCase);
        if (args.Length != 0 && !runner)
        {
            ReportFailure(false, "Unsupported launcher arguments.");
            return 2;
        }

        try
        {
            string folder = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
            string script = Path.Combine(folder, "CodexResumeScheduler.ps1");
            if (!File.Exists(script)) throw new FileNotFoundException("The scheduler script is missing.", script);

            var start = new ProcessStartInfo();
            start.FileName = "pwsh.exe";
            start.WorkingDirectory = folder;
            start.UseShellExecute = false;
            start.CreateNoWindow = true;
            start.WindowStyle = ProcessWindowStyle.Hidden;
            start.Arguments = "-NoLogo -NoProfile " +
                (runner ? "" : "-STA ") +
                "-ExecutionPolicy Bypass -File " + Quote(script) +
                (runner ? " -RunJob -JobFile " + Quote(args[1]) : "");

            using (Process process = Process.Start(start))
            {
                if (process == null) throw new InvalidOperationException("PowerShell did not start.");
                if (runner)
                {
                    // Keep Task Scheduler running until Codex exits; do not detach its job.
                    process.WaitForExit();
                    return process.ExitCode;
                }

                // The Windows Forms window now belongs to PowerShell, but it has no
                // console and is independent of this short-lived launcher.
                return 0;
            }
        }
        catch (Exception ex)
        {
            ReportFailure(runner, ex.Message);
            return 1;
        }
    }

    private static string Quote(string value)
    {
        // Windows CommandLineToArgvW-compatible argument quoting.
        return "\"" + value.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"";
    }

    private static void ReportFailure(bool runner, string message)
    {
        string detail = "Codex Resume Scheduler launch failed: " + message;
        try
        {
            string folder = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "CodexResumeScheduler");
            Directory.CreateDirectory(folder);
            File.AppendAllText(Path.Combine(folder, "launcher-errors.log"),
                DateTimeOffset.Now.ToString("o") + " " + detail + Environment.NewLine);
        }
        catch { }

        if (!runner)
            MessageBox.Show(detail, "Codex Resume Scheduler", MessageBoxButtons.OK, MessageBoxIcon.Error);
    }
}
