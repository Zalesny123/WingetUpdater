using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

public static class FakeWingetStreams
{
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GetStdHandle(int nStdHandle);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr handle);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetStdHandle(int nStdHandle, IntPtr handle);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint GetFileType(IntPtr handle);

    public static int Main(string[] args)
    {
        if (args.Length != 2 || !String.Equals(args[0], "early-eof", StringComparison.Ordinal))
        {
            return 64;
        }

        IntPtr standardOutput = GetStdHandle(-11);
        IntPtr standardError = GetStdHandle(-12);
        Console.Out.Dispose();
        Console.Error.Dispose();
        SetStdHandle(-11, new IntPtr(-1));
        SetStdHandle(-12, new IntPtr(-1));
        bool outputClosed = CloseHandle(standardOutput);
        int outputError = Marshal.GetLastWin32Error();
        bool errorClosed = CloseHandle(standardError);
        int errorError = Marshal.GetLastWin32Error();
        for (long handleValue = 4; handleValue < 65536; handleValue += 4)
        {
            IntPtr handle = new IntPtr(handleValue);
            if (GetFileType(handle) == 3)
            {
                CloseHandle(handle);
            }
        }
        Thread.Sleep(200);
        File.WriteAllText(
            args[1],
            String.Format("{0:o}|stdout={1}:{2}|stderr={3}:{4}", DateTime.UtcNow, outputClosed, outputError, errorClosed, errorError));
        Thread.Sleep(1500);
        return 0;
    }
}
